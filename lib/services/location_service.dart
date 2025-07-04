import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Stream subscription for position updates
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _forcedUpdateTimer;

  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Location settings
  int _normalInterval = 5000;   // 5 seconds when not on ride
  int _rideInterval = 2000;     // 2 seconds during active rides
  int _distanceFilter = 0;      // 0 meters - update regardless of movement

  // Last known position and random jitter for forced updates
  Position? _lastKnownPosition;
  Random _random = Random();

  // Callbacks
  Function(LatLng)? onLocationChanged;

  // Current state
  bool _isInRide = false;
  bool _isTracking = false;
  bool _forceUpdates = true; // Force updates even without movement

  // Getters
  bool get isTracking => _isTracking;

  // Set whether to force updates even without movement
  void setForceUpdates(bool force) {
    _forceUpdates = force;
    if (_isTracking) {
      stopTracking();
      startTracking();
    }
  }

  // Configure update intervals
  void configure({
    int? normalIntervalMs,
    int? rideIntervalMs,
    int? distanceFilterMeters,
    bool? forceUpdates,
  }) {
    if (normalIntervalMs != null) _normalInterval = normalIntervalMs;
    if (rideIntervalMs != null) _rideInterval = rideIntervalMs;
    if (distanceFilterMeters != null) _distanceFilter = distanceFilterMeters;
    if (forceUpdates != null) _forceUpdates = forceUpdates;

    // If already tracking, restart with new settings
    if (_isTracking) {
      stopTracking();
      startTracking();
    }
  }

  // Set ride mode to change update frequency
  void setRideMode(bool isInRide) {
    if (_isInRide == isInRide) return;

    _isInRide = isInRide;
    print('Location service: Setting ride mode to ${isInRide ? "ACTIVE RIDE" : "NORMAL"}');

    // Restart tracking with new interval if already tracking
    if (_isTracking) {
      stopTracking();
      startTracking();
    }
  }

  // Request location permissions
  Future<bool> requestPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  // Get current location once
  Future<LatLng?> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      );
      _lastKnownPosition = position;
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  // Start tracking location continuously
  Future<bool> startTracking() async {
    if (_isTracking) return true;

    final hasPermission = await requestPermissions();
    if (!hasPermission) return false;

    // Get initial position
    final initialPosition = await getCurrentLocation();
    if (initialPosition != null) {
      onLocationChanged?.call(initialPosition);
      _updateFirestoreDirectly(initialPosition);
    }

    try {
      print('Starting location tracking with ${_isInRide ? "ride" : "normal"} mode');

      // For geolocator 14.0.0, use the correct parameters
      final LocationSettings locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilter, // Set to 0 to get all updates
        intervalDuration: Duration(milliseconds: _isInRide ? _rideInterval : _normalInterval),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Lily Captain is tracking your location",
          notificationTitle: "Location Tracking Active",
          enableWakeLock: true,
        ),
      );

      // Start listening to position updates
      _positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: locationSettings
      ).listen((Position position) {
        _lastKnownPosition = position;
        final driverLocation = LatLng(position.latitude, position.longitude);

        print('LOCATION UPDATE: ${position.latitude}, ${position.longitude}');

        // Notify listeners
        onLocationChanged?.call(driverLocation);

        // Also update Firestore directly to ensure it happens
        _updateFirestoreDirectly(driverLocation);
      });

      // Set up forced update timer if enabled
      if (_forceUpdates) {
        _setupForcedUpdateTimer();
      }

      _isTracking = true;
      print('Location tracking started in ${_isInRide ? "RIDE" : "NORMAL"} mode');
      return true;
    } catch (e) {
      print('Error starting location tracking: $e');
      return false;
    }
  }

  // Set up timer to force location updates even without movement
  void _setupForcedUpdateTimer() {
    _forcedUpdateTimer?.cancel();

    final updateInterval = _isInRide ? _rideInterval : _normalInterval;

    _forcedUpdateTimer = Timer.periodic(Duration(milliseconds: updateInterval * 2), (_) {
      if (_lastKnownPosition != null) {
        // Add tiny random variation to ensure updates are registered
        final jitteredLocation = LatLng(
            _lastKnownPosition!.latitude + (_random.nextDouble() - 0.5) * 0.00001,
            _lastKnownPosition!.longitude + (_random.nextDouble() - 0.5) * 0.00001
        );

        print('FORCED LOCATION UPDATE: ${jitteredLocation.latitude}, ${jitteredLocation.longitude}');

        // Notify listeners of jittered location
        onLocationChanged?.call(jitteredLocation);

        // Update Firestore directly
        _updateFirestoreDirectly(jitteredLocation);
      }
    });
  }

  // Update Firestore directly with location
  Future<void> _updateFirestoreDirectly(LatLng location) async {
    try {
      final currentUser = _auth.currentUser;

      if (currentUser != null) {
        await _firestore.collection('Taxis').doc(currentUser.uid).update({
          'lat': location.latitude,
          'lng': location.longitude,
          'location': GeoPoint(location.latitude, location.longitude),
          'lastLocationUpdate': FieldValue.serverTimestamp(),
          'forceUpdatedAt': DateTime.now().toIso8601String(), // Add this to track forced updates
        });
        print('Firebase location updated directly: ${location.latitude}, ${location.longitude}');
      }
    } catch (e) {
      print('Error updating Firestore directly: $e');
    }
  }

  // Stop tracking location
  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    _forcedUpdateTimer?.cancel();
    _forcedUpdateTimer = null;

    _isTracking = false;
    print('Location tracking stopped');
  }

  // Cleanup resources
  void dispose() {
    stopTracking();
  }
}