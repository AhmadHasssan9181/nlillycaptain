import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../location_bridge.dart';
import '../passenger_model.dart';
import '../passenger_service.dart';
import '../screens/chat_screen.dart';
import '../services/chat_service.dart';

// Ride states enum
enum RideState {
  searching,             // Looking for requests
  waitingForConfirmation, // Waiting for passenger confirmation after accepting
  enrouteToPickup,       // Driving to pickup location
  arrivedAtPickup,       // Arrived at pickup, waiting for passenger
  enrouteToDestination,  // Passenger picked up, driving to destination
  arrivedAtDestination,  // Arrived at destination
}

class RideController extends ChangeNotifier {
  // Services
  final PassengerService _passengerService = PassengerService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Driver info
  String driverName = "Driver";
  String driverImage = "https://randomuser.me/api/portraits/men/32.jpg";
  bool isOnline = false;
  LatLng? driverLocation;
  LatLng? _previousDriverLocation;
  double totalEarningsToday = 0.0;
  int ridesCompleted = 0;
  double rating = 4.5;
  String rank = "New";

  // Ride state
  bool isLoading = false;
  bool isLoadingRequests = false;
  RideState rideState = RideState.searching;
  List<PassengerRequest> nearbyRequests = [];
  bool showRequestsList = false;
  PassengerRequest? currentRide;

  // Arrival detection
  double arrivalRadius = 50.0; // meters - radius to consider "arrived"
  bool canArrive = false; // whether arrive button should be enabled
  Timer? _arrivalCheckTimer;

  // Ride subscriptions
  StreamSubscription<DocumentSnapshot>? _rideSubscription;
  StreamSubscription<DocumentSnapshot>? _requestListener;

  // Callbacks
  Function(String)? onShowSnackBar;
  Function(LatLng)? onShowRoute;
  Function()? onClearRoute;
  Function()? onClearMarkers;
  Function(String)? onClearPickupMarker; // Clears specific marker by ID

  // Add getter for previousDriverLocation
  LatLng? get previousDriverLocation => _previousDriverLocation;

  // Computed property
  bool get isInRide =>
      currentRide != null &&
          rideState != RideState.searching &&
          rideState != RideState.arrivedAtDestination;

  // Initialize controller with data
  void initialize() async {
    await _loadDriverProfile();
    await _checkActiveRide();

    if (currentRide != null) {
      _setupRideListener();
    }

    _startArrivalCheckTimer();
    notifyListeners();
  }

  // Updated - Fixed implementation for updateDriverLocation
  void updateDriverLocation(LatLng location) {
    // Skip invalid locations
    if (location.latitude == 0 && location.longitude == 0) {
      print("Ignoring invalid location (0,0)");
      return;
    }

    // Store previous location before updating
    _previousDriverLocation = driverLocation;
    driverLocation = location;

    // Update in Firestore if online
    if (isOnline) {
      _updateDriverLocationInFirestore(location);
    }

    // Check arrival status if in a ride
    if (isInRide) {
      _checkArrival();
    }

    notifyListeners();
  }

  // Updated - Fixed implementation for markAsArrived
  void markAsArrived() {
    if (currentRide == null) return;

    try {
      // Handle different ride states
      if (rideState == RideState.enrouteToPickup) {
        // Mark as arrived at pickup
        arrivedAtPickup();
      }
      else if (rideState == RideState.enrouteToDestination) {
        // Mark as arrived at destination
        arrivedAtDestination();
      }
      else if (rideState == RideState.arrivedAtDestination) {
        // Complete the ride if we're already at destination
        completeRide();
      }
    } catch (e) {
      print('Error marking ride as arrived: $e');
      onShowSnackBar?.call('Error updating arrival status');
    }
  }

