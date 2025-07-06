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

  // Navigation state
  bool _isNavigating = false;

  // Getters
  MaplibreMapController? get mapController => _mapController;
  LatLng? get driverLocation => _driverLocation;
  LatLng? get currentTarget => _currentTarget;
  List<LatLng> get currentRoute => _currentRoute;
  bool get isNavigating => _isNavigating;

  // Initialize the map controller
  void setMapController(MaplibreMapController controller) {
    _mapController = controller;
    print("Map controller initialized");
  }

  // Central location update method
  void updateDriverLocation(LatLng location) {
    if (location.latitude == 0 && location.longitude == 0) {
      print("Ignoring invalid location (0,0)");
      return;
    }

    _driverLocation = location;
    print("Driver location updated to: (${location.latitude}, ${location.longitude})");

    // Update navigation state if needed
    if (_currentTarget != null && _currentRoute.isNotEmpty && !_isNavigating) {
      _isNavigating = true;
    }
  }

  // Get the actual blue dot position from MapLibre
  Future<LatLng?> getActualMapPosition() async {
    if (_mapController == null) return null;

    try {
      final position = await _mapController!.requestMyLocationLatLng();
      if (position != null) {
        print("Got actual map position: (${position.latitude}, ${position.longitude})");
      }
      return position;
    } catch (e) {
      print("Error getting actual map position: $e");
      return null;
    }
  }

  // Recalculate route using the ACTUAL map position
  Future<bool> recalculateRouteFromActualPosition() async {
    if (_mapController == null || _currentTarget == null) {
      print("Cannot recalculate: map controller or target is null");
      return false;
    }

    // Get the actual blue dot position from the map
    final actualPosition = await getActualMapPosition();
    if (actualPosition == null) {
      print("Failed to get actual position from map");
      return false;
    }

    // Update our stored driver location
    _driverLocation = actualPosition;
    print("Recalculating route from actual position: (${actualPosition.latitude}, ${actualPosition.longitude})");

    // Clear existing route
    clearRoute();

    // Calculate new route
    return await showRouteToLocation(_currentTarget!);
  }

  // Calculate and show route from driver to destination
  Future<bool> showRouteToLocation(LatLng destination) async {
    if (_driverLocation == null || _mapController == null) {
      print("Cannot show route: driver location or map controller is null");
      return false;
    }

    _currentTarget = destination;

    // Clean up before showing new route
    clearRoute();

    try {
      print("Calculating route from: (${_driverLocation!.latitude}, ${_driverLocation!.longitude}) to: (${destination.latitude}, ${destination.longitude})");

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
            print("Route calculated successfully with ${route.length} points");
            _isNavigating = true;
            return true;
          }
        }
      }

      // If API failed or returned empty route, use direct line
      print("Using direct line as fallback");
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

  // Move camera to specific location - ONLY WHEN EXPLICITLY CALLED
  void moveCameraToLocation(LatLng location) {
    if (_mapController == null) return;

    print("Moving camera to: (${location.latitude}, ${location.longitude})");
    _mapController!.moveCamera(
      CameraUpdate.newLatLngZoom(location, 16.0),
    );
  }

  // Fit map to show route - ONLY WHEN EXPLICITLY CALLED
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

  // Add route to map
  void _addRouteToMap(List<LatLng> route) {
    if (_mapController == null) return;

    // Add main route line
    _mapController!.addLine(
      LineOptions(
        geometry: route,
        lineWidth: 6,
        lineColor: "#FF4B6C",  // Pink route color
        lineOpacity: 0.8,
        lineJoin: "round",
      ),
    ).then((line) {
      if (line != null) {
        _routeLines.add(line);
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
        _routeLines.add(line);
      }
    });
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

  // Show destination preview
  Future<void> showDestinationPreview(LatLng pickupLocation, LatLng destinationLocation) async {
    if (_mapController == null) return;

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

    // Add connecting line
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

  // Get distance to target
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

  // Clean up resources
  void dispose() {
    clearPassengerMarkers();
    clearRoute();
    clearDestinationPreview();

    // Unregister from LocationBridge
    LocationBridge().unregisterMapController(this);

    _mapController = null;
  }
}