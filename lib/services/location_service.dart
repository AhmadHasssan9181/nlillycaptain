import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../controller/map_controller.dart';
import '../location_bridge.dart';
import '../location_manager.dart';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Properties
  LocationManager? _locationManager;

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

  // Last known position
  Position? _lastKnownPosition;
  final Random _random = Random();

  // Callbacks
  Function(LatLng)? onLocationChanged;

  // Current state
  bool _isInRide = false;
  bool _isTracking = false;
  bool _forceUpdates = true; // Force updates even without movement

  // Map controllers
  MaplibreMapController? _mapController;
  MapController? _appMapController;

  // Getters
  bool get isTracking => _isTracking;

  // Set the MapController from our app architecture
  void setMapController(MapController controller) {
    _appMapController = controller;
  }

  // Set the MapLibre controller
  void setMapLibreController(MaplibreMapController controller) {
    _mapController = controller;
  }

  void setLocationManager(LocationManager manager) {
    _locationManager = manager;

    // Register existing map controller if available
    if (_appMapController != null) {
      _locationManager!.registerMapController(_appMapController!);
    }
  }

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
      return false;
    }

    // Check Android permissions specifically
    if (Platform.isAndroid) {
      // Check if we have the required permissions for foreground service
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        // Request notification permission for foreground service
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          return false;
        }
      }
    }

    // Check for location permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
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
      return null;
    }
  }

  // Start tracking location
  Future<bool> startTracking() async {
    if (_isTracking) return true;

    final hasPermission = await requestPermissions();
    if (!hasPermission) return false;

    // Get initial position
    final initialPosition = await getCurrentLocation();
    if (initialPosition != null) {
      if (onLocationChanged != null) {
        onLocationChanged!(initialPosition);
      }

      // Use LocationBridge to distribute updates
      LocationBridge().updateLocation(initialPosition);

      _updateFirestoreDirectly(initialPosition);
    }

    try {
      // Use locationSettings appropriate for the platform
      LocationSettings locationSettings;

      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _distanceFilter,
          intervalDuration: Duration(milliseconds: _isInRide ? _rideInterval : _normalInterval),
          // Set foreground notification details - required for Android
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Lily Captain is using your location",
            notificationTitle: "Location Access",
            enableWakeLock: true,
            notificationChannelName: "Location tracking",
            notificationIcon: AndroidResource(name: 'ic_notification'),
          ),
        );
      } else if (Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _distanceFilter,
          pauseLocationUpdatesAutomatically: false,
          activityType: ActivityType.automotiveNavigation,
          allowBackgroundLocationUpdates: true,
        );
      } else {
        locationSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _distanceFilter,
        );
      }

      // Start listening to position updates with proper error handling
      _positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: locationSettings
      ).listen(
            (Position position) {
          // Process position updates
          _lastKnownPosition = position;
          final driverLocation = LatLng(position.latitude, position.longitude);

          // Notify listeners
          if (onLocationChanged != null) {
            onLocationChanged!(driverLocation);
          }

          // Use LocationBridge to distribute updates
          LocationBridge().updateLocation(driverLocation);

          // Update Firestore
          _updateFirestoreDirectly(driverLocation);
        },
        onError: (error) {
          print("Location stream error: $error");

          // Attempt to restart tracking after a delay if we encounter an error
          if (_isTracking) {
            Future.delayed(Duration(seconds: 5), () {
              if (_isTracking) {
                stopTracking();
                startTracking();
              }
            });
          }
        },
      );

      // Set up forced update timer if enabled
      if (_forceUpdates) {
        _setupForcedUpdateTimer();
      }

      _isTracking = true;
      return true;
    } catch (e) {
      print("Error starting location tracking: $e");
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

        // Notify listeners of jittered location
        if (onLocationChanged != null) {
          onLocationChanged!(jitteredLocation);
        }

        // Use LocationBridge to distribute updates
        LocationBridge().updateLocation(jitteredLocation);

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
        });
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  // Stop tracking location
  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    _forcedUpdateTimer?.cancel();
    _forcedUpdateTimer = null;

    _isTracking = false;
  }

  // Cleanup resources
  void dispose() {
    stopTracking();
    _appMapController = null;
    _mapController = null;
  }
}