  // Load driver profile data from Firestore
  Future<void> _loadDriverProfile() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('No authenticated user found');
        return;
      }

      driverName = currentUser.displayName ?? "Driver";
      driverImage = currentUser.photoURL ?? "https://randomuser.me/api/portraits/men/32.jpg";

      final driverDoc = await _firestore.collection('Taxis').doc(currentUser.uid).get();
      if (!driverDoc.exists) {
        print('No driver profile found in database');
        return;
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;

      driverName = driverData['name'] ?? driverData['driverName'] ?? driverName;
      driverImage = driverData['profileImage'] ?? driverData['driverImage'] ?? driverImage;
      isOnline = driverData['isOnline'] ?? false;
      totalEarningsToday = _extractDouble(driverData['todayEarnings'] ?? driverData['earnings']) ?? 0.0;
      rating = _extractDouble(driverData['rating']) ?? 4.5;
      rank = driverData['rank'] ?? "New";
      ridesCompleted = _extractInt(driverData['totalRides']) ?? 0;

      final settings = driverData['settings'] as Map<String, dynamic>?;
      if (settings != null && settings.containsKey('arrivalRadius')) {
        arrivalRadius = _extractDouble(settings['arrivalRadius']) ?? 50.0;
      }

      notifyListeners();
    } catch (e) {
      print('Error loading driver profile: $e');
    }
  }

  // Helper methods to extract double and int values safely
  double? _extractDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _extractInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  // Helper to update driver's isAvailable status in Firestore
  Future<void> _updateDriverAvailabilityInFirestore(bool available) async {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      try {
        await _firestore.collection('Taxis').doc(currentUser.uid).update({
          'isAvailable': available,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error updating driver Firestore isAvailable: $e');
      }
    }
  }

  void _handleRideCompletion() {
    if (currentRide != null) {
      totalEarningsToday += currentRide!.fare;
      ridesCompleted++;
    }

    rideState = RideState.searching;
    currentRide = null;
    canArrive = false;

    // Cancel any active listeners
    _rideSubscription?.cancel();
    _requestListener?.cancel();

    onClearRoute?.call();
    onShowSnackBar?.call('Ride completed successfully!');

    // If driver is still set to 'online', make them available again
    if (isOnline) {
      _updateDriverAvailabilityInFirestore(true);
    }
    _loadDriverProfile(); // To refresh stats like earnings, ridesCompleted
    notifyListeners();
  }

  void _handleRideCancellation() {
    rideState = RideState.searching;
    currentRide = null;
    canArrive = false;

    // Cancel any active listeners
    _rideSubscription?.cancel();
    _requestListener?.cancel();

    onClearRoute?.call();
    onShowSnackBar?.call('Ride was cancelled');

    // If driver is still set to 'online', make them available again
    if (isOnline) {
      _updateDriverAvailabilityInFirestore(true);
    }
    notifyListeners();
  }

  // Set up a listener for a specific request to detect confirmation
  void _setupRequestListener(String requestId) {
    print('Setting up request confirmation listener for $requestId');

    // Cancel any existing request listener to prevent duplicates
    _requestListener?.cancel();

    _requestListener = _firestore
        .collection('PassengerRequests')
        .doc(requestId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        print('Request document no longer exists');
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'] as String?;
      final confirmedDriverId = data['confirmedDriverId'] as String?;

      // Check if this driver is confirmed and status changed to "accepted"
      if ((status == 'accepted' || status == 'confirmed') &&
          confirmedDriverId == _auth.currentUser?.uid) {
        print('✅ Passenger confirmed this driver! Starting ride...');

        // Instead of creating a new PassengerRequest object directly,
        // update the existing currentRide object
        if (currentRide != null) {
          currentRide = currentRide!.copyWith(
              status: status,
              captainId: confirmedDriverId
          );

          // Send welcome message when the passenger confirms
          _sendWelcomeMessage();

          // Mark as en route to pickup
          _passengerService.updateCaptainStatus(requestId, 'en_route_to_pickup')
              .then((_) {
            // Start full ride mode with active listeners
            _setupRideListener();

            // Update ride state to enrouteToPickup
            rideState = RideState.enrouteToPickup;

            // Show route to pickup location
            if (onShowRoute != null && driverLocation != null) {
              onShowRoute!(LatLng(currentRide!.pickupLat, currentRide!.pickupLng));
              print('Showing route to pickup location');
            }

            // Notify UI of the state change
            notifyListeners();
          });
        }
      }
      // Handle cancellation
      else if (status == 'cancelled') {
        print('❌ Request was cancelled');
        _handleRideCancellation();
      }
    }, onError: (e) {
      print('Error in request listener: $e');
    });
  }

  // Send welcome message to passenger
  Future<void> _sendWelcomeMessage() async {
    if (currentRide == null) return;

    try {
      print('Sending welcome message for ride: ${currentRide!.id}');

      // Create an instance of ChatService
      final ChatService _chatService = ChatService();

      // Send welcome message
      await _chatService.sendMessage(
          currentRide!.id,
          "Hello! I'm ${driverName}, your driver for today. I'm on my way to pick you up! 🚗"
      );

      print('Welcome message sent successfully');
    } catch (e) {
      print('Error sending welcome message: $e');
    }
  }

  // Check for active ride
  Future<void> _checkActiveRide() async {
    try {
      print('Getting active ride for driver ${_auth.currentUser?.uid}');

      // First check if the driver has activeRideId set in their Taxis document
      final driverDoc = await _firestore.collection('Taxis').doc(_auth.currentUser?.uid).get();

      if (!driverDoc.exists) {
        print('Driver document not found');
        return;
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final String? activeRideId = driverData['activeRideId'] as String?;
      final String? driverRideState = driverData['rideState'] as String?;

      // No active ride - nothing to do
      if (activeRideId == null) {
        print('No active ride found in driver document');
        rideState = RideState.searching;
        currentRide = null;
        notifyListeners();
        return;
      }

      // Get the ride document
      final rideDoc = await _firestore.collection('PassengerRequests').doc(activeRideId).get();

      // Ride document doesn't exist - clean up driver state
      if (!rideDoc.exists) {
        print('Active ride document not found, cleaning up driver state');
        // Clear the invalid active ride ID
        await _firestore.collection('Taxis').doc(_auth.currentUser?.uid).update({
          'activeRideId': null,
          'rideState': null,
          'isAvailable': true,
        });
        rideState = RideState.searching;
        currentRide = null;
        notifyListeners();
        return;
      }

      final rideData = rideDoc.data() as Map<String, dynamic>;
      final String? rideStatus = rideData['status'] as String?;
      final String? confirmedDriverId = rideData['confirmedDriverId'] as String?;

      // If ride is cancelled or completed, clean up driver state
      if (rideStatus == 'cancelled' || rideStatus == 'completed') {
        print('Ride found with status $rideStatus - cleaning up driver state');
        await _firestore.collection('Taxis').doc(_auth.currentUser?.uid).update({
          'activeRideId': null,
          'rideState': null,
          'isAvailable': isOnline, // Only available if online
        });
        rideState = RideState.searching;
        currentRide = null;
        notifyListeners();
        return;
      }

      // Create the ride object
      currentRide = PassengerRequest.fromFirestore(rideDoc);

      // Handle when driver is waiting for confirmation
      if (driverRideState == 'waitingForConfirmation') {
        print('Driver is waiting for confirmation');

        // This driver isn't confirmed yet
        if (confirmedDriverId == null || confirmedDriverId != _auth.currentUser?.uid) {
          rideState = RideState.waitingForConfirmation;
          // Set up a listener to detect when passenger confirms
          _setupRequestListener(activeRideId);
          notifyListeners();
          return;
        }
        // This driver is confirmed but state hasn't been updated yet
        else if ((rideStatus == 'accepted' || rideStatus == 'confirmed')) {
          print('Confirmed driver found - updating ride state');

          // Check if captain status already set
          final captainStatus = rideData['captainStatus'] as String?;
          if (captainStatus == null) {
            // Update captain status to en route to pickup
            await _passengerService.updateCaptainStatus(activeRideId, 'en_route_to_pickup');
            currentRide = currentRide!.copyWith(captainStatus: 'en_route_to_pickup');
          }

          // Set up ride listener for ongoing ride
          _setupRideListener();

          // Determine initial ride state
          _determineRideState();

          notifyListeners();
          return;
        }
      }

      // Handle rides that are already in progress (normal flow)
      if ((rideStatus == 'accepted' || rideStatus == 'confirmed' || rideStatus == 'inProgress') &&
          confirmedDriverId == _auth.currentUser?.uid) {

        // Set up ride listener for ongoing ride
        _setupRideListener();

        // Determine ride state based on status
        _determineRideState();

        notifyListeners();
        return;
      }

      // If none of the conditions match, just reset to searching
      print('No valid ride state found');
      rideState = RideState.searching;
      notifyListeners();
    } catch (e) {
      print('Error checking active ride: $e');
      // Handle errors gracefully - reset to searching state if there's an error
      rideState = RideState.searching;
      notifyListeners();
    }
  }

  // Determine current ride state
  void _determineRideState() {
    if (currentRide == null) return;

    final rideStatus = currentRide!.status;
    final captainStatus = currentRide!.captainStatus;

    // Handle cancelled status immediately
    if (rideStatus == 'cancelled') {
      _handleRideCancellation();
      return;
    }

    // Handle completed status immediately
    if (rideStatus == 'completed') {
      _handleRideCompletion();
      return;
    }

    // Special handling for accepted/confirmed rides
    if (rideStatus == 'accepted' || rideStatus == 'confirmed') {
      // If captain status is set, use that to determine ride state
      if (captainStatus == 'arrived_at_pickup') {
        rideState = RideState.arrivedAtPickup;
      }
      else if (captainStatus == 'en_route_to_destination') {
        rideState = RideState.enrouteToDestination;

        // Route to destination
        if (onShowRoute != null && driverLocation != null) {
          onShowRoute!(LatLng(currentRide!.destinationLat, currentRide!.destinationLng));
        }
      }
      else if (captainStatus == 'arrived_at_destination') {
        rideState = RideState.arrivedAtDestination;
      }
      // Default for accepted rides with confirmed driver - en route to pickup
      else if (currentRide!.captainId == _auth.currentUser?.uid) {
        rideState = RideState.enrouteToPickup;

        // Route to pickup
        if (onShowRoute != null && driverLocation != null) {
          onShowRoute!(LatLng(currentRide!.pickupLat, currentRide!.pickupLng));
        }
      }
      // Still waiting for confirmation
      else {
        rideState = RideState.waitingForConfirmation;
      }
    }
    // Handle in progress rides
    else if (rideStatus == 'inProgress') {
      rideState = RideState.enrouteToDestination;

      if (onShowRoute != null && driverLocation != null) {
        onShowRoute!(LatLng(currentRide!.destinationLat, currentRide!.destinationLng));
      }
    }
    // Default case
    else {
      rideState = RideState.waitingForConfirmation;
    }
  }

  // Set up listener for ride updates
  void _setupRideListener() {
    // Cancel any existing subscription
    _rideSubscription?.cancel();
    _requestListener?.cancel();  // Cancel request listener when setting up ride listener

    if (currentRide != null) {
      print('Setting up ride listener for ${currentRide!.id}');

      _rideSubscription = _firestore
          .collection('PassengerRequests')
          .doc(currentRide!.id)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) {
          print('Ride document no longer exists');
          _handleRideCancellation();
          return;
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        final captainStatus = data['captainStatus'] as String?;

        // Explicitly check for cancelled status
        if (status == 'cancelled') {
          print('Ride was CANCELLED - resetting driver state');
          _handleRideCancellation();
          return;
        }

        // Update the local ride model
        if (currentRide != null) {
          currentRide = currentRide!.copyWith(
              status: status,
              captainStatus: captainStatus
          );

          // Handle state transitions
          _handleRideStateTransition(status, captainStatus);
        }
      }, onError: (e) {
        print('Error in ride listener: $e');
      });
    }
  }

  // Handle ride state transition
  void _handleRideStateTransition(String? status, String? captainStatus) {
    if (currentRide == null) return;

    RideState oldState = rideState;
    bool stateChanged = false;

    // Reset state for cancelled rides
    if (status == 'cancelled') {
      _handleRideCancellation();
      return;
    }

    // Handle completed rides
    if (status == 'completed') {
      _handleRideCompletion();
      return;
    }

    // Handle confirmed/accepted rides with captain status changes
    if (status == 'confirmed' || status == 'accepted') {
      if (captainStatus == 'en_route_to_pickup' || captainStatus == null) {
        // Driver should go to pickup location
        if (rideState != RideState.enrouteToPickup) {
          rideState = RideState.enrouteToPickup;
          stateChanged = true;

          // Show route to pickup
          if (onShowRoute != null && driverLocation != null) {
            onShowRoute!(LatLng(currentRide!.pickupLat, currentRide!.pickupLng));
            print('En route to PICKUP location');
          }
        }
      }
      else if (captainStatus == 'arrived_at_pickup') {
        // Driver has arrived at pickup
        if (rideState != RideState.arrivedAtPickup) {
          rideState = RideState.arrivedAtPickup;
          stateChanged = true;
          print('Arrived at PICKUP location');
        }
      }
      else if (captainStatus == 'en_route_to_destination') {
        // Driver has picked up passenger and is heading to destination
        if (rideState != RideState.enrouteToDestination) {
          rideState = RideState.enrouteToDestination;
          stateChanged = true;

          // Show route to destination
          if (onShowRoute != null && driverLocation != null) {
            onShowRoute!(LatLng(currentRide!.destinationLat, currentRide!.destinationLng));
            print('En route to DESTINATION');
          }
        }
      }
      else if (captainStatus == 'arrived_at_destination') {
        // Driver has arrived at destination
        if (rideState != RideState.arrivedAtDestination) {
          rideState = RideState.arrivedAtDestination;
          stateChanged = true;
          print('Arrived at DESTINATION');
        }
      }
    }

    // Handle in progress rides
    if (status == 'inProgress') {
      // Always show destination for in-progress rides
      if (rideState != RideState.enrouteToDestination) {
        rideState = RideState.enrouteToDestination;
        stateChanged = true;

        if (onShowRoute != null && driverLocation != null) {
          onShowRoute!(LatLng(currentRide!.destinationLat, currentRide!.destinationLng));
          print('In progress - heading to DESTINATION');
        }
      }
    }

    // Notify UI if state changed
    if (stateChanged) {
      print('Ride state changed: $oldState -> $rideState');
      notifyListeners();
    }
  }

  // Toggle driver online/offline status
  void toggleDriverStatus() async {
    try {
      isLoading = true;
      notifyListeners();

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      isOnline = !isOnline; // Toggle local state first

      Map<String, dynamic> updates = {
        'isOnline': isOnline,
        'lastStatusChange': FieldValue.serverTimestamp(),
      };

      if (isOnline) {
        if (currentRide == null) {
          updates['isAvailable'] = true;
        } else {
          updates['isAvailable'] = false;
        }
      } else {
        updates['isAvailable'] = false;
        rideState = RideState.searching;
        nearbyRequests.clear();
        onClearMarkers?.call();
        onClearRoute?.call();
      }

      await _firestore.collection('Taxis').doc(currentUser.uid).update(updates);

      if (isOnline && currentRide == null) {
        await _checkActiveRide();
      }

      onShowSnackBar?.call(isOnline ? 'You are now online' : 'You are now offline');

    } catch (e) {
      print('Error toggling driver status: $e');
      onShowSnackBar?.call('Error updating status.');
      isOnline = !isOnline;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Start timer to check arrival status
  void _startArrivalCheckTimer() {
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _checkArrival();
    });
  }

  // Check if driver has arrived at destination
  void _checkArrival() {
    if (driverLocation == null || currentRide == null) return;

    LatLng target;

    // Determine target based on ride state
    if (rideState == RideState.enrouteToPickup) {
      target = LatLng(currentRide!.pickupLat, currentRide!.pickupLng);
    } else if (rideState == RideState.enrouteToDestination) {
      target = LatLng(currentRide!.destinationLat, currentRide!.destinationLng);
    } else {
      return;
    }

    // Calculate distance to target
    double distanceKm = _calculateDistance(
      driverLocation!.latitude,
      driverLocation!.longitude,
      target.latitude,
      target.longitude,
    );

    // Convert to meters
    double distanceMeters = distanceKm * 1000;

    // Dynamic arrival radius - larger for destination to make it easier to detect arrival
    double effectiveRadius = arrivalRadius;
    if (rideState == RideState.enrouteToDestination) {
      // Use a larger radius for destination arrival detection
      effectiveRadius = 100.0; // 100 meters for destination
    }

    // Store previous state to detect changes
    bool wasArrival = canArrive;

    // Update arrival status
    canArrive = distanceMeters <= effectiveRadius;

    // If arrival status changed, notify
    if (wasArrival != canArrive) {
      notifyListeners();
    }
  }

  // Calculate distance between two points
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = sin(dLat/2) * sin(dLat/2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon/2) * sin(dLon/2);

    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * (pi / 180);
  }

  // Set driver location
  void setLocation(LatLng location) {
    driverLocation = location;

    // Check arrival status
    _checkArrival();

    // Update in Firestore if online
    if (isOnline) {
      _updateDriverLocationInFirestore(location);
    }

    notifyListeners();
  }

  // Update driver location in Firestore
  Future<void> _updateDriverLocationInFirestore(LatLng location) async {
    try {
      final currentUser = _auth.currentUser;

      if (currentUser != null) {
        await _firestore.collection('Taxis').doc(currentUser.uid).update({
          'lat': location.latitude,
          'lng': location.longitude,
          'location': GeoPoint(location.latitude, location.longitude),
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error updating driver location: $e');
    }
  }

  // Get text based on ride state
  String getRideStateText() {
    switch (rideState) {
      case RideState.searching:
        return 'Available';
      case RideState.waitingForConfirmation:
        return 'Waiting for confirmation';
      case RideState.enrouteToPickup:
        return 'Heading to pickup';
      case RideState.arrivedAtPickup:
        return 'Arrived at pickup';
      case RideState.enrouteToDestination:
        return 'Heading to destination';
      case RideState.arrivedAtDestination:
        return 'Arrived at destination';
    }
  }

  // Fetch nearby passenger requests
  Future<void> fetchNearbyRequests() async {
    if (driverLocation == null) {
      if (onShowSnackBar != null) {
        onShowSnackBar!('Location not available');
      }
      return;
    }

    try {
      isLoadingRequests = true;
      notifyListeners();

      // Use PassengerService to get nearby requests
      nearbyRequests = await _passengerService.getNearbyPassengerRequests(driverLocation!, 10.0);

      if (nearbyRequests.isEmpty) {
        if (onShowSnackBar != null) {
          onShowSnackBar!('No nearby requests found');
        }
      }
    } catch (e) {
      print('Error fetching nearby requests: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error fetching requests: $e');
      }
    } finally {
      isLoadingRequests = false;
      notifyListeners();
    }
  }

  // Show/hide requests list
  void setShowRequestsList(bool show) {
    showRequestsList = show;
    notifyListeners();
  }

  // Accept a passenger request
  Future<void> acceptRequest(PassengerRequest request) async {
    try {
      isLoading = true;
      notifyListeners();

      // Use PassengerService to accept request
      final success = await _passengerService.acceptRequest(request.id);

      if (success) {
        // Set up listener to detect passenger confirmation
        _setupRequestListener(request.id);

        // Update ride state
        rideState = RideState.waitingForConfirmation;
        currentRide = request;
        showRequestsList = false;

        // Clear any existing route first
        onClearRoute?.call();

        // Show route to pickup location
        if (onShowRoute != null) {
          onShowRoute!(LatLng(request.pickupLat, request.pickupLng));
        }

        if (onShowSnackBar != null) {
          onShowSnackBar!('Request accepted. Waiting for passenger confirmation.');
        }
      } else {
        if (onShowSnackBar != null) {
          onShowSnackBar!('Failed to accept request. Try again.');
        }
      }
    } catch (e) {
      print('Error accepting request: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Mark arrived at pickup
  Future<void> arrivedAtPickup() async {
    if (currentRide == null) return;

    try {
      isLoading = true;
      notifyListeners();

      final success = await _passengerService.updateCaptainStatus(
          currentRide!.id,
          'arrived_at_pickup'
      );

      if (success) {
        rideState = RideState.arrivedAtPickup;
        canArrive = false;

        if (onShowSnackBar != null) {
          onShowSnackBar!('Arrival at pickup location confirmed!');
        }
      } else {
        if (onShowSnackBar != null) {
          onShowSnackBar!('Failed to update status. Try again.');
        }
      }
    } catch (e) {
      print('Error updating pickup arrival: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Confirm pickup and start ride
  Future<void> confirmPickup() async {
    if (currentRide == null) return;

    try {
      isLoading = true;
      notifyListeners();

      final success = await _passengerService.updateCaptainStatus(
          currentRide!.id,
          'en_route_to_destination'
      );

      if (success) {
        // Clear pickup marker when passenger is picked up
        if (onClearPickupMarker != null && currentRide != null) {
          onClearPickupMarker!(currentRide!.id);
        }

        rideState = RideState.enrouteToDestination;

        // Show route to destination
        if (onShowRoute != null && driverLocation != null) {
          onShowRoute!(LatLng(currentRide!.destinationLat, currentRide!.destinationLng));
          print('Showing route to destination after pickup');
        }

        if (onShowSnackBar != null) {
          onShowSnackBar!('Passenger picked up! Heading to destination.');
        }
      } else {
        if (onShowSnackBar != null) {
          onShowSnackBar!('Failed to update status. Try again.');
        }
      }
    } catch (e) {
      print('Error confirming pickup: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Mark arrived at destination
  Future<void> arrivedAtDestination() async {
    if (currentRide == null) return;

    try {
      isLoading = true;
      notifyListeners();

      final success = await _passengerService.updateCaptainStatus(
          currentRide!.id,
          'arrived_at_destination'
      );

      if (success) {
        rideState = RideState.arrivedAtDestination;
        canArrive = false;

        if (onShowSnackBar != null) {
          onShowSnackBar!('Arrival at destination confirmed!');
        }
      } else {
        if (onShowSnackBar != null) {
          onShowSnackBar!('Failed to update status. Try again.');
        }
      }
    } catch (e) {
      print('Error updating destination arrival: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Complete ride
  Future<void> completeRide() async {
    if (currentRide == null) return;

    try {
      isLoading = true;
      notifyListeners();

      final success = await _passengerService.updateCaptainStatus(
          currentRide!.id,
          'completed'
      );

      if (success) {
        // Clear any remaining markers
        if (onClearMarkers != null) {
          onClearMarkers!();
        }

        _handleRideCompletion();
      } else {
        if (onShowSnackBar != null) {
          onShowSnackBar!('Failed to complete ride. Try again.');
        }
      }
    } catch (e) {
      print('Error completing ride: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Cancel ride
  Future<void> cancelRide() async {
    if (currentRide == null) return;

    try {
      isLoading = true;
      notifyListeners();

      final success = await _passengerService.updateCaptainStatus(
          currentRide!.id,
          'cancelled'
      );

      if (success) {
        // Clear all markers associated with this ride
        if (onClearMarkers != null) {
          onClearMarkers!();
        }

        _handleRideCancellation();
      } else {
        if (onShowSnackBar != null) {
          onShowSnackBar!('Failed to cancel ride. Try again.');
        }
      }
    } catch (e) {
      print('Error cancelling ride: $e');
      if (onShowSnackBar != null) {
        onShowSnackBar!('Error: $e');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Dispose method
  @override
  void dispose() {
    @override
    void dispose() {
      _arrivalCheckTimer?.cancel();
      _rideSubscription?.cancel();
      _requestListener?.cancel();

      // Unregister from LocationBridge
      LocationBridge().unregisterRideController(this);

      super.dispose();
    }
  }
}