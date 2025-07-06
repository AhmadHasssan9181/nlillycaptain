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

  // Debugging
  bool _debugMode = false;
  LatLng? _lastLocation;

  // Register controllers
  void registerMapController(MapController controller) {
    if (!_mapControllers.contains(controller)) {
      _mapControllers.add(controller);
      print("📍 LocationBridge: MapController registered");

      // Immediately update with last known location if available
      if (_lastLocation != null) {
        controller.updateDriverLocation(_lastLocation!);
      }
    }
  }

  void registerRideController(RideController controller) {
    if (!_rideControllers.contains(controller)) {
      _rideControllers.add(controller);
      print("📍 LocationBridge: RideController registered");

      // Immediately update with last known location if available
      if (_lastLocation != null) {
        controller.updateDriverLocation(_lastLocation!);
      }
    }
  }

  // Main update method that distributes location to all controllers
  void updateLocation(LatLng location) {
    // Store the location
    _lastLocation = location;

    // Debug output
    if (_debugMode) {
      print("📍 LocationBridge: Broadcasting location (${location.latitude}, ${location.longitude}) to ${_mapControllers.length} MapControllers and ${_rideControllers.length} RideControllers");
    }

    // Update all map controllers
    for (final controller in _mapControllers) {
      controller.updateDriverLocation(location);
    }

    // Update all ride controllers
    for (final controller in _rideControllers) {
      controller.updateDriverLocation(location);
    }
  }

  // Enable/disable debug logging
  void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  // Force recalculation of active routes
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
}