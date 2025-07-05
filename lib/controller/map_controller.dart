import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../passenger_model.dart';

class MapController {
  // Core controllers
  MaplibreMapController? _mapController;
  NavigationManager? _navigationManager;

  // Location and routing data
  LatLng? _driverLocation;
  LatLng? _currentTarget;
  List<LatLng> _currentRoute = [];
  List<LatLng> _originalRoute = [];

  // Map UI elements
  List<Circle> _circles = [];  // Passenger pickup markers
  Map<String, Circle> _markerMap = {}; // Track markers by ID for selective removal
  List<Line> _lines = [];
  List<Circle> _previewCircles = [];
  List<Line> _previewLines = [];

  // Navigation state
  bool _isNavigating = false;
  int _lastRoutePointIndex = 0;
  Timer? _routeUpdateTimer;
  final double _routeDeviationThreshold = 100.0; // meters

  // Getters
  MaplibreMapController? get mapController => _mapController;
  LatLng? get driverLocation => _driverLocation;
  LatLng? get currentTarget => _currentTarget;
  List<LatLng> get currentRoute => _currentRoute;
  bool get isNavigating => _isNavigating;

  // Initialize the map controller
  void setMapController(MaplibreMapController controller) {
    _mapController = controller;

    // Initialize navigation manager
    _navigationManager = NavigationManager();
    _navigationManager!.initialize(controller);
  }

  // Central location update method that handles all location changes
  void updateDriverLocation(LatLng location) {
    _driverLocation = location;

    // Update navigation manager
    _navigationManager?.setDriverLocation(location);

    // Handle navigation updates if active
    if (_isNavigating && _currentRoute.isNotEmpty) {
      _updateRouteProgress(location);
      _updateCameraForNavigation(location);
    }
    // Fix navigation state if needed
    else if (_currentTarget != null && _currentRoute.isNotEmpty && !_isNavigating) {
      _isNavigating = true;
      _updateRouteProgress(location);
    }
  }

