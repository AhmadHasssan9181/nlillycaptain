import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../passenger_model.dart';

class MapController {
  MaplibreMapController? _mapController;
  LatLng? _driverLocation;
  List<LatLng> _currentRoute = [];
  List<Circle> _circles = [];
  List<Line> _lines = [];
  LatLng? _currentTarget;

  // Preview related variables
  List<Circle> _previewCircles = [];
  List<Line> _previewLines = [];

  // System info
  final String _currentTimestamp = "2025-06-03 18:15:48";
  final String _currentUserLogin = "Lilydebug";

  // Getters
  MaplibreMapController? get mapController => _mapController;
  LatLng? get driverLocation => _driverLocation;
  LatLng? get currentTarget => _currentTarget;
  List<LatLng> get currentRoute => _currentRoute;

  void setMapController(MaplibreMapController controller) {
    _mapController = controller;
    print("[$_currentTimestamp] [$_currentUserLogin] Map controller set");
  }

  void updateDriverLocation(LatLng location) {
    _driverLocation = location;
  }

  void moveCameraToLocation(LatLng location) {
    _mapController?.moveCamera(
      CameraUpdate.newLatLngZoom(location, 15.0),
    );
  }

  // Add passenger markers to the map using circles
  Future<void> addPassengerMarkersToMap(List<PassengerRequest> requests) async {
    // Clear any existing markers
    clearPassengerMarkers();

    print("[$_currentTimestamp] [$_currentUserLogin] Adding ${requests.length} passenger markers");

    // For each request, add a circle at the pickup location
    for (var request in requests) {
      try {
        final pickupLocation = LatLng(request.pickupLat, request.pickupLng);

        // Add a circle for the pickup location
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
        }

        print("[$_currentTimestamp] [$_currentUserLogin] Added marker for passenger at (${pickupLocation.latitude}, ${pickupLocation.longitude})");
      } catch (e) {
        print("[$_currentTimestamp] [$_currentUserLogin] Error adding marker: $e");
      }
    }

    // Fit the map to show all markers
    if (_circles.isNotEmpty && _driverLocation != null) {
      _fitBounds();
    }
  }

  // Fit the map bounds to show all markers and driver location
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
        final lat = circle.options.geometry?.latitude;
        final lng = circle.options.geometry?.longitude;

        minLat = min(minLat, lat!);
        maxLat = max(maxLat, lat);
        minLng = min(minLng, lng!);
        maxLng = max(maxLng, lng);
      }

      // Add padding
      double latPadding = (maxLat - minLat) * 0.3;
      double lngPadding = (maxLng - minLng) * 0.3;

      // Ensure minimum padding
      latPadding = max(latPadding, 0.01);
      lngPadding = max(lngPadding, 0.01);

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

      print("[$_currentTimestamp] [$_currentUserLogin] Camera adjusted to show all markers");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error fitting bounds: $e");
    }
  }

  // Clear passenger markers
  void clearPassengerMarkers() {
    if (_mapController == null) return;

    try {
      // Clear circles
      for (var circle in _circles) {
        _mapController!.removeCircle(circle);
      }
      _circles.clear();

      print("[$_currentTimestamp] [$_currentUserLogin] Passenger markers cleared");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error clearing passenger markers: $e");
    }
  }

