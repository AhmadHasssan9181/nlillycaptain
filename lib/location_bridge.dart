import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../controller/map_controller.dart';
import '../controller/ride_controller.dart';

class LocationBridge {
  // Singleton pattern
  static final LocationBridge _instance = LocationBridge._internal();
  factory LocationBridge() => _instance;
  LocationBridge._internal();

  // Controllers that need location updates
  final List<MapController> _mapControllers = [];
  final List<RideController> _rideControllers = [];

  LatLng? _lastLocation;
  final List<LatLng> _locationHistory = [];
  static const int _maxHistorySize = 5;
  DateTime _lastRouteCheck = DateTime.now();

  void updateLocation(LatLng location) {
    // Store the location
    _lastLocation = location;

    // Add to history and manage history size
    _locationHistory.add(location);
    if (_locationHistory.length > _maxHistorySize) {
      _locationHistory.removeAt(0);
    }

    // Check if off route and recalculate if needed
    _checkIfOffRouteAndRecalculate();
    _lastRouteCheck = DateTime.now();

    // Update all controllers
    for (final controller in _mapControllers) {
      controller.updateDriverLocation(location);
    }

    for (final controller in _rideControllers) {
      controller.updateDriverLocation(location);
    }
  }

  void _checkIfOffRouteAndRecalculate() {
    if (_locationHistory.length < 2) return; // Need at least a couple of points

    // Find a map controller with active navigation
    MapController? activeNavigationController;
    for (final controller in _mapControllers) {
      if (controller.isNavigating) {
        activeNavigationController = controller;
        break;
      }
    }

    if (activeNavigationController == null) {
      return;
    }

    // Trigger route check
    activeNavigationController.checkAndRecalculateRouteIfNeeded();
  }

  bool _isLocationOffRoute(LatLng location, List<LatLng> route) {
    if (route.isEmpty) return false;

    // Find closest segment on route
    double minDistance = double.infinity;

    // Loop through route segments
    for (int i = 0; i < route.length - 1; i++) {
      final pointA = route[i];
      final pointB = route[i + 1];

      // Calculate distance to this segment
      final segmentDistance = _distanceToSegment(
          location.latitude, location.longitude,
          pointA.latitude, pointA.longitude,
          pointB.latitude, pointB.longitude
      );

      minDistance = min(minDistance, segmentDistance);
    }

    // 30 meters threshold
    return minDistance > 0.03; // 30 meters in km
  }

  double _distanceToSegment(
      double x, double y,
      double x1, double y1,
      double x2, double y2) {

    final A = x - x1;
    final B = y - y1;
    final C = x2 - x1;
    final D = y2 - y1;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;

    // Find projection ratio
    double param = dot / lenSq;

    double xx, yy;

    // Find nearest point
    if (param < 0) {
      xx = x1;
      yy = y1;
    }
    else if (param > 1) {
      xx = x2;
      yy = y2;
    }
    else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    // Calculate distance
    return _calculateDistance(x, y, xx, yy);
  }

  // Register controllers
  void registerMapController(MapController controller) {
    if (!_mapControllers.contains(controller)) {
      _mapControllers.add(controller);

      // Immediately update with last known location if available
      if (_lastLocation != null) {
        controller.updateDriverLocation(_lastLocation!);
      }
    }
  }

  void registerRideController(RideController controller) {
    if (!_rideControllers.contains(controller)) {
      _rideControllers.add(controller);

      // Immediately update with last known location if available
      if (_lastLocation != null) {
        controller.updateDriverLocation(_lastLocation!);
      }
    }
  }

  void recalculateActiveRoutes() {
    if (_lastLocation == null) return;

    for (final controller in _mapControllers) {
      if (controller.isNavigating) {
        controller.recalculateRouteFromActualPosition();
      }
    }
  }

  // Clean up
  void unregisterMapController(MapController controller) {
    _mapControllers.remove(controller);
  }

  void unregisterRideController(RideController controller) {
    _rideControllers.remove(controller);
  }

  void dispose() {
    _mapControllers.clear();
    _rideControllers.clear();
    _lastLocation = null;
  }

  // Distance calculation helper
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat/2) * sin(dLat/2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon/2) * sin(dLon/2);
    final c = 2 * atan2(sqrt(a), sqrt(1-a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * (pi / 180);
  }
}