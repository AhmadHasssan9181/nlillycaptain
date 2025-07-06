import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../controller/map_controller.dart';
import '../controller/ride_controller.dart';

// A global provider to ensure controller lifecycle is properly managed
class ControllerProvider extends ChangeNotifier {
  static final ControllerProvider _instance = ControllerProvider._internal();

  ControllerProvider._internal();

  // Controllers
  MapController? _mapController;
  RideController? _rideController;
  bool _isInitialized = false;

  // Getters
  MapController get mapController {
    if (_mapController == null) {
      _mapController = MapController();
    }
    return _mapController!;
  }

  RideController get rideController {
    if (_rideController == null) {
      _rideController = RideController();
    }
    return _rideController!;
  }

  bool get isInitialized => _isInitialized;

  // Factory constructor to return the singleton instance
  factory ControllerProvider() {
    return _instance;
  }

  // Initialize controllers and set up callbacks
  void initialize(Function(String) showSnackBar) {
    if (!_isInitialized) {
      // Set up callbacks
      rideController.onShowSnackBar = showSnackBar;

      rideController.onClearPreview = () {
        if (mapController.mapController != null) {
          mapController.clearDestinationPreview();
        }
      };
      rideController.onShowRoute = (destination) async {
        if (mapController.mapController != null) {
          try {
            final success = await mapController.showRouteToLocation(destination);
            if (!success) {
              showSnackBar('Failed to get route.');
            }
          } catch (e) {
            print('Error showing route: $e');
          }
        } else {
          print("Map controller not ready for routing");
        }
      };

      rideController.onClearRoute = () {
        if (mapController.mapController != null) {
          mapController.clearRoute();
        }
      };

      rideController.onClearMarkers = () {
        if (mapController.mapController != null) {
          mapController.clearPassengerMarkers();
        }
      };

      // Add handler for selective marker removal
      rideController.onClearPickupMarker = (passengerId) {
        if (mapController.mapController != null) {
          mapController.clearPassengerMarkerById(passengerId);
        }
      };

      // Initialize the ride controller
      rideController.initialize();
      _isInitialized = true;
    }
  }

  // Update location in both controllers
  void updateLocation(LatLng location) {
    if (_mapController != null) {
      _mapController!.updateDriverLocation(location);
    }

    if (_rideController != null) {
      _rideController!.setLocation(location);
    }
  }

  // Clean up (call this in app termination, not in widget disposal)
  void cleanupControllers() {
    if (_rideController != null) {
      _rideController!.dispose();
      _rideController = null;
    }

    if (_mapController != null) {
      _mapController!.dispose();
      _mapController = null;
    }

    _isInitialized = false;
  }
}