// Calculate and show route from driver to destination
  Future<bool> showRouteToLocation(LatLng destination) async {
    if (_driverLocation == null || _mapController == null) {
      print("[$_currentTimestamp] [$_currentUserLogin] Can't show route: driver location or map controller is null");
      return false;
    }

    print("[$_currentTimestamp] [$_currentUserLogin] Calculating route to (${destination.latitude}, ${destination.longitude})");

    _currentTarget = destination;

    // Clear existing route lines
    _clearRouteLines();

    // ADDED THIS LINE: Clear any destination preview before showing route
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

        if (data['routes'] == null || data['routes'].isEmpty) {
          print("[$_currentTimestamp] [$_currentUserLogin] No routes found, using direct line");
          _addDirectLineToMap(_driverLocation!, destination);
          return true;
        }

        final geometry = data['routes'][0]['geometry'];

        List<LatLng> route = [];
        if (geometry is Map && geometry['coordinates'] != null) {
          route = _decodeGeoJSON(geometry['coordinates']);
        } else if (geometry is String) {
          route = _decodePolyline(geometry);
        }

        _currentRoute = route;

        if (_currentRoute.isEmpty) {
          print("[$_currentTimestamp] [$_currentUserLogin] Empty route, using direct line");
          _addDirectLineToMap(_driverLocation!, destination);
        } else {
          _addRouteToMap(_currentRoute);
          _fitRouteInView(_currentRoute);
          print("[$_currentTimestamp] [$_currentUserLogin] Route displayed with ${_currentRoute.length} points");
        }

        return true;
      } else {
        print("[$_currentTimestamp] [$_currentUserLogin] API returned status ${response.statusCode}, using direct line");
        _addDirectLineToMap(_driverLocation!, destination);
        return true;
      }
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error getting route: $e, using direct line");
      _addDirectLineToMap(_driverLocation!, destination);
      return true;
    }
  }
  // Clear route lines
  void _clearRouteLines() {
    if (_mapController == null) return;

    try {
      for (var line in _lines) {
        _mapController!.removeLine(line);
      }
      _lines.clear();
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error clearing route lines: $e");
    }
  }

  // Add a direct line from driver to destination
  void _addDirectLineToMap(LatLng start, LatLng end) {
    if (_mapController == null) return;

    try {
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
      print("[$_currentTimestamp] [$_currentUserLogin] Direct line added to map");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error adding direct line: $e");
    }
  }

  // Add a multi-point route to map
  void _addRouteToMap(List<LatLng> route) {
    if (_mapController == null) return;

    try {
      _mapController!.addLine(
        LineOptions(
          geometry: route,
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

      print("[$_currentTimestamp] [$_currentUserLogin] Route line added to map");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error adding route to map: $e");
    }
  }

  // Fit camera to show route
  void _fitRouteInView(List<LatLng> route) {
    if (route.isEmpty || _mapController == null) return;

    try {
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
      double latPadding = (maxLat - minLat) * 0.2;
      double lngPadding = (maxLng - minLng) * 0.2;

      latPadding = max(latPadding, 0.01);
      lngPadding = max(lngPadding, 0.01);

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

      print("[$_currentTimestamp] [$_currentUserLogin] Camera adjusted to show route");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error fitting route in view: $e");
    }
  }

  // Fit camera to show two points
  void _fitTwoPointsInView(LatLng point1, LatLng point2) {
    if (_mapController == null) return;

    try {
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
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error fitting two points in view: $e");
    }
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
      print("[$_currentTimestamp] [$_currentUserLogin] Error getting address: $e");
    }

    return "Location at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}";
  }

  // Clear the route
  void clearRoute() {
    _clearRouteLines();
    _currentRoute.clear();
    _currentTarget = null;
    print("[$_currentTimestamp] [$_currentUserLogin] Route cleared");
  }

  // Dispose
  void dispose() {
    clearPassengerMarkers();
    clearRoute();
    clearDestinationPreview(); // Clear any destination previews on dispose
    _mapController = null;
    print("[$_currentTimestamp] [$_currentUserLogin] MapController disposed");
  }

  // ADDED METHODS: For destination preview

  // Show preview of pickup and destination locations on the map
  // Show preview of pickup and destination locations on the map
  Future<void> showDestinationPreview(LatLng pickupLocation, LatLng destinationLocation) async {
    if (_mapController == null) {
      print("[$_currentTimestamp] [$_currentUserLogin] Can't show destination preview: map controller is null");
      return;
    }

    // Clear any existing preview
    clearDestinationPreview();

    print("[$_currentTimestamp] [$_currentUserLogin] Showing destination preview");

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

      // Add a line between pickup and destination (without dashed pattern)
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

      print("[$_currentTimestamp] [$_currentUserLogin] Destination preview displayed");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error showing destination preview: $e");
    }
  }
  // Clear destination preview markers and lines
  void clearDestinationPreview() {
    if (_mapController == null) return;

    try {
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

      print("[$_currentTimestamp] [$_currentUserLogin] Destination preview cleared");
    } catch (e) {
      print("[$_currentTimestamp] [$_currentUserLogin] Error clearing destination preview: $e");
    }
  }
}