  // Update camera position during navigation
  void _updateCameraForNavigation(LatLng location) {
    if (_mapController == null) return;

    // Get next point and calculate bearing
    LatLng nextPoint = _getNextPointOnRoute(location);
    double bearing = _calculateBearing(location, nextPoint);

    // Move camera with bearing
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 17.0,
          bearing: bearing,
        ),
      ),
    );
  }

  // Move camera to specific location
  void moveCameraToLocation(LatLng location) {
    _mapController?.moveCamera(
      CameraUpdate.newLatLngZoom(location, 15.0),
    );
  }

  // Add passenger markers to the map
  Future<void> addPassengerMarkersToMap(List<PassengerRequest> requests) async {
    clearPassengerMarkers();

    for (var request in requests) {
      try {
        final pickupLocation = LatLng(request.pickupLat, request.pickupLng);

        final circle = await _mapController?.addCircle(
          CircleOptions(
            geometry: pickupLocation,
            circleRadius: 10,
            circleColor: "#FF0000",
            circleOpacity: 1.0,
            circleStrokeWidth: 2,
            circleStrokeColor: "#FFFFFF",
          ),
        );

        if (circle != null) {
          _circles.add(circle);
          // Store marker with request ID for selective removal later
          _markerMap[request.id] = circle;
        }
      } catch (e) {
        print("Error adding marker: $e");
      }
    }

    // Fit map to show all markers
    if (_circles.isNotEmpty && _driverLocation != null) {
      _fitBounds();
    }
  }

  // Clear specific passenger marker by ID
  Future<void> clearPassengerMarkerById(String passengerId) async {
    if (_mapController == null) return;

    if (_markerMap.containsKey(passengerId)) {
      try {
        final circle = _markerMap[passengerId]!;
        await _mapController!.removeCircle(circle);
        _circles.remove(circle);
        _markerMap.remove(passengerId);
        print("Removed passenger marker with ID: $passengerId");
      } catch (e) {
        print("Error removing passenger marker: $e");
      }
    }
  }

  // Fit the map to show all markers and driver
  void _fitBounds() {
    if (_mapController == null || _circles.isEmpty || _driverLocation == null) return;

    try {
      // Start with driver location
      double minLat = _driverLocation!.latitude;
      double maxLat = _driverLocation!.latitude;
      double minLng = _driverLocation!.longitude;
      double maxLng = _driverLocation!.longitude;

      // Include all circles
      for (var circle in _circles) {
        final lat = circle.options.geometry?.latitude ?? 0;
        final lng = circle.options.geometry?.longitude ?? 0;

        minLat = min(minLat, lat);
        maxLat = max(maxLat, lat);
        minLng = min(minLng, lng);
        maxLng = max(maxLng, lng);
      }

      // Add padding
      double latPadding = max((maxLat - minLat) * 0.3, 0.01);
      double lngPadding = max((maxLng - minLng) * 0.3, 0.01);

      _mapController!.moveCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - latPadding, minLng - lngPadding),
            northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
          ),
          top: 100,
          right: 50,
          left: 50,
          bottom: 150,
        ),
      );
    } catch (e) {
      print("Error fitting bounds: $e");
    }
  }

  // Clear all passenger markers
  void clearPassengerMarkers() {
    if (_mapController == null) return;

    for (var circle in _circles) {
      _mapController!.removeCircle(circle);
    }
    _circles.clear();
    _markerMap.clear();
  }

  // Calculate and show route from driver to destination
  Future<bool> showRouteToLocation(LatLng destination) async {
    if (_driverLocation == null || _mapController == null) {
      return false;
    }

    _currentTarget = destination;

    // Clean up before showing new route
    _clearRouteLines();
    stopRouteNavigation();
    clearDestinationPreview();

    try {
      // Use OpenRouteService API to get the route
      const apiKey = '5b3ce3597851110001cf6248099f56e121c64067b5762a109e70ee9b';
      final url = 'https://api.openrouteservice.org/v2/directions/driving-car';

      final body = json.encode({
        "coordinates": [
          [_driverLocation!.longitude, _driverLocation!.latitude],
          [destination.longitude, destination.latitude],
        ],
      });

      final response = await http.post(
        Uri.parse(url),
        headers: {
          "Authorization": apiKey,
          "Content-Type": "application/json",
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];

          List<LatLng> route = [];
          if (geometry is Map && geometry['coordinates'] != null) {
            route = _decodeGeoJSON(geometry['coordinates']);
          } else if (geometry is String) {
            route = _decodePolyline(geometry);
          }

          if (route.isNotEmpty) {
            _currentRoute = route;
            _addRouteToMap(route);
            _fitRouteInView(route);
            startRouteNavigation(route, destination);
            return true;
          }
        }
      }

      // If API failed or returned empty route, use direct line
      _addDirectLineToMap(_driverLocation!, destination);
      startRouteNavigation([_driverLocation!, destination], destination);
      return true;

    } catch (e) {
      print("Error getting route: $e");
      _addDirectLineToMap(_driverLocation!, destination);
      startRouteNavigation([_driverLocation!, destination], destination);
      return true;
    }
  }

  // Start navigation along a route
  void startRouteNavigation(List<LatLng> route, LatLng destination) {
    _isNavigating = true;
    _originalRoute = List.from(route);
    _currentRoute = List.from(route);
    _currentTarget = destination;
    _lastRoutePointIndex = 0;

    // Start periodic route updates
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = Timer.periodic(Duration(seconds: 3), (_) {
      if (_driverLocation != null) {
        _updateRouteProgress(_driverLocation!);
      }
    });

    // Tell the navigation manager about the route
    _navigationManager?.startNavigation(_currentRoute, destination);
  }

  // Stop active navigation
  void stopRouteNavigation() {
    _isNavigating = false;
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = null;
    _lastRoutePointIndex = 0;
    _originalRoute.clear();
  }

  // Update the route based on driver's progress
  void _updateRouteProgress(LatLng driverLocation) {
    if (!_isNavigating || _originalRoute.isEmpty) return;

    // Find the closest point on the route to the driver
    int closestPointIndex = _findClosestPointOnRoute(driverLocation);

    // Check if driver has progressed along the route
    if (closestPointIndex > _lastRoutePointIndex) {
      _lastRoutePointIndex = closestPointIndex;
      _updateVisualRoute(closestPointIndex);
    }

    // Check for significant deviation from route
    double deviationDistance = _calculateDistanceToRoute(driverLocation, closestPointIndex);
    if (deviationDistance > _routeDeviationThreshold && _currentTarget != null) {
      _recalculateRoute(driverLocation, _currentTarget!);
    }
  }

  // Find the closest point on the route to the driver
  int _findClosestPointOnRoute(LatLng driverLocation) {
    int closestIndex = _lastRoutePointIndex;
    double minDistance = double.infinity;

    // Start searching from the last known position
    for (int i = _lastRoutePointIndex; i < _originalRoute.length; i++) {
      double distance = calculateDistance(
          driverLocation.latitude,
          driverLocation.longitude,
          _originalRoute[i].latitude,
          _originalRoute[i].longitude
      ) * 1000; // Convert to meters

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  // Calculate distance from driver to route
  double _calculateDistanceToRoute(LatLng driverLocation, int nearestPointIndex) {
    if (nearestPointIndex >= _originalRoute.length) {
      return 0;
    }

    LatLng routePoint = _originalRoute[nearestPointIndex];
    return calculateDistance(
        driverLocation.latitude,
        driverLocation.longitude,
        routePoint.latitude,
        routePoint.longitude
    ) * 1000; // Convert to meters
  }

  // Update the visual route on the map
  void _updateVisualRoute(int fromIndex) {
    if (_mapController == null) return;

    // Clear existing route lines
    _clearRouteLines();

    // Create a new route with only the remaining points
    List<LatLng> remainingRoute = _originalRoute.sublist(fromIndex);
    _currentRoute = remainingRoute;

    // Draw the new route
    if (remainingRoute.isNotEmpty) {
      _addRouteToMap(remainingRoute);
    }
  }

  // Recalculate route when driver deviates
  Future<void> _recalculateRoute(LatLng from, LatLng to) async {
    stopRouteNavigation();
    await showRouteToLocation(to);
  }

  // Clear route lines
  void _clearRouteLines() {
    if (_mapController == null) return;

    for (var line in _lines) {
      _mapController!.removeLine(line);
    }
    _lines.clear();
  }

  // Add a direct line from driver to destination
  void _addDirectLineToMap(LatLng start, LatLng end) {
    if (_mapController == null) return;

    _mapController!.addLine(
      LineOptions(
        geometry: [start, end],
        lineWidth: 4,
        lineColor: "#FF4B6C",
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _lines.add(line);
      }
    });

    _fitTwoPointsInView(start, end);
  }

  // Add route to map with enhanced visibility
  void _addRouteToMap(List<LatLng> route) {
    if (_mapController == null) return;

    // Add main route line
    _mapController!.addLine(
      LineOptions(
        geometry: route,
        lineWidth: 6,
        lineColor: "#FF4B6C",
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _lines.add(line);
      }
    });

    // Add route outline for better visibility
    _mapController!.addLine(
      LineOptions(
        geometry: route,
        lineWidth: 10,
        lineColor: "#FFFFFF",
        lineOpacity: 0.4,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _lines.add(line);
      }
    });
  }

  // Fit camera to show route
  void _fitRouteInView(List<LatLng> route) {
    if (route.isEmpty || _mapController == null) return;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (var point in route) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    // Add padding
    double latPadding = max((maxLat - minLat) * 0.2, 0.01);
    double lngPadding = max((maxLng - minLng) * 0.2, 0.01);

    _mapController!.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - latPadding, minLng - lngPadding),
          northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
        ),
        top: 150,
        right: 50,
        left: 50,
        bottom: 250,
      ),
    );
  }

  // Fit camera to show two points
  void _fitTwoPointsInView(LatLng point1, LatLng point2) {
    if (_mapController == null) return;

    _mapController!.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            min(point1.latitude, point2.latitude) - 0.01,
            min(point1.longitude, point2.longitude) - 0.01,
          ),
          northeast: LatLng(
            max(point1.latitude, point2.latitude) + 0.01,
            max(point1.longitude, point2.longitude) + 0.01,
          ),
        ),
        top: 150,
        right: 50,
        left: 50,
        bottom: 250,
      ),
    );
  }

  // Decode GeoJSON coordinates
  List<LatLng> _decodeGeoJSON(dynamic coordinates) {
    final List<LatLng> polyline = [];
    for (var point in coordinates) {
      if (point is List && point.length >= 2) {
        polyline.add(LatLng(point[1], point[0]));
      }
    }
    return polyline;
  }

  // Decode polyline
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  // Calculate distance between two points
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
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

  // Get the distance to the current target
  String getDistanceToTarget() {
    if (_driverLocation == null || _currentTarget == null) return "";

    double distanceKm = calculateDistance(
      _driverLocation!.latitude,
      _driverLocation!.longitude,
      _currentTarget!.latitude,
      _currentTarget!.longitude,
    );

    if (distanceKm < 1.0) {
      int meters = (distanceKm * 1000).round();
      return "$meters m away";
    } else {
      return "${distanceKm.toStringAsFixed(1)} km away";
    }
  }

  // Get address from location
  Future<String> getAddressFromLocation(LatLng location) async {
    const apiKey = '7197722b517046909c15f761c566b49c';
    final url = 'https://api.opencagedata.com/geocode/v1/json?q=${location.latitude}+${location.longitude}&key=$apiKey&pretty=1';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          String address = "Current Location";

          if (result['components'] != null) {
            var components = result['components'];
            if (components['road'] != null) {
              address = components['road'];
              if (components['house_number'] != null) {
                address = "${components['house_number']} $address";
              }
            } else if (components['neighbourhood'] != null) {
              address = components['neighbourhood'];
            } else if (components['suburb'] != null) {
              address = components['suburb'];
            } else if (components['city'] != null) {
              address = components['city'];
            }
          } else if (result['formatted'] != null) {
            String fullAddress = result['formatted'];
            if (fullAddress.length > 30) {
              fullAddress = fullAddress.substring(0, 27) + '...';
            }
            address = fullAddress;
          }

          return address;
        }
      }
    } catch (e) {
      print("Error getting address: $e");
    }

    return "Location at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}";
  }

  // Clear the active route
  void clearRoute() {
    _clearRouteLines();
    _currentRoute.clear();
    _currentTarget = null;
    stopRouteNavigation();
  }

  // Release resources
  void dispose() {
    _navigationManager?.dispose();
    stopRouteNavigation();
    clearPassengerMarkers();
    clearRoute();
    clearDestinationPreview();
    _mapController = null;
  }

  // Show preview of pickup and destination
  Future<void> showDestinationPreview(LatLng pickupLocation, LatLng destinationLocation) async {
    if (_mapController == null) return;

    // Clear any existing preview
    clearDestinationPreview();

    try {
      // Add pickup point marker (red circle)
      final pickupCircle = await _mapController!.addCircle(
        CircleOptions(
          geometry: pickupLocation,
          circleRadius: 10,
          circleColor: "#FF0000", // Red for pickup
          circleOpacity: 0.8,
          circleStrokeWidth: 2,
          circleStrokeColor: "#FFFFFF",
        ),
      );

      if (pickupCircle != null) {
        _previewCircles.add(pickupCircle);
      }

      // Add destination point marker (green circle)
      final destinationCircle = await _mapController!.addCircle(
        CircleOptions(
          geometry: destinationLocation,
          circleRadius: 10,
          circleColor: "#00FF00", // Green for destination
          circleOpacity: 0.8,
          circleStrokeWidth: 2,
          circleStrokeColor: "#FFFFFF",
        ),
      );

      if (destinationCircle != null) {
        _previewCircles.add(destinationCircle);
      }

      // Add a line between pickup and destination
      final previewLine = await _mapController!.addLine(
        LineOptions(
          geometry: [pickupLocation, destinationLocation],
          lineWidth: 3,
          lineColor: "#4B6CFF", // Blue line for preview
          lineOpacity: 0.7,
          lineJoin: "round",
        ),
      );

      if (previewLine != null) {
        _previewLines.add(previewLine);
      }

      // Fit both points in the camera view
      _fitTwoPointsInView(pickupLocation, destinationLocation);
    } catch (e) {
      print("Error showing destination preview: $e");
    }
  }

  // Clear destination preview markers and lines
  void clearDestinationPreview() {
    if (_mapController == null) return;

    // Clear preview circles
    for (var circle in _previewCircles) {
      _mapController!.removeCircle(circle);
    }
    _previewCircles.clear();

    // Clear preview lines
    for (var line in _previewLines) {
      _mapController!.removeLine(line);
    }
    _previewLines.clear();
  }

  // Get next point on route for navigation
  LatLng _getNextPointOnRoute(LatLng currentLocation) {
    if (_currentRoute.isEmpty) return currentLocation;

    int nextIndex = _findClosestPointOnRoute(currentLocation) + 1;
    if (nextIndex >= _currentRoute.length) nextIndex = _currentRoute.length - 1;

    return _currentRoute[nextIndex];
  }

  // Calculate bearing between two points
  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = _toRadians(start.latitude);
    double startLng = _toRadians(start.longitude);
    double endLat = _toRadians(end.latitude);
    double endLng = _toRadians(end.longitude);

    double dLng = endLng - startLng;

    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);

    double bearing = atan2(y, x);
    bearing = _toDegrees(bearing);
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  double _toDegrees(double radians) {
    return radians * (180 / pi);
  }

  // Force a route progress update
  void forceRouteProgressUpdate() {
    if (_isNavigating && _driverLocation != null && _currentRoute.isNotEmpty) {
      _updateRouteProgress(_driverLocation!);
    }
  }

  bool hasActiveRoute() {
    return _isNavigating && _currentRoute.isNotEmpty && _currentTarget != null;
  }

  void ensureNavigationActive() {
    if (_currentTarget != null && _currentRoute.isNotEmpty && !_isNavigating) {
      startRouteNavigation(_currentRoute, _currentTarget!);
    }
  }

  void addLineToCollection(Line line) {
    _lines.add(line);
  }
}

