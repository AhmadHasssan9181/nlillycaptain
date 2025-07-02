import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'passenger_model.dart';

class PassengerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current timestamp and user login info for logging
  final String _currentTimestamp = "2025-06-04 00:20:35";
  final String _currentUserLogin = "Lilydebug";

  // Get all available passenger requests from real users
  Future<List<PassengerRequest>> getNearbyPassengerRequests(LatLng driverLocation, double radiusKm) async {
    try {
      print('Fetching passenger requests near (${driverLocation.latitude}, ${driverLocation.longitude})');

      // Get all requests with status "isLooking" (your actual status)
      final snapshot = await _firestore
          .collection('PassengerRequests')
          .where('status', isEqualTo: 'isLooking')
          .orderBy('createdAt', descending: false) // Get oldest requests first
          .get();

      print('Found ${snapshot.docs.length} "isLooking" passenger requests in database');

      if (snapshot.docs.isEmpty) {
        print('No "isLooking" passenger requests found in the database');
        return [];
      }

      List<PassengerRequest> allRequests = [];

      // Convert all documents to PassengerRequest objects
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          print('Processing request ${doc.id}: ${data['passengerName']} - Status: ${data['status']}');

          // Create PassengerRequest from your actual data structure
          final request = PassengerRequest(
            id: doc.id,
            passengerId: data['passengerId'] ?? '',
            passengerName: data['passengerName'] ?? 'Unknown Passenger',
            passengerImage: data['passengerImage'] ?? 'https://randomuser.me/api/portraits/women/44.jpg',
            passengerRating: 4.5, // Default rating since not in your data
            pickupLat: (data['pickupLat'] ?? 0).toDouble(),
            pickupLng: (data['pickupLng'] ?? 0).toDouble(),
            destinationLat: (data['destinationLat'] ?? 0).toDouble(),
            destinationLng: (data['destinationLng'] ?? 0).toDouble(),
            pickupAddress: data['pickupAddress'] ?? 'Unknown pickup location',
            destinationAddress: data['destinationAddress'] ?? 'Unknown destination',
            fare: (data['rideFare'] ?? 0) is int ? data['rideFare'] : (data['rideFare'] ?? 0).toInt(),
            distanceKm: (data['rideDistance'] ?? 0).toDouble(),
            status: data['status'] ?? 'isLooking',
            captainId: data['confirmedDriverId'], // Your field name
            captainStatus: null, // Not in your current structure
            timestamp: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
            pickupLocation: GeoPoint(
              (data['pickupLat'] ?? 0).toDouble(),
              (data['pickupLng'] ?? 0).toDouble(),
            ),
            additionalData: {
              'acceptedDrivers': data['acceptedDrivers'] ?? [],
              'confirmedDriverId': data['confirmedDriverId'],
              'rideDistance': data['rideDistance'],
              'rideFare': data['rideFare'],
              'originalData': data,
            },
          );

          // Skip if this request already has a confirmed driver
          if (data['confirmedDriverId'] != null && data['confirmedDriverId'].toString().isNotEmpty) {
            print('Skipping request ${request.id} - already confirmed to driver ${data['confirmedDriverId']}');
            continue;
          }

          // Skip if this is the current driver's own request (if they were a passenger)
          final currentUser = _auth.currentUser;
          if (currentUser != null && request.passengerId == currentUser.uid) {
            print('Skipping request ${request.id} - this is the current driver\'s own request');
            continue;
          }

          // Check if current driver already accepted this request
          final acceptedDrivers = data['acceptedDrivers'] as List<dynamic>? ?? [];
          if (currentUser != null && acceptedDrivers.contains(currentUser.uid)) {
            print('Current driver already accepted request ${request.id}');
            // Still include it but mark it differently
            request.additionalData!['alreadyAcceptedByMe'] = true;
          }

          allRequests.add(request);
          print('Added request ${request.id} from ${request.passengerName} - ${request.fare} PKR');

        } catch (e) {
          print('Error processing request ${doc.id}: $e');
          continue;
        }
      }

      print('Found ${allRequests.length} available requests after filtering');

      if (allRequests.isEmpty) {
        print('No available passenger requests after filtering');
        return [];
      }

      // Filter requests by distance from driver location
      List<PassengerRequest> nearbyRequests = [];

      for (var request in allRequests) {
        double distance = _calculateDistance(
            driverLocation.latitude,
            driverLocation.longitude,
            request.pickupLat,
            request.pickupLng
        );

        if (distance <= radiusKm) {
          // Add calculated distance to the request
          request = request.copyWith(
              additionalData: {
                'calculatedDistanceKm': distance,
                'distanceFromDriver': distance,
                'estimatedPickupTime': (distance * 3).round(), // Rough estimate: 3 minutes per km
                'lastChecked': DateTime.now().toIso8601String(),
                ...request.additionalData ?? {}
              }
          );

          nearbyRequests.add(request);
          print('Added nearby request ${request.id} from ${request.passengerName} - ${distance.toStringAsFixed(2)}km away');
        } else {
          print('Request ${request.id} too far: ${distance.toStringAsFixed(2)}km (limit: ${radiusKm}km)');
        }
      }

      // Sort by distance (closest first)
      nearbyRequests.sort((a, b) {
        double distanceA = a.additionalData?['calculatedDistanceKm'] ?? double.infinity;
        double distanceB = b.additionalData?['calculatedDistanceKm'] ?? double.infinity;
        return distanceA.compareTo(distanceB);
      });

      print('Returning ${nearbyRequests.length} nearby passenger requests');

      // Log the first few requests for debugging
      for (int i = 0; i < min(nearbyRequests.length, 3); i++) {
        final req = nearbyRequests[i];
        final distance = req.additionalData?['calculatedDistanceKm'] ?? 0.0;
        print('Request ${i + 1}: ${req.passengerName} - ${distance.toStringAsFixed(2)}km - ${req.fare} PKR');
      }

      return nearbyRequests;

    } catch (e) {
      print("Error fetching passenger requests: $e");
      return [];
    }
  }

  // Accept a passenger request - add driver to acceptedDrivers array
  Future<bool> acceptRequest(String requestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('Error: No current user found');
        return false;
      }

      print('Attempting to accept request $requestId by driver ${currentUser.uid}');

      // First, check if the request is still available
      final requestDoc = await _firestore.collection('PassengerRequests').doc(requestId).get();

      if (!requestDoc.exists) {
        print('Error: Request $requestId does not exist');
        return false;
      }

      final requestData = requestDoc.data() as Map<String, dynamic>;

      // Check if request is still looking
      if (requestData['status'] != 'isLooking') {
        print('Error: Request $requestId is no longer looking (status: ${requestData['status']})');
        return false;
      }

      // Check if already confirmed to another driver
      if (requestData['confirmedDriverId'] != null && requestData['confirmedDriverId'].toString().isNotEmpty) {
        print('Error: Request $requestId is already confirmed to driver ${requestData['confirmedDriverId']}');
        return false;
      }

      // Check if current driver already accepted
      final acceptedDrivers = List<String>.from(requestData['acceptedDrivers'] ?? []);
      if (acceptedDrivers.contains(currentUser.uid)) {
        print('Driver ${currentUser.uid} already accepted request $requestId');
        return true; // Consider this a success since they already accepted
      }

      // Use a transaction to ensure atomicity
      await _firestore.runTransaction((transaction) async {
        // Re-read the document in the transaction
        final freshRequestDoc = await transaction.get(_firestore.collection('PassengerRequests').doc(requestId));

        if (!freshRequestDoc.exists) {
          throw Exception('Request no longer exists');
        }

        final freshData = freshRequestDoc.data() as Map<String, dynamic>;

        if (freshData['status'] != 'isLooking' ||
            (freshData['confirmedDriverId'] != null && freshData['confirmedDriverId'].toString().isNotEmpty)) {
          throw Exception('Request no longer available');
        }

        // Add current driver to acceptedDrivers array
        final currentAcceptedDrivers = List<String>.from(freshData['acceptedDrivers'] ?? []);
        if (!currentAcceptedDrivers.contains(currentUser.uid)) {
          currentAcceptedDrivers.add(currentUser.uid);
        }

        // Update the request - add driver to accepted list but don't confirm yet
        transaction.update(_firestore.collection('PassengerRequests').doc(requestId), {
          'acceptedDrivers': currentAcceptedDrivers,
          'lastUpdated': FieldValue.serverTimestamp(),
          'currentTimestamp': _currentTimestamp,
          'currentUserLogin': _currentUserLogin,
        });

        // Update driver's active ride in their profile
        transaction.update(_firestore.collection('Taxis').doc(currentUser.uid), {
          'activeRideId': requestId,
          'rideState': 'waitingForConfirmation',
          'isAvailable': false, // Only set isAvailable to false, NOT status
          'lastUpdated': FieldValue.serverTimestamp(),
          'currentTimestamp': _currentTimestamp,
          'currentUserLogin': _currentUserLogin,
        });
      });

      print('Successfully accepted request $requestId - added to acceptedDrivers list');
      return true;

    } catch (e) {
      print("Error accepting request: $e");
      return false;
    }
  }

  // Confirm driver selection (this would be called when passenger selects a driver)
  Future<bool> confirmDriver(String requestId, String driverId) async {
    try {
      print('Confirming driver $driverId for request $requestId');

      await _firestore.runTransaction((transaction) async {
        final requestDoc = await transaction.get(_firestore.collection('PassengerRequests').doc(requestId));

        if (!requestDoc.exists) {
          throw Exception('Request not found');
        }

        final requestData = requestDoc.data() as Map<String, dynamic>;
        final acceptedDrivers = List<String>.from(requestData['acceptedDrivers'] ?? []);

        if (!acceptedDrivers.contains(driverId)) {
          throw Exception('Driver not in accepted list');
        }

        // Update request with confirmed driver
        transaction.update(_firestore.collection('PassengerRequests').doc(requestId), {
          'confirmedDriverId': driverId,
          'status': 'confirmed',
          'confirmedAt': FieldValue.serverTimestamp(),
          'currentTimestamp': _currentTimestamp,
          'currentUserLogin': _currentUserLogin,
        });

        // Update confirmed driver - ONLY updating isAvailable and rideState, NOT status
        transaction.update(_firestore.collection('Taxis').doc(driverId), {
          'rideState': 'enrouteToPickup',
          'isAvailable': false,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Update other drivers who weren't selected - ONLY updating isAvailable and rideState
        for (String otherDriverId in acceptedDrivers) {
          if (otherDriverId != driverId) {
            transaction.update(_firestore.collection('Taxis').doc(otherDriverId), {
              'activeRideId': null,
              'rideState': null,
              'isAvailable': true, // Set back to available
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }
      });

      print('Successfully confirmed driver $driverId for request $requestId');
      return true;

    } catch (e) {
      print('Error confirming driver: $e');
      return false;
    }
  }

  // Update the captain's status for a ride
  Future<bool> updateCaptainStatus(String requestId, String status) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('Error: No current user found');
        return false;
      }

      print('Updating captain status for request $requestId to: $status');

      // Map status to standardized values for rideState
      String rideState;
      String requestStatus = 'confirmed'; // Default to confirmed
      bool isAvailable = false; // Default to unavailable

      switch (status) {
        case 'en_route_to_pickup':
          rideState = 'enrouteToPickup';
          requestStatus = 'confirmed';
          break;
        case 'arrived_at_pickup':
          rideState = 'arrivedAtPickup';
          requestStatus = 'confirmed';
          break;
        case 'en_route_to_destination':
          rideState = 'enrouteToDestination';
          requestStatus = 'inProgress';
          break;
        case 'arrived_at_destination':
          rideState = 'arrivedAtDestination';
          requestStatus = 'inProgress';
          break;
        case 'completed':
          rideState = 'completed';
          requestStatus = 'completed';
          isAvailable = true; // Make available again when completed
          break;
        case 'cancelled':
          rideState = 'cancelled';
          requestStatus = 'cancelled';
          isAvailable = true; // Make available again when cancelled
          break;
        default:
          rideState = status;
      }

      // Use transaction for atomic updates
      await _firestore.runTransaction((transaction) async {
        // Update the request
        transaction.update(_firestore.collection('PassengerRequests').doc(requestId), {
          'captainStatus': status,
          'status': requestStatus,
          'lastUpdated': FieldValue.serverTimestamp(),
          'currentTimestamp': _currentTimestamp,
          'currentUserLogin': _currentUserLogin,
        });

        // Update driver's state - ONLY updating rideState and isAvailable, NOT status
        Map<String, dynamic> driverUpdate = {
          'rideState': rideState,
          'isAvailable': isAvailable,
          'lastUpdated': FieldValue.serverTimestamp(),
          'currentTimestamp': _currentTimestamp,
          'currentUserLogin': _currentUserLogin,
        };

        // If ride is completed or cancelled, clear active ride
        if (status == 'completed' || status == 'cancelled') {
          driverUpdate['activeRideId'] = null;
        }

        transaction.update(_firestore.collection('Taxis').doc(currentUser.uid), driverUpdate);
      });

      // If ride is completed, update driver stats
      if (status == 'completed') {
        await _updateDriverStats(requestId);
      }

      print('Successfully updated captain status to: $status');
      return true;

    } catch (e) {
      print("Error updating captain status: $e");
      return false;
    }
  }

  // Update driver statistics after completing a ride
  Future<void> _updateDriverStats(String requestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // Get the completed request details
      final requestDoc = await _firestore.collection('PassengerRequests').doc(requestId).get();
      if (!requestDoc.exists) return;

      final requestData = requestDoc.data() as Map<String, dynamic>;
      final int fare = (requestData['rideFare'] ?? 0) is int ? requestData['rideFare'] : (requestData['rideFare'] ?? 0).toInt();
      final String passengerId = requestData['passengerId'] ?? '';

      print('Updating driver stats: +1 ride, +$fare PKR earnings');

      // Update driver stats - DON'T touch status field
      await _firestore.collection('Taxis').doc(currentUser.uid).update({
        'totalRides': FieldValue.increment(1),
        'earnings': FieldValue.increment(fare),
        'lastRideCompleted': FieldValue.serverTimestamp(),
        'currentTimestamp': _currentTimestamp,
        'currentUserLogin': _currentUserLogin,
      });

      // Update passenger's ride history if this is a real passenger
      if (passengerId.isNotEmpty) {
        try {
          await _firestore.collection('Users').doc(passengerId).update({
            'lastRideTimestamp': FieldValue.serverTimestamp(),
            'rideCount': FieldValue.increment(1),
            'lastRideWithDriver': currentUser.uid,
            'currentTimestamp': _currentTimestamp,
          });
          print('Updated passenger $passengerId ride history');
        } catch (e) {
          print('Error updating passenger data: $e');
          // Continue despite passenger update error
        }
      }

    } catch (e) {
      print('Error updating driver stats: $e');
    }
  }

  // Get captain's active ride if any
  Future<PassengerRequest?> getActiveRide() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;

      print('Getting active ride for driver ${currentUser.uid}');

      // Get driver's active ride ID
      final driverDoc = await _firestore.collection('Taxis').doc(currentUser.uid).get();
      if (!driverDoc.exists) {
        print('Driver document not found');
        return null;
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final String? activeRideId = driverData['activeRideId'] as String?;

      if (activeRideId == null || activeRideId.isEmpty) {
        print('No active ride found for driver');
        return null;
      }

      print('Found active ride ID: $activeRideId');

      // Fetch the active ride
      final rideDoc = await _firestore.collection('PassengerRequests').doc(activeRideId).get();
      if (!rideDoc.exists) {
        print('Active ride document not found, clearing from driver profile');
        // Clear the invalid active ride ID
        await _firestore.collection('Taxis').doc(currentUser.uid).update({
          'activeRideId': null,
          'rideState': null,
          'isAvailable': true,  // Make available again
        });
        return null;
      }

      final data = rideDoc.data() as Map<String, dynamic>;

      // Create PassengerRequest from your data structure
      final request = PassengerRequest(
        id: rideDoc.id,
        passengerId: data['passengerId'] ?? '',
        passengerName: data['passengerName'] ?? 'Unknown Passenger',
        passengerImage: data['passengerImage'] ?? 'https://randomuser.me/api/portraits/women/44.jpg',
        passengerRating: 4.5,
        pickupLat: (data['pickupLat'] ?? 0).toDouble(),
        pickupLng: (data['pickupLng'] ?? 0).toDouble(),
        destinationLat: (data['destinationLat'] ?? 0).toDouble(),
        destinationLng: (data['destinationLng'] ?? 0).toDouble(),
        pickupAddress: data['pickupAddress'] ?? 'Unknown pickup location',
        destinationAddress: data['destinationAddress'] ?? 'Unknown destination',
        fare: (data['rideFare'] ?? 0) is int ? data['rideFare'] : (data['rideFare'] ?? 0).toInt(),
        distanceKm: (data['rideDistance'] ?? 0).toDouble(),
        status: data['status'] ?? 'isLooking',
        captainId: data['confirmedDriverId'],
        captainStatus: data['captainStatus'],
        timestamp: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
        pickupLocation: GeoPoint(
          (data['pickupLat'] ?? 0).toDouble(),
          (data['pickupLng'] ?? 0).toDouble(),
        ),
        additionalData: data,
      );

      print('Retrieved active ride: ${request.id} with passenger ${request.passengerName}');

      return request;

    } catch (e) {
      print("Error getting active ride: $e");
      return null;
    }
  }

  // Calculate distance between two points in km
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a =
        sin(dLat/2) * sin(dLat/2) +
            cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
                sin(dLon/2) * sin(dLon/2);

    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * (pi / 180);
  }
}