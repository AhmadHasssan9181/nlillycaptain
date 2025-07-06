import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../location_bridge.dart';
import '../passenger_model.dart';

class MapController {
  // Core controller
  MaplibreMapController? _mapController;

  // Location and routing data
  LatLng? _driverLocation;
  LatLng? _currentTarget;
  List<LatLng> _currentRoute = [];

  // Map UI elements
  List<Circle> _circles = [];  // Passenger pickup markers
  Map<String, Circle> _markerMap = {}; // Track markers by ID for selective removal
  List<Line> _routeLines = [];
  List<Circle> _previewCircles = [];
  List<Line> _previewLines = [];
  bool autoRecalculateEnabled = true;

  // Navigation state
  bool _isNavigating = false;

  // Route tracking
  List<double> _cumulativeDistances = [];
  double _totalRouteDistance = 0.0;
  Timer? _locationSyncTimer;
  bool _isRecalculating = false;
  final double _recalculationThreshold = 10.0; // meters
  int _lastClosestPointIndex = 0;

  // Getters
  MaplibreMapController? get mapController => _mapController;
  LatLng? get driverLocation => _driverLocation;
  LatLng? get currentTarget => _currentTarget;
  List<LatLng> get currentRoute => _currentRoute;
  bool get isNavigating => _isNavigating;

  // Called whenever a new route is calculated
  void _calculateCumulativeDistances(List<LatLng> route) {
    _cumulativeDistances = [];
    _totalRouteDistance = 0.0;
    _lastClosestPointIndex = 0;

    if (route.isEmpty) return;

    _cumulativeDistances.add(0.0); // First point has distance 0

    for (int i = 1; i < route.length; i++) {
      double segmentDist = calculateDistance(
          route[i-1].latitude, route[i-1].longitude,
          route[i].latitude, route[i].longitude
      );
      _totalRouteDistance += segmentDist;
      _cumulativeDistances.add(_totalRouteDistance);
    }
  }

  // Get remaining distance to destination as driver moves
  String getDistanceToTarget() {
    if (_driverLocation == null || _currentTarget == null ||
        _currentRoute.isEmpty || _cumulativeDistances.isEmpty) {
      return "";
    }

    // Find closest point on route to current location
    double minDist = double.infinity;
    int closestIdx = 0;

    // Only check a reasonable number of points for performance
    // Start from last known closest point
    int startIdx = max(0, _lastClosestPointIndex - 5);
    int endIdx = min(_currentRoute.length, _lastClosestPointIndex + 20);

    for (int i = startIdx; i < endIdx; i++) {
      double dist = calculateDistance(
          _driverLocation!.latitude, _driverLocation!.longitude,
          _currentRoute[i].latitude, _currentRoute[i].longitude
      );

      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }

    // Store for next calculation
    _lastClosestPointIndex = closestIdx;

    // If off route, recalculate
    if (minDist * 1000 > 10.0) {
      // Avoid recalculating too often with a simple debounce
      if (!_isRecalculating) {
        _isRecalculating = true;
        _recalculateRoute().then((success) {
          _isRecalculating = false;
        });
      }
    }

    // Calculate remaining distance along route
    double remainingDistance = _totalRouteDistance - _cumulativeDistances[closestIdx];
    remainingDistance = max(0.0, remainingDistance);

    // Format distance for display
    if (remainingDistance < 1.0) {
      int meters = (remainingDistance * 1000).round();
      return "$meters m away";
    } else {
      return "${remainingDistance.toStringAsFixed(1)} km away";
    }
  }

  // Recalculate route when driver deviates
  Future<bool> _recalculateRoute() async {
    if (_currentTarget == null || _driverLocation == null) {
      return false;
    }

    // Clear existing route
    clearRoute();

    // Calculate new route
    try {
      return await showRouteToLocation(_currentTarget!);
    } catch (e) {
      print("Exception during route recalculation: $e");
      return false;
    }
  }

  Future<bool> checkAndRecalculateRouteIfNeeded() async {
    if (!autoRecalculateEnabled) {
      return false;
    }

    if (_mapController == null || _driverLocation == null ||
        _currentTarget == null || _currentRoute.isEmpty) {
      return false;
    }

    if (_isRecalculating) {
      return false;
    }

    // Find closest point on route to current location
    double minDist = double.infinity;
    for (var point in _currentRoute) {
      double dist = calculateDistance(
          _driverLocation!.latitude, _driverLocation!.longitude,
          point.latitude, point.longitude
      );
      minDist = min(minDist, dist);
    }

    // Convert to meters
    double distanceMeters = minDist * 1000;

    // Check if we're off route
    if (distanceMeters > 10.0) {
      _isRecalculating = true;

      try {
        // Clear existing route
        clearRoute();

        // Calculate new route from current position
        bool success = await showRouteToLocation(_currentTarget!);

        _isRecalculating = false;
        return success;
      } catch (e) {
        _isRecalculating = false;
        print("Error recalculating route: $e");
        return false;
      }
    }

    return false;
  }