// Navigation manager that ensures proper route updates and camera positioning
class NavigationManager {
  static final NavigationManager _instance = NavigationManager._internal();
  factory NavigationManager() => _instance;
  NavigationManager._internal();

  // Controllers
  MaplibreMapController? _mapController;
  Timer? _navigationUpdateTimer;
  Timer? _cameraCorrectionTimer;

  // Navigation state
  LatLng? _currentDriverLocation;
  LatLng? _currentTarget;
  List<LatLng> _fullRoute = [];
  bool _isNavigating = false;
  int _lastProcessedIndex = 0;
  List<Line> _activeRouteLines = [];

  // Initialize with map controller
  void initialize(MaplibreMapController mapController) {
    _mapController = mapController;
    _startUpdateTimers();
  }

  // Set up timers for route and camera updates
  void _startUpdateTimers() {
    // Cancel existing timers
    _navigationUpdateTimer?.cancel();
    _cameraCorrectionTimer?.cancel();

    // Process route updates every second
    _navigationUpdateTimer = Timer.periodic(Duration(milliseconds: 1000), (_) {
      _processRouteUpdate();
    });

    // Ensure camera follows driver every 2 seconds
    _cameraCorrectionTimer = Timer.periodic(Duration(milliseconds: 2000), (_) {
      _ensureCameraFollowsDriver();
    });
  }

