import 'package:cloud_firestore/cloud_firestore.dart';

class PassengerRequest {
  final String id;
  final String passengerId;
  final String passengerName;
  final String passengerImage;
  final double passengerRating;
  final double pickupLat;
  final double pickupLng;
  final double destinationLat;
  final double destinationLng;
  final String pickupAddress;
  final String destinationAddress;
  final int fare;
  final double distanceKm;
  final String status; // "pending", "accepted", "completed", "cancelled"
  final String? captainId;
  final String? captainStatus; // "en_route_to_pickup", "arrived_at_pickup", "en_route_to_destination", etc.
  final DateTime timestamp;
  final GeoPoint? pickupLocation; // For GeoFirestore queries
  final Map<String, dynamic>? additionalData;

  PassengerRequest({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.passengerImage,
    required this.passengerRating,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.fare,
    required this.distanceKm,
    required this.status,
    required this.timestamp,
    this.captainId,
    this.captainStatus,
    this.pickupLocation,
    this.additionalData,
  });

  factory PassengerRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Extract location data, handling different storage formats
    double pickupLat = 0.0;
    double pickupLng = 0.0;

    if (data['pickupLocation'] is GeoPoint) {
      final geoPoint = data['pickupLocation'] as GeoPoint;
      pickupLat = geoPoint.latitude;
      pickupLng = geoPoint.longitude;
    } else {
      pickupLat = (data['pickupLat'] ?? 0).toDouble();
      pickupLng = (data['pickupLng'] ?? 0).toDouble();
    }

    double destinationLat = (data['destinationLat'] ?? 0).toDouble();
    double destinationLng = (data['destinationLng'] ?? 0).toDouble();

    // Handle timestamp variations
    DateTime timestamp;
    if (data['timestamp'] is Timestamp) {
      timestamp = (data['timestamp'] as Timestamp).toDate();
    } else if (data['createdAt'] is Timestamp) {
      timestamp = (data['createdAt'] as Timestamp).toDate();
    } else {
      timestamp = DateTime.now();
    }

    return PassengerRequest(
      id: doc.id,
      passengerId: data['passengerId'] ?? '',
      passengerName: data['passengerName'] ?? 'Unknown Passenger',
      passengerImage: data['passengerImage'] ?? 'https://randomuser.me/api/portraits/women/44.jpg',
      passengerRating: (data['passengerRating'] ?? 4.5).toDouble(),
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      pickupAddress: data['pickupAddress'] ?? 'Unknown pickup location',
      destinationAddress: data['destinationAddress'] ?? 'Unknown destination',
      fare: (data['fare'] ?? 0) is int ? data['fare'] : (data['fare'] ?? 0).toInt(),
      distanceKm: (data['distanceKm'] ?? 0).toDouble(),
      status: data['status'] ?? 'pending',
      captainId: data['captainId'],
      captainStatus: data['captainStatus'],
      timestamp: timestamp,
      pickupLocation: data['pickupLocation'] is GeoPoint ? data['pickupLocation'] : null,
      additionalData: data['additionalData'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerImage': passengerImage,
      'passengerRating': passengerRating,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'fare': fare,
      'distanceKm': distanceKm,
      'status': status,
      'captainId': captainId,
      'captainStatus': captainStatus,
      'timestamp': FieldValue.serverTimestamp(),
      'pickupLocation': GeoPoint(pickupLat, pickupLng),
      'additionalData': additionalData,
    };
  }

  // Create a copy with updated fields
  PassengerRequest copyWith({
    String? status,
    String? captainId,
    String? captainStatus,
    Map<String, dynamic>? additionalData,
  }) {
    return PassengerRequest(
      id: this.id,
      passengerId: this.passengerId,
      passengerName: this.passengerName,
      passengerImage: this.passengerImage,
      passengerRating: this.passengerRating,
      pickupLat: this.pickupLat,
      pickupLng: this.pickupLng,
      destinationLat: this.destinationLat,
      destinationLng: this.destinationLng,
      pickupAddress: this.pickupAddress,
      destinationAddress: this.destinationAddress,
      fare: this.fare,
      distanceKm: this.distanceKm,
      status: status ?? this.status,
      captainId: captainId ?? this.captainId,
      captainStatus: captainStatus ?? this.captainStatus,
      timestamp: this.timestamp,
      pickupLocation: this.pickupLocation,
      additionalData: additionalData ?? this.additionalData,
    );
  }
}