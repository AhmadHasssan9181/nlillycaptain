import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../services/location_service.dart';

class DebugControls extends StatelessWidget {
  final LocationService locationService;
  final LatLng? destinationLocation;
  final List<LatLng> currentRoute;

  const DebugControls({
    Key? key,
    required this.locationService,
    this.destinationLocation,
    this.currentRoute = const [],
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).viewPadding.top + 80,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, color: Colors.orange, size: 16),
                SizedBox(width: 4),
                Text(
                  "Debug Controls",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Toggle debug mode
            SizedBox(
              width: 140,
              height: 32,
              child: ElevatedButton.icon(
                icon: Icon(
                  locationService.isDebugModeEnabled ? Icons.location_off : Icons.location_on,
                  size: 14,
                ),
                label: Text(
                  locationService.isDebugModeEnabled ? "Disable Debug" : "Enable Debug",
                  style: TextStyle(fontSize: 10),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: locationService.isDebugModeEnabled ? Colors.red : Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                ),
                onPressed: () {
                  locationService.setDebugMode(!locationService.isDebugModeEnabled);
                },
              ),
            ),
            SizedBox(height: 4),

            // Jump to destination button - only visible when in debug mode and destination exists
            if (locationService.isDebugModeEnabled && destinationLocation != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: SizedBox(
                  width: 140,
                  height: 32,
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.flag, size: 14),
                    label: Text(
                      "Jump to Destination",
                      style: TextStyle(fontSize: 10),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    ),
                    onPressed: () {
                      if (destinationLocation != null) {
                        locationService.simulateArrivalAt(destinationLocation!);
                      }
                    },
                  ),
                ),
              ),

            // Help text for debug mode
            if (locationService.isDebugModeEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "Tap map to move location",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}