  // Update driver location
  void setDriverLocation(LatLng location) {
    _currentDriverLocation = location;
  }

  // Start navigation along route
  void startNavigation(List<LatLng> route, LatLng target) {
    _fullRoute = List.from(route);
    _currentTarget = target;
    _isNavigating = true;
    _lastProcessedIndex = 0;
  }

  // Keep camera centered on driver with proper bearing
  void _ensureCameraFollowsDriver() {
    if (!_isNavigating || _currentDriverLocation == null || _mapController == null) return;

    // Get bearing to next point
    LatLng nextPoint = _getNextRoutePoint();
    double bearing = _calculateBearing(_currentDriverLocation!, nextPoint);

    // Move camera with bearing for directional navigation
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentDriverLocation!,
          zoom: 17.0,
          bearing: bearing,
        ),
      ),
    );
  }

  // Get next point on route
  LatLng _getNextRoutePoint() {
    if (_fullRoute.isEmpty || _currentDriverLocation == null) {
      return _currentTarget ?? _currentDriverLocation!;
    }

    int nextIndex = _findNextPointIndex();
    return nextIndex < _fullRoute.length ? _fullRoute[nextIndex] :
    _currentTarget ?? _fullRoute.last;
  }

  // Find next point index on route
  int _findNextPointIndex() {
    if (_fullRoute.isEmpty || _currentDriverLocation == null) return 0;

    int bestIndex = _lastProcessedIndex;
    double minDistance = double.infinity;

    // Limit search to optimize performance
    int endIndex = min(_lastProcessedIndex + 50, _fullRoute.length);

    for (int i = _lastProcessedIndex; i < endIndex; i++) {
      double distance = _calculateDistance(
          _currentDriverLocation!.latitude,
          _currentDriverLocation!.longitude,
          _fullRoute[i].latitude,
          _fullRoute[i].longitude
      ) * 1000; // Convert to meters

      if (distance < minDistance) {
        minDistance = distance;
        bestIndex = i;
      }
    }

    // Return the next point after the closest one
    return min(bestIndex + 1, _fullRoute.length - 1);
  }

  // Process route updates
  void _processRouteUpdate() {
    if (!_isNavigating || _fullRoute.isEmpty || _currentDriverLocation == null || _mapController == null) return;

    // Find closest point on route to current location
    int closestIndex = _findClosestPointIndex();

    // If we've made progress along the route
    if (closestIndex > _lastProcessedIndex) {
      _lastProcessedIndex = closestIndex;
      _updateVisualRoute(closestIndex);
    }

    // Check for route deviation
    double deviationDistance = _calculateDeviationFromRoute();
    if (deviationDistance > 100) { // 100 meters
      // Leave recalculation to MapController
    }
  }

  // Find closest point on route
  int _findClosestPointIndex() {
    if (_fullRoute.isEmpty || _currentDriverLocation == null) return 0;

    int bestIndex = _lastProcessedIndex;
    double minDistance = double.infinity;

    // Limit search for performance
    int endIndex = min(_lastProcessedIndex + 50, _fullRoute.length);

    for (int i = _lastProcessedIndex; i < endIndex; i++) {
      double distance = _calculateDistance(
          _currentDriverLocation!.latitude,
          _currentDriverLocation!.longitude,
          _fullRoute[i].latitude,
          _fullRoute[i].longitude
      ) * 1000; // Convert to meters

      if (distance < minDistance) {
        minDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  // Calculate deviation from route
  double _calculateDeviationFromRoute() {
    if (_fullRoute.isEmpty || _currentDriverLocation == null) return 0;

    int closest = _findClosestPointIndex();

    return _calculateDistance(
        _currentDriverLocation!.latitude,
        _currentDriverLocation!.longitude,
        _fullRoute[closest].latitude,
        _fullRoute[closest].longitude
    ) * 1000; // Convert to meters
  }

  // Update visual route display
  void _updateVisualRoute(int fromIndex) {
    if (_mapController == null || fromIndex >= _fullRoute.length) return;

    // Clear current route lines
    _clearRouteLines();

    // Create a new route with only the remaining points
    List<LatLng> remainingRoute = _fullRoute.sublist(fromIndex);

    // Add main route line
    _mapController!.addLine(
      LineOptions(
        geometry: remainingRoute,
        lineWidth: 6,
        lineColor: "#FF4B6C",
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _activeRouteLines.add(line);
      }
    });

    // Add outline for better visibility
    _mapController!.addLine(
      LineOptions(
        geometry: remainingRoute,
        lineWidth: 10,
        lineColor: "#FFFFFF",
        lineOpacity: 0.4,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _activeRouteLines.add(line);
      }
    });
  }

  // Clear route lines
  void _clearRouteLines() {
    if (_mapController == null) return;

    for (var line in _activeRouteLines) {
      _mapController!.removeLine(line);
    }
    _activeRouteLines.clear();
  }

  // Calculate distance between points
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

  // Calculate bearing between points
  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = _toRadians(start.latitude);
    double startLng = _toRadians(start.longitude);
    double endLat = _toRadians(end.latitude);
    double endLng = _toRadians(end.longitude);

    double dLng = endLng - startLng;

    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) -
        sin(startLat) * cos(endLat) * cos(dLng);

    double bearing = atan2(y, x);
    bearing = _toDegrees(bearing);
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  // Convert degrees to radians
  double _toRadians(double degree) {
    return degree * (pi / 180);
  }

  // Convert radians to degrees
  double _toDegrees(double radians) {
    return radians * (180 / pi);
  }

  // Clean up resources
  void dispose() {
    _navigationUpdateTimer?.cancel();
    _cameraCorrectionTimer?.cancel();
    _clearRouteLines();
    _isNavigating = false;
    _fullRoute.clear();
  }
}