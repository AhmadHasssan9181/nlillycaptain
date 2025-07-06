import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../controller/map_controller.dart';

class LocationManager {
  // Singleton pattern
  static final LocationManager _instance = LocationManager._internal();
  factory LocationManager() => _instance;
  LocationManager._internal();

  // Last verified location
  LatLng? _verifiedLocation;
  DateTime _lastVerifiedUpdate = DateTime.now();

  // Dependent controllers
  final List<MapController> _mapControllers = [];

  // Status
  bool _isInitialized = false;
  StreamController<LatLng> _locationStreamController = StreamController<LatLng>.broadcast();
  Stream<LatLng> get locationStream => _locationStreamController.stream;

  // Register a map controller to receive location updates
  void registerMapController(MapController controller) {
    if (!_mapControllers.contains(controller)) {
      _mapControllers.add(controller);
      print("📱 MapController registered with LocationManager");

      // If we already have a location, update the controller immediately
      if (_verifiedLocation != null) {
        controller.updateDriverLocation(_verifiedLocation!);
      }
    }
  }

  // Initialize the manager
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    print("🚀 LocationManager initialized");
  }


// For LocationManager class
  void handleLocationUpdate(LatLng location) {
    // Store as verified location
    _verifiedLocation = location;
    _lastVerifiedUpdate = DateTime.now();

    // Broadcast to all registered controllers
    for (var controller in _mapControllers) {
      controller.updateDriverLocation(location);

      // Check if controller has an active route and force update

    }

    // Broadcast to stream listeners
    if (!_locationStreamController.isClosed) {
      _locationStreamController.add(location);
    }

    print("Location broadcast to ${_mapControllers.length} controllers: (${location.latitude}, ${location.longitude})");
  }

  // Force a location update to all controllers
  void forceLocationUpdate() {
    if (_verifiedLocation != null) {
      print("🔄 Forcing location update to all controllers");
      for (var controller in _mapControllers) {
        controller.updateDriverLocation(_verifiedLocation!);
      }
    }
  }

  // Get current verified location
  LatLng? getCurrentLocation() {
    return _verifiedLocation;
  }

  // Cleanup
  void dispose() {
    _locationStreamController.close();
    _mapControllers.clear();
    _isInitialized = false;
    print("🗑️ LocationManager disposed");
  }
}