  // Update the driver location
  void updateDriverLocation(LatLng location) {
    if (location.latitude == 0 && location.longitude == 0) return;

    _driverLocation = location;

    // If we have a route and target, update distances
    if (_currentTarget != null && _currentRoute.isNotEmpty) {
      if (!_isNavigating) _isNavigating = true;

      // getDistanceToTarget will check for deviations and trigger recalculation
      getDistanceToTarget();
    }
  }

  // Updated route display method
  void _addRouteToMap(List<LatLng> route) {
    if (_mapController == null) return;

    // Calculate cumulative distances for this route
    _calculateCumulativeDistances(route);

    // Add route outline (wider white line underneath for better visibility)
    _mapController!.addLine(
      LineOptions(
        geometry: route,
        lineWidth: 10,
        lineColor: "#FFFFFF",
        lineOpacity: 0.4,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) _routeLines.add(line);
    });

    // Add primary route line
    _mapController!.addLine(
      LineOptions(
        geometry: route,
        lineWidth: 6,
        lineColor: "#FF4B6C",
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) _routeLines.add(line);
    });
  }

  void notifyRouteChanged() {
    if (_currentRoute.isNotEmpty) {
      _calculateCumulativeDistances(_currentRoute);
    }
  }

  // Initialize the map controller
  void setMapController(MaplibreMapController controller) {
    _mapController = controller;
  }

  // Get the actual blue dot position from MapLibre
  Future<LatLng?> getActualMapPosition() async {
    if (_mapController == null) return null;

    try {
      return await _mapController!.requestMyLocationLatLng();
    } catch (e) {
      print("Error getting actual map position: $e");
      return null;
    }
  }

  // Recalculate route using the actual map position
  Future<bool> recalculateRouteFromActualPosition() async {
    if (_mapController == null || _currentTarget == null) {
      return false;
    }

    // Get the actual blue dot position from the map
    final actualPosition = await getActualMapPosition();
    if (actualPosition == null) {
      return false;
    }

    // Update our stored driver location
    _driverLocation = actualPosition;

    // Clear existing route
    clearRoute();

    // Calculate new route
    return await showRouteToLocation(_currentTarget!);
  }

  Future<bool> showRouteToLocation(LatLng destination) async {
    if (_driverLocation == null || _mapController == null) {
      return false;
    }

    _currentTarget = destination;

    // Clean up before showing new route
    clearRoute();

    // Start periodic route deviation checking
    _locationSyncTimer?.cancel();
    _locationSyncTimer = Timer.periodic(Duration(seconds: 2), (_) {
      checkAndRecalculateRouteIfNeeded();
    });

    try {
      // Use OpenRouteService API
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
            _calculateCumulativeDistances(route);
            _isNavigating = true;
            return true;
          }
        }
      }

      // If API failed or returned empty route, use direct line
      _addDirectLineToMap(_driverLocation!, destination);
      _currentRoute = [_driverLocation!, destination];
      _isNavigating = true;
      return true;

    } catch (e) {
      print("Error getting route: $e");
      _addDirectLineToMap(_driverLocation!, destination);
      _currentRoute = [_driverLocation!, destination];
      _isNavigating = true;
      return true;
    }
  }

  // Move camera to specific location
  void moveCameraToLocation(LatLng location) {
    if (_mapController == null) return;

    _mapController!.moveCamera(
      CameraUpdate.newLatLngZoom(location, 16.0),
    );
  }

  // Fit map to show route
  void fitRouteInView(List<LatLng> route) {
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

  // Clear route lines
  void _clearRouteLines() {
    if (_mapController == null) return;

    for (var line in _routeLines) {
      _mapController!.removeLine(line);
    }
    _routeLines.clear();
  }

  // Add direct line between points
  void _addDirectLineToMap(LatLng start, LatLng end) {
    if (_mapController == null) return;

    _mapController!.addLine(
      LineOptions(
        geometry: [start, end],
        lineWidth: 6,
        lineColor: "#FF4B6C",  // Pink line color
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _routeLines.add(line);
      }
    });
  }

  // Add passenger markers to map
  Future<void> addPassengerMarkersToMap(List<PassengerRequest> requests) async {
    clearPassengerMarkers();

    if (_mapController == null) return;

    for (var request in requests) {
      final pickupLocation = LatLng(request.pickupLat, request.pickupLng);

      final circle = await _mapController!.addCircle(
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
        _markerMap[request.id] = circle;
      }
    }
  }

  // Clear passenger marker by ID
  Future<void> clearPassengerMarkerById(String passengerId) async {
    if (_mapController == null) return;

    if (_markerMap.containsKey(passengerId)) {
      await _mapController!.removeCircle(_markerMap[passengerId]!);
      _circles.remove(_markerMap[passengerId]);
      _markerMap.remove(passengerId);
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

  Future<void> showDestinationPreview(LatLng pickupLocation, LatLng destinationLocation) async {
    if (_mapController == null) return;

    // Clear any existing preview first
    clearDestinationPreview();

    // Add pickup marker
    final pickupCircle = await _mapController!.addCircle(
      CircleOptions(
        geometry: pickupLocation,
        circleRadius: 10,
        circleColor: "#FF0000",
        circleOpacity: 0.8,
        circleStrokeWidth: 2,
        circleStrokeColor: "#FFFFFF",
      ),
    );

    if (pickupCircle != null) {
      _previewCircles.add(pickupCircle);
    }

    // Add destination marker
    final destinationCircle = await _mapController!.addCircle(
      CircleOptions(
        geometry: destinationLocation,
        circleRadius: 10,
        circleColor: "#00FF00",
        circleOpacity: 0.8,
        circleStrokeWidth: 2,
        circleStrokeColor: "#FFFFFF",
      ),
    );

    if (destinationCircle != null) {
      _previewCircles.add(destinationCircle);
    }

    try {
      // Calculate actual route
      const apiKey = '5b3ce3597851110001cf6248099f56e121c64067b5762a109e70ee9b';
      final url = 'https://api.openrouteservice.org/v2/directions/driving-car';

      final body = json.encode({
        "coordinates": [
          [pickupLocation.longitude, pickupLocation.latitude],
          [destinationLocation.longitude, destinationLocation.latitude],
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

      List<LatLng> previewRoute = [];
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];
          if (geometry is Map && geometry['coordinates'] != null) {
            previewRoute = _decodeGeoJSON(geometry['coordinates']);
          } else if (geometry is String) {
            previewRoute = _decodePolyline(geometry);
          }
        }
      }

      if (previewRoute.isNotEmpty) {
        // Add actual route line
        final previewLine = await _mapController!.addLine(
          LineOptions(
            geometry: previewRoute,
            lineWidth: 4,
            lineColor: "#4B6CFF",  // Blue preview line
            lineOpacity: 0.7,
            lineJoin: "round",
          ),
        );

        if (previewLine != null) {
          _previewLines.add(previewLine);
        }

        // Add route outline
        final outlineLine = await _mapController!.addLine(
          LineOptions(
            geometry: previewRoute,
            lineWidth: 7,
            lineColor: "#FFFFFF",
            lineOpacity: 0.4,
            lineJoin: "round",
          ),
        );

        if (outlineLine != null) {
          _previewLines.add(outlineLine);
        }
      } else {
        // Fallback to direct line if route calculation fails
        final previewLine = await _mapController!.addLine(
          LineOptions(
            geometry: [pickupLocation, destinationLocation],
            lineWidth: 3,
            lineColor: "#4B6CFF",  // Blue preview line
            lineOpacity: 0.7,
            lineJoin: "round",
          ),
        );

        if (previewLine != null) {
          _previewLines.add(previewLine);
        }
      }

    } catch (e) {
      print("Error calculating preview route: $e");
      // Add fallback direct line
      final previewLine = await _mapController!.addLine(
        LineOptions(
          geometry: [pickupLocation, destinationLocation],
          lineWidth: 3,
          lineColor: "#4B6CFF",  // Blue preview line
          lineOpacity: 0.7,
          lineJoin: "round",
        ),
      );

      if (previewLine != null) {
        _previewLines.add(previewLine);
      }
    }

    // Fit both points in the camera view
    _fitTwoPointsInView(pickupLocation, destinationLocation);
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

  // Clear destination preview
  void clearDestinationPreview() {
    if (_mapController == null) return;

    for (var circle in _previewCircles) {
      _mapController!.removeCircle(circle);
    }
    _previewCircles.clear();

    for (var line in _previewLines) {
      _mapController!.removeLine(line);
    }
    _previewLines.clear();
  }

  // Clear the active route
  void clearRoute() {
    _clearRouteLines();
    _currentRoute.clear();
    _currentTarget = null;
    _isNavigating = false;
  }

  // Decode polyline
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
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

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // Decode GeoJSON
  List<LatLng> _decodeGeoJSON(dynamic coordinates) {
    List<LatLng> points = [];
    for (var point in coordinates) {
      if (point is List && point.length >= 2) {
        points.add(LatLng(point[1], point[0]));
      }
    }
    return points;
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
          String address = "Current location";

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

    return "Current location";
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

  bool hasActiveRoute() {
    return _isNavigating && _currentRoute.isNotEmpty && _currentTarget != null;
  }

  void dispose() {
    _locationSyncTimer?.cancel();
    clearPassengerMarkers();
    clearRoute();
    clearDestinationPreview();
    LocationBridge().unregisterMapController(this);
    _mapController = null;
  }
}