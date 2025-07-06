import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../services/location_service.dart';

class DebugControls extends StatefulWidget {
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
  State<DebugControls> createState() => _DebugControlsState();
}

class _DebugControlsState extends State<DebugControls> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).viewPadding.top + 80,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.locationService.isDebugModeEnabled
                ? Colors.orange.withOpacity(0.6)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              spreadRadius: 2,
              offset: Offset(0, 3),
            ),
          ],
        ),
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white70,
                    size: 16,
                  ),
                ],
              ),
            ),

            if (_expanded || widget.locationService.isDebugModeEnabled) ...[
              SizedBox(height: 8),
              // Toggle debug mode
              SizedBox(
                width: 140,
                height: 32,
                child: ElevatedButton.icon(
                  icon: Icon(
                    widget.locationService.isDebugModeEnabled ? Icons.location_off : Icons.location_on,
                    size: 14,
                  ),
                  label: Text(
                    widget.locationService.isDebugModeEnabled ? "Disable Debug" : "Enable Debug",
                    style: TextStyle(fontSize: 10),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.locationService.isDebugModeEnabled ? Colors.red : Colors.blue,
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    elevation: 3,
                  ),
                  onPressed: () {
                    widget.locationService.setDebugMode(!widget.locationService.isDebugModeEnabled);
                    setState(() {});  // Refresh UI
                  },
                ),
              ),

              // Jump to destination button - only visible when in debug mode and destination exists
              if (widget.locationService.isDebugModeEnabled && widget.destinationLocation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
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
                        elevation: 2,
                      ),
                      onPressed: () {
                        if (widget.destinationLocation != null) {
                          widget.locationService.simulateArrivalAt(widget.destinationLocation!);
                        }
                      },
                    ),
                  ),
                ),

              // Route simulation - only visible when in debug mode and route exists
              if (widget.locationService.isDebugModeEnabled && widget.currentRoute.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    width: 140,
                    height: 32,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.route, size: 14),
                      label: Text(
                        "Simulate Route",
                        style: TextStyle(fontSize: 10),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        elevation: 2,
                      ),
                      onPressed: () {
                        if (widget.currentRoute.isNotEmpty) {
                          widget.locationService.simulateRouteProgress(
                              widget.currentRoute,
                              (widget.currentRoute.length / 10).round().clamp(1, 10)
                          );
                        }
                      },
                    ),
                  ),
                ),

              // NEW: Quick Jump Location Buttons - only visible in debug mode
              if (widget.locationService.isDebugModeEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        "Quick Jump Locations:",
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                      SizedBox(height: 4),

                      // Quick jump buttons row 1
                      Row(
                        children: [
                          // Location 1 - 500m North
                          ElevatedButton(
                            onPressed: () {
                              // Get a location ~500m North from a default position
                              widget.locationService.simulateArrivalAt(
                                  LatLng(33.5819, 73.0534)
                              );
                            },
                            child: Text("North", style: TextStyle(fontSize: 9)),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.all(4),
                              minimumSize: Size(45, 25),
                              backgroundColor: Colors.blue.shade700,
                              elevation: 1,
                            ),
                          ),
                          SizedBox(width: 4),

                          // Location 2 - 500m East
                          ElevatedButton(
                            onPressed: () {
                              widget.locationService.simulateArrivalAt(
                                  LatLng(33.5773, 73.0595)
                              );
                            },
                            child: Text("East", style: TextStyle(fontSize: 9)),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.all(4),
                              minimumSize: Size(45, 25),
                              backgroundColor: Colors.blue.shade700,
                              elevation: 1,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),

                      // Second row
                      Row(
                        children: [
                          // Location 3 - 500m South
                          ElevatedButton(
                            onPressed: () {
                              widget.locationService.simulateArrivalAt(
                                  LatLng(33.5730, 73.0534)
                              );
                            },
                            child: Text("South", style: TextStyle(fontSize: 9)),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.all(4),
                              minimumSize: Size(45, 25),
                              backgroundColor: Colors.blue.shade700,
                              elevation: 1,
                            ),
                          ),
                          SizedBox(width: 4),

                          // Location 4 - 500m West
                          ElevatedButton(
                            onPressed: () {
                              widget.locationService.simulateArrivalAt(
                                  LatLng(33.5773, 73.0475)
                              );
                            },
                            child: Text("West", style: TextStyle(fontSize: 9)),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.all(4),
                              minimumSize: Size(45, 25),
                              backgroundColor: Colors.blue.shade700,
                              elevation: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Help text for debug mode
              if (widget.locationService.isDebugModeEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app, color: Colors.orange, size: 10),
                        SizedBox(width: 4),
                        Text(
                          "Tap map to move location",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}