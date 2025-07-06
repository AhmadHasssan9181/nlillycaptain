import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lilycaptain/passenger_model.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

// Local imports
import '../controller/map_controller.dart';
import '../controller/ride_controller.dart';
import '../location_bridge.dart';
import '../location_manager.dart';
import '../main.dart';
import '../services/permission_service.dart';
import '../widgets/app_drawer.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../providers/emergency_sos_provider.dart';
import '../services/emergency_sos_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/ride_history_screen.dart';  // Add this import
import '../screens/earnings_screen.dart';
import '../services/location_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final MapController _mapController;
  late final RideController _rideController;
  Timer? _locationSyncTimer;

  bool _isBottomPanelMinimized = false;
  bool _controllersInitialized = false;

  bool _showRideHistoryScreen = false;
  bool _showEarningsScreen = false;
  LocationService _locationService = LocationService();
  bool _isLocationServiceInitialized = false;


  String _locationName = "Loading location...";
  bool _isLoadingAddress = false;
  bool _showProfileScreen = false;
  bool _showSettingsScreen = false;

  bool _showRequestPreview = false;
  PassengerRequest? _previewedRequest;

  late EmergencySosService _sosService;
  bool _isSosInitialized = false;
  Timer? _routeMonitorTimer;
  bool _autoFindRequests = false;
  Timer? _autoFindTimer;

  Timer? _routeCheckTimer;

  @override
  void initState() {
    super.initState();

    // Initialize everything only once
    _initializeControllers();
    _initializeEmergencySOS();
    _initializeLocationService();
    _checkPermissions();

    // Use a single timer for location sync with adaptive interval
    _setupLocationSyncTimer();

    // Set up ride state change listener
    _setupRideStateListener();

    // Configure UI
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

// Set up location sync timer with adaptive interval
  void _setupLocationSyncTimer() {
    _locationSyncTimer?.cancel();
    int interval = _rideController.isInRide ? 2 : 5;
    _locationSyncTimer = Timer.periodic(Duration(seconds: interval), (_) {
      _syncActualMapPosition();
    });
  }

// Set up ride state change listener
  void _setupRideStateListener() {
    _rideController.addListener(() {
      // Update sync timer frequency based on ride state
      _setupLocationSyncTimer();

      // Handle request fetching based on online status
      if (_rideController.isOnline && !_rideController.isInRide) {
        _startAutoFindRequests();
      } else {
        _stopAutoFindRequests();
      }
    });
  }



  void _startAutoFindRequests() {
    _autoFindTimer?.cancel();
    _autoFindTimer = Timer.periodic(Duration(seconds: 15), (_) async {
      if (!_rideController.isLoadingRequests && _rideController.isOnline && !_rideController.isInRide) {
        print("Auto-fetching requests...");
        await _rideController.fetchNearbyRequests();
        if (_rideController.nearbyRequests.isNotEmpty && _mapController.mapController != null) {
          await _mapController.addPassengerMarkersToMap(_rideController.nearbyRequests);

          // Show requests if any are found
          if (_rideController.nearbyRequests.isNotEmpty) {
            print("Found ${_rideController.nearbyRequests.length} requests, showing list");
            _rideController.setShowRequestsList(true);
          }
        }
      }
    });
  }

  void _stopAutoFindRequests() {
    _autoFindTimer?.cancel();
    _autoFindTimer = null;
  }

  void _onMapCreated(MaplibreMapController controller) {
    // Set controller in MapController
    _mapController.setMapController(controller);

    // No need to call _startRouteMonitoring() since MapController already handles it

    // Calculate initial route distances if route exists
    Future.delayed(Duration(seconds: 1), () {
      if (_mapController.currentRoute.isNotEmpty) {
        // Let MapController handle this
        _mapController.notifyRouteChanged();
      }
    });
  }

  void _syncActualMapPosition() {
    if (_mapController.mapController == null) return;

    _mapController.mapController!.requestMyLocationLatLng().then((location) {
      if (location != null) {
        // Update the location through LocationBridge
        LocationBridge().updateLocation(location);

        // MapController will handle route progress tracking internally
        // when updateDriverLocation is called via LocationBridge

        print("🔵 Synced actual map position: (${location.latitude}, ${location.longitude})");
      }
    }).catchError((error) {
      print("Error getting actual map position: $error");
    });
  }

  void _initializeLocationService() {
    if (!_isLocationServiceInitialized) {
      // No need to create the service instance here since it's already initialized

      // Get the LocationBridge from provider
      final locationBridge = ref.read(locationBridgeProvider);

      // Register MapController directly with LocationBridge if it's already initialized
      if (_controllersInitialized) {
        locationBridge.registerMapController(_mapController);
        locationBridge.registerRideController(_rideController);
      }

      // Configure update frequency
      _locationService.configure(
        normalIntervalMs: 10000,  // 10 seconds when not in ride
        rideIntervalMs: 3000,     // 3 seconds during active ride
      );

      // Set callback for location updates
      _locationService.onLocationChanged = (LatLng location) {
        print("📱 Location update received: (${location.latitude}, ${location.longitude})");
      };

      // Start tracking
      _locationService.startTracking();

      // Listen for ride state changes to adjust update frequency
      _rideController.addListener(() {
        _locationService.setRideMode(_rideController.isInRide);
      });

      _isLocationServiceInitialized = true;
    }
  }

  void _initializeEmergencySOS() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isSosInitialized) {
        // Initialize the SOS service
        _sosService = EmergencySosService(
          onCrashDetected: () {
            print("Crash detected - preparing emergency response");
          },
          onSosActivated: () {
            print("SOS activated - showing emergency overlay");
            ref.read(emergencySosProvider.notifier).activateSOS();
          },
          onSosCancelled: () {
            print("SOS cancelled - removing emergency overlay");
            ref.read(emergencySosProvider.notifier).deactivateSOS();
          },
          onCountdownTick: (seconds) {
            print("Emergency countdown: $seconds seconds remaining");
            ref.read(emergencySosProvider.notifier).updateCountdown(seconds);
          },
        );

        // Register the service with the provider
        ref.read(emergencySosServiceProvider.notifier).update((_) => _sosService);

        // Start monitoring for crashes
        _sosService.startMonitoring();
        _isSosInitialized = true;
      }
    });
  }

  void _initializeControllers() {
    if (!_controllersInitialized) {
      _mapController = MapController();
      _rideController = RideController();

      // Register controllers with LocationBridge
      final locationBridge = ref.read(locationBridgeProvider);
      locationBridge.registerMapController(_mapController);
      locationBridge.registerRideController(_rideController);

      // Set up callbacks with safety checks
      _rideController.onShowSnackBar = _showSnackBar;

      _rideController.onShowRoute = (destination) async {
        if (_mapController.mapController != null) {
          final success = await _mapController.showRouteToLocation(destination);
          if (!success) {
            _showSnackBar('Failed to get route.');
          }
        } else {
          print("Map controller not ready for routing");
        }
      };

      _rideController.onClearRoute = () {
        if (_mapController.mapController != null) {
          _mapController.clearRoute();
        }
      };

      _rideController.onClearMarkers = () {
        if (_mapController.mapController != null) {
          _mapController.clearPassengerMarkers();
        }
      };

      // Initialize the ride controller
      _rideController.initialize();
      _controllersInitialized = true;
    }
  }

  void _showRideHistory() {
    setState(() {
      _showProfileScreen = false;
      _showSettingsScreen = false;
      _showRideHistoryScreen = true;
      _showEarningsScreen = false;
    });
  }

  void _showEarnings() {
    setState(() {
      _showProfileScreen = false;
      _showSettingsScreen = false;
      _showRideHistoryScreen = false;
      _showEarningsScreen = true;
    });
  }

  void _showHome() {
    setState(() {
      _showProfileScreen = false;
      _showSettingsScreen = false;
      _showRideHistoryScreen = false;
      _showEarningsScreen = false;
    });
  }

  Future<void> _checkPermissions() async {
    await PermissionService.requestLocationPermission(context);
    final location = await PermissionService.getCurrentLocation();
    if (location != null) {
      final driverLocation = LatLng(location.latitude, location.longitude);

      LocationBridge().updateLocation(driverLocation);

      _getAddressFromLatLng(driverLocation);

      if (_mapController.mapController != null) {
        _mapController.moveCameraToLocation(driverLocation);
      }
    }
  }

  Future<void> _getAddressFromLatLng(LatLng location) async {
    if (_isLoadingAddress) return; // Prevent multiple simultaneous calls

    setState(() {
      _isLoadingAddress = true;
    });

    try {
      final address = await _mapController.getAddressFromLocation(location);

      if (mounted) {
        setState(() {
          _locationName = address;
        });
      }
    } catch (e) {
      print('[2025-06-03 18:53:11] [Lilydebug] Error getting address: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAddress = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      _showSnackBar("Error signing out: $e");
    }
  }

  void _showProfile() {
    setState(() {
      _showProfileScreen = true;
      _showSettingsScreen = false;
    });
  }

  void _showSettings() {
    setState(() {
      _showSettingsScreen = true;
      _showProfileScreen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show specific screens when active
    if (_showProfileScreen) {
      return ProfileScreen(onBackPressed: _showHome);
    } else if (_showSettingsScreen) {
      return SettingsScreen(onBackPressed: _showHome);
    } else if (_showRideHistoryScreen) {
      return RideHistoryScreen(onBackPressed: _showHome);
    } else if (_showEarningsScreen) {
      return DriverEarningsScreen(onBackPressed: _showHome);
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(
        onProfileTap: _showProfile,
        onSettingsTap: _showSettings,
        onRideHistoryTap: _showRideHistory,
        onEarningsTap: _showEarnings,
      ),
      extendBodyBehindAppBar: true,
      body: AnimatedBuilder(
        animation: _rideController,
        builder: (context, child) {
          return Stack(
            children: [
              // Map (full screen)
              MaplibreMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _rideController.driverLocation ?? LatLng(0, 0),
                  zoom: _rideController.driverLocation != null ? 15.0 : 2.0,
                ),
                styleString: "https://api.maptiler.com/maps/dataviz-dark/style.json?key=U7fg3KGqTysSBCZJpaNH",
                myLocationEnabled: true,
              ),

              // Top Status Bar
              _buildTopStatusBar(),

              // Auto-recalculate toggle button - only when in a ride
              if (_rideController.isInRide)
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).size.height / 2 - 80,
                  child: FloatingActionButton(
                    onPressed: () {
                      setState(() {
                        _mapController.autoRecalculateEnabled = !_mapController.autoRecalculateEnabled;
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              _mapController.autoRecalculateEnabled
                                  ? 'Auto-recalculate enabled'
                                  : 'Auto-recalculate disabled'
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    backgroundColor: _mapController.autoRecalculateEnabled ? Colors.green : Colors.grey,
                    mini: true,
                    heroTag: "toggleAutoRecalculate",
                    tooltip: "Toggle auto-recalculate",
                    child: Icon(
                      _mapController.autoRecalculateEnabled ? Icons.sync : Icons.sync_disabled,
                      color: Colors.white,
                    ),
                  ),
                ),

              // Manual recalculate button - only when in a ride
              if (_rideController.isInRide)
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).size.height / 2 - 28,
                  child: FloatingActionButton(
                    onPressed: () {
                      if (_mapController.mapController != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Recalculating route...'),
                            duration: Duration(seconds: 2),
                          ),
                        );

                        _mapController.mapController!.requestMyLocationLatLng().then((location) {
                          if (location != null) {
                            _recalculateRouteFromLocation(location);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Cannot get current position'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Cannot recalculate: Map not ready'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                    backgroundColor: Color(0xFFFF4B6C),
                    elevation: 4,
                    heroTag: "recalculateRoute",
                    tooltip: "Recalculate route",
                    child: Icon(Icons.refresh, color: Colors.white),
                  ),
                ),

              // Bottom Control Panel
              _buildBottomControlPanel(),

              // Passenger Requests Overlay
              if (_rideController.showRequestsList &&
                  _rideController.nearbyRequests.isNotEmpty &&
                  !_rideController.isInRide)
                _buildPassengerRequestsOverlay(),

              // Request Preview Overlay
              if (_showRequestPreview && _previewedRequest != null)
                _buildRequestDestinationPreview(),

              // Loading indicator
              if (_rideController.isLoading)
                _buildLoadingOverlay(),
            ],
          );
        },
      ),
    );
  }

// Helper method for recalculating route
  void _recalculateRouteFromLocation(LatLng location) {
    if (_rideController.currentRide != null) {
      // Determine destination based on ride state
      LatLng destination;
      if (_rideController.rideState == RideState.enrouteToPickup) {
        destination = LatLng(
            _rideController.currentRide!.pickupLat,
            _rideController.currentRide!.pickupLng
        );
      } else {
        destination = LatLng(
            _rideController.currentRide!.destinationLat,
            _rideController.currentRide!.destinationLng
        );
      }

      // Clear existing route
      _mapController.clearRoute();

      // Calculate new route
      _mapController.showRouteToLocation(destination).then((success) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Route recalculated successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to recalculate route'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }
  Widget _buildTopStatusBar() {
    return Positioned(
      top: MediaQuery.of(context).viewPadding.top,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.menu, color: Colors.white, size: 18),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  },
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.all(8),
                ),
              ),
              SizedBox(width: 12),
              CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(_rideController.driverImage),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rideController.driverName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _rideController.isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _rideController.isOnline ? _rideController.getRideStateText() : "Offline",
                            style: TextStyle(
                              color: _rideController.isOnline ? Colors.green : Colors.grey,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on, color: Colors.amber, size: 14),
                    SizedBox(width: 4),
                    Text(
                      '${_rideController.totalEarningsToday}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.logout, color: Colors.white, size: 16),
                  onPressed: _logout,
                  tooltip: 'Logout',
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControlPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, -4),
            ),
          ],
          border: Border.all(color: Colors.grey[850]!, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Minimize toggle bar
            GestureDetector(
              onTap: () {
                setState(() {
                  _isBottomPanelMinimized = !_isBottomPanelMinimized;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Color(0xFF222222),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // Show minimized or full panel based on state
            if (!_isBottomPanelMinimized)
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_rideController.isInRide)
                      _buildOfflineControls()
                    else
                      _buildRideControls(),

                    // Timestamp footer
                    SizedBox(height: 8),
                    Divider(color: Colors.grey[850], height: 1),
                    SizedBox(height: 8),
                    _buildFooterTimestamp(),
                  ],
                ),
              )
            else
              _buildMinimizedControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterTimestamp() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(Icons.access_time, size: 9, color: Colors.grey[600]),
        SizedBox(width: 4),
        Text(
          "Last updated",
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineControls() {
    return Column(
      children: [
        // Location Display
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [Color(0xFF2A2A2A), Color(0xFF222222)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF222222),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on,
                  color: Color(0xFFFF4B6C),
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Location',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 2),
                    _isLoadingAddress
                        ? Row(
                      children: [
                        SizedBox(
                          height: 12,
                          width: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            "Getting location...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                        : Text(
                      _locationName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF333333),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.my_location, color: Colors.white, size: 18),
                  onPressed: () {
                    if (_rideController.driverLocation != null && _mapController.mapController != null) {
                      _mapController.moveCameraToLocation(_rideController.driverLocation!);
                    }
                  },
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),

        // Online/Offline Toggle
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _rideController.toggleDriverStatus,
            icon: Icon(
              _rideController.isOnline ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 20,
            ),
            label: Text(
              _rideController.isOnline ? 'Go Offline' : 'Go Online',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _rideController.isOnline ? Colors.orange : Color(0xFFFF4B6C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              shadowColor: _rideController.isOnline
                  ? Colors.orange.withOpacity(0.4)
                  : Color(0xFFFF4B6C).withOpacity(0.4),
            ),
          ),
        ),

        // Status indicator when online + manual refresh button
        if (_rideController.isOnline)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _rideController.isLoadingRequests
                    ? SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : Icon(Icons.search, size: 14, color: Colors.grey[400]),
                SizedBox(width: 8),
                Text(
                  _rideController.isLoadingRequests ? "Finding requests..." : "Searching for ride requests",
                  style: TextStyle(
                    color: _rideController.isLoadingRequests ? Colors.white70 : Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
                SizedBox(width: 8),
                // Added manual refresh button
                GestureDetector(
                  onTap: _rideController.isLoadingRequests
                      ? null
                      : () async {
                    await _rideController.fetchNearbyRequests();
                    if (_rideController.nearbyRequests.isNotEmpty && _mapController.mapController != null) {
                      await _mapController.addPassengerMarkersToMap(_rideController.nearbyRequests);
                      _rideController.setShowRequestsList(true);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _rideController.isLoadingRequests ? Color(0xFF333333).withOpacity(0.5) : Color(0xFF333333),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.refresh,
                      size: 12,
                      color: _rideController.isLoadingRequests ? Colors.grey[600] : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Preview of top request when not showing full list
        if (_rideController.nearbyRequests.isNotEmpty && !_rideController.showRequestsList)
          _buildRequestPreview(),
      ],
    );
  }

  Widget _buildMinimizedControls() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Driver status indicator
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _rideController.isOnline ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 4),
              Text(
                _rideController.isOnline
                    ? (_rideController.isInRide ? _rideController.getRideStateText() : "Online")
                    : "Offline",
                style: TextStyle(
                  color: _rideController.isOnline ? Colors.white : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // Action buttons
          Row(
            children: [
              // Location button
              Container(
                decoration: BoxDecoration(
                  color: Color(0xFF333333),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.my_location, color: Colors.white, size: 16),
                  onPressed: () {
                    if (_rideController.driverLocation != null && _mapController.mapController != null) {
                      _mapController.moveCameraToLocation(_rideController.driverLocation!);
                    }
                  },
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.all(6),
                ),
              ),
              SizedBox(width: 8),

              // Toggle online/offline button (if not in ride)
              if (!_rideController.isInRide)
                Container(
                  decoration: BoxDecoration(
                    color: _rideController.isOnline ? Colors.orange : Color(0xFFFF4B6C),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                        _rideController.isOnline ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 16
                    ),
                    onPressed: _rideController.toggleDriverStatus,
                    constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.all(6),
                  ),
                ),

              // If in a ride, show arrive button when near destination
              if (_rideController.isInRide && _rideController.canArrive)
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFFF4B6C),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                        _rideController.rideState == RideState.enrouteToPickup
                            ? Icons.location_on
                            : Icons.flag,
                        color: Colors.white,
                        size: 16
                    ),
                    // Fixed method call to use the correct arrive methods
                    onPressed: () {
                      if (_rideController.canArrive) {
                        if (_rideController.rideState == RideState.enrouteToPickup) {
                          _rideController.arrivedAtPickup();
                        } else if (_rideController.rideState == RideState.enrouteToDestination) {
                          _rideController.arrivedAtDestination();
                        }
                      }
                    },
                    constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.all(6),
                  ),
                ),

              // Find requests button (if online and not in ride)
              if (_rideController.isOnline && !_rideController.isInRide)
                SizedBox(width: 8),
              if (_rideController.isOnline && !_rideController.isInRide)
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFF2A2A2A),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: _rideController.isLoadingRequests
                        ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Icon(Icons.refresh, color: Colors.white, size: 16),
                    onPressed: _rideController.isLoadingRequests
                        ? null
                        : () async {
                      await _rideController.fetchNearbyRequests();
                      if (_rideController.nearbyRequests.isNotEmpty && _mapController.mapController != null) {
                        await _mapController.addPassengerMarkersToMap(_rideController.nearbyRequests);
                      }
                      _rideController.setShowRequestsList(true);
                    },
                    constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.all(6),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestPreview() {
    final request = _rideController.nearbyRequests[0];

    return Column(
      children: [
        SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            _rideController.setShowRequestsList(true);
          },
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(0xFFFF4B6C).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_taxi,
                      color: Color(0xFFFF4B6C),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Available Requests',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Color(0xFF333333),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_rideController.nearbyRequests.length}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundImage: NetworkImage(request.passengerImage),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.passengerName,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 12),
                              SizedBox(width: 2),
                              Text(
                                '${request.passengerRating}',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '${request.distanceKm.toStringAsFixed(1)} km away',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xFF333333),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${request.fare} PKR',
                            style: TextStyle(
                              color: Color(0xFFFF4B6C),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 4),
                        SizedBox(
                          height: 28,
                          child: ElevatedButton(
                            onPressed: () => _rideController.acceptRequest(request),
                            child: Text(
                              'Accept',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFFFF4B6C),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getCurrentDestination() {
    if (_rideController.currentRide == null) return "";

    switch (_rideController.rideState) {
      case RideState.enrouteToPickup:
      case RideState.arrivedAtPickup:
      case RideState.waitingForConfirmation:
        return _rideController.currentRide!.pickupAddress;
      case RideState.enrouteToDestination:
      case RideState.arrivedAtDestination:
        return _rideController.currentRide!.destinationAddress;
      default:
        return "";
    }
  }

  IconData _getCurrentLocationIcon() {
    switch (_rideController.rideState) {
      case RideState.enrouteToPickup:
      case RideState.arrivedAtPickup:
      case RideState.waitingForConfirmation:
        return Icons.location_on;
      case RideState.enrouteToDestination:
      case RideState.arrivedAtDestination:
        return Icons.flag;
      default:
        return Icons.location_on;
    }
  }

  Color _getCurrentLocationIconColor() {
    switch (_rideController.rideState) {
      case RideState.enrouteToPickup:
      case RideState.arrivedAtPickup:
      case RideState.waitingForConfirmation:
        return Color(0xFFFF4B6C);
      case RideState.enrouteToDestination:
      case RideState.arrivedAtDestination:
        return Colors.green;
      default:
        return Color(0xFFFF4B6C);
    }
  }

  Widget _buildRideControls() {
    if (_rideController.currentRide == null) return Container();

    final request = _rideController.currentRide!;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _rideController.rideState == RideState.arrivedAtDestination
                  ? Colors.green.withOpacity(0.3)
                  : Colors.grey[850]!,
              width: 1,
            ),
            gradient: LinearGradient(
              colors: [Color(0xFF2A2A2A), Color(0xFF222222)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(request.passengerImage),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.passengerName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 12),
                            SizedBox(width: 2),
                            Text(
                              '${request.passengerRating}',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Color(0xFF333333),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _rideController.getRideStateText(),
                                  style: TextStyle(
                                    color: _getCurrentLocationIconColor(),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Color(0xFF333333),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                      border: Border.all(
                        color: Color(0xFFFF4B6C).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${request.fare} PKR',
                      style: TextStyle(
                        color: Color(0xFFFF4B6C),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Divider(color: Colors.grey[800], height: 1),
              SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getCurrentLocationIconColor().withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _getCurrentLocationIconColor().withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _getCurrentLocationIcon(),
                      color: _getCurrentLocationIconColor(),
                      size: 16,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _rideController.rideState == RideState.enrouteToPickup ||
                                  _rideController.rideState == RideState.arrivedAtPickup ||
                                  _rideController.rideState == RideState.waitingForConfirmation
                                  ? "Pickup Location"
                                  : "Destination",
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 6),
                            if (_rideController.canArrive)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'NEARBY',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          _getCurrentDestination(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (_mapController.currentTarget != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _mapController.getDistanceToTarget(),
                              style: TextStyle(
                                color: _rideController.canArrive ? Colors.green : Colors.grey[400],
                                fontSize: 11,
                                fontWeight: _rideController.canArrive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // Action Buttons based on ride state - INCLUDING WAITING FOR CONFIRMATION

        if (_rideController.rideState == RideState.enrouteToPickup)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _rideController.cancelRide,
                    icon: Icon(Icons.cancel_outlined, size: 18),
                    label: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_rideController.currentRide != null) {
                        context.pushNamed(
                          'chat',
                          pathParameters: {'rideId': _rideController.currentRide!.id},
                          queryParameters: {
                            'name': _rideController.currentRide!.passengerName,
                            'image': _rideController.currentRide!.passengerImage,
                          },
                        );
                        print(" Opening chat with ${_rideController.currentRide!.passengerName}");
                      }
                    },
                    icon: Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(
                      'Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF2A2A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _rideController.canArrive ? _rideController.arrivedAtPickup : null,
                    icon: Icon(
                      Icons.location_on,
                      size: 18,
                      color: _rideController.canArrive ? Colors.white : Colors.white54,
                    ),
                    label: Text(
                      'Arrived',
                      style: TextStyle(
                        color: _rideController.canArrive ? Colors.white : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rideController.canArrive ? Color(0xFFFF4B6C) : Colors.grey[600],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: _rideController.canArrive ? 4 : 0,
                      shadowColor: _rideController.canArrive ? Color(0xFFFF4B6C).withOpacity(0.4) : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          )
        else  if (_rideController.rideState == RideState.waitingForConfirmation)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _rideController.cancelRide,
                    icon: Icon(Icons.cancel_outlined, size: 18),
                    label: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_rideController.currentRide != null) {
                        context.pushNamed(
                          'chat',
                          pathParameters: {'rideId': _rideController.currentRide!.id},
                          queryParameters: {
                            'name': _rideController.currentRide!.passengerName,
                            'image': _rideController.currentRide!.passengerImage,
                          },
                        );
                        print(" Opening chat with ${_rideController.currentRide!.passengerName}");
                      }
                    },
                    icon: Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(
                      'Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF2A2A2A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        else if (_rideController.rideState == RideState.arrivedAtPickup)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _rideController.cancelRide,
                      icon: Icon(Icons.cancel_outlined, size: 18),
                      label: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (_rideController.currentRide != null) {
                          context.pushNamed(
                            'chat',
                            pathParameters: {'rideId': _rideController.currentRide!.id},
                            queryParameters: {
                              'name': _rideController.currentRide!.passengerName,
                              'image': _rideController.currentRide!.passengerImage,
                            },
                          );
                          print(" Opening chat with ${_rideController.currentRide!.passengerName}");
                        }
                      },
                      icon: Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(
                        'Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF2A2A2A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _rideController.confirmPickup,
                      icon: Icon(Icons.person_pin_circle, size: 18),
                      label: Text(
                        'Pickup',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 4,
                        shadowColor: Colors.green.withOpacity(0.4),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else if (_rideController.rideState == RideState.enrouteToDestination)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (_rideController.currentRide != null) {
                            context.pushNamed(
                              'chat',
                              pathParameters: {'rideId': _rideController.currentRide!.id},
                              queryParameters: {
                                'name': _rideController.currentRide!.passengerName,
                                'image': _rideController.currentRide!.passengerImage,
                              },
                            );
                            print("Opening chat with ${_rideController.currentRide!.passengerName}");
                          }
                        },
                        icon: Icon(Icons.chat_bubble_outline, size: 18),
                        label: Text(
                          'Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF2A2A2A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _rideController.canArrive ? _rideController.arrivedAtDestination : null,
                        icon: Icon(
                          Icons.flag,
                          size: 18,
                          color: _rideController.canArrive ? Colors.white : Colors.white54,
                        ),
                        label: Flexible(
                          child: Text(
                            'Arrived at Destination',
                            style: TextStyle(
                              color: _rideController.canArrive ? Colors.white : Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rideController.canArrive ? Color(0xFFFF4B6C) : Colors.grey[600],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: _rideController.canArrive ? 4 : 0,
                          shadowColor: _rideController.canArrive ? Color(0xFFFF4B6C).withOpacity(0.4) : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else if (_rideController.rideState == RideState.arrivedAtDestination)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_rideController.currentRide != null) {
                              context.pushNamed(
                                'chat',
                                pathParameters: {'rideId': _rideController.currentRide!.id},
                                queryParameters: {
                                  'name': _rideController.currentRide!.passengerName,
                                  'image': _rideController.currentRide!.passengerImage,
                                },
                              );
                              print(" Opening chat with ${_rideController.currentRide!.passengerName}");
                            }
                          },
                          icon: Icon(Icons.chat_bubble_outline, size: 18),
                          label: Text(
                            'Chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF2A2A2A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _rideController.completeRide,
                          icon: Icon(Icons.check_circle_outline, size: 18),
                          label: Text(
                            'Complete Ride',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 4,
                            shadowColor: Colors.green.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
      ],
    );
  }

  Widget _buildRequestDestinationPreview() {
    if (_previewedRequest == null) return Container();

    final request = _previewedRequest!;
    final pickupLatLng = LatLng(request.pickupLat, request.pickupLng);
    final destinationLatLng = LatLng(request.destinationLat, request.destinationLng);

    // Calculate trip distance if not available in the request
    double tripDistanceKm = request.distanceKm;
    if (request.additionalData != null &&
        request.additionalData!.containsKey('tripDistanceKm')) {
      tripDistanceKm = request.additionalData!['tripDistanceKm'];
    }

    // Auto-minimize bottom panel when showing preview
    if (!_isBottomPanelMinimized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _isBottomPanelMinimized = true;
        });
      });
    }

    return Positioned(
      bottom: _isBottomPanelMinimized ? 100 : 220,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, -4),
            ),
          ],
          border: Border.all(
            color: Color(0xFFFF4B6C).withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: Color(0xFFFF4B6C),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trip Details',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showRequestPreview = false;
                        _previewedRequest = null;
                        // Maximize bottom panel on close
                        _isBottomPanelMinimized = false;
                      });
                      // Clear destination preview
                      _mapController.clearDestinationPreview();
                      // Re-show requests list
                      _rideController.setShowRequestsList(true);
                    },
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Color(0xFF2A2A2A),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // Passenger info
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(request.passengerImage),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.passengerName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 12),
                            SizedBox(width: 2),
                            Text(
                              '${request.passengerRating}',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Color(0xFFFF4B6C).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${request.fare} PKR',
                      style: TextStyle(
                        color: Color(0xFFFF4B6C),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),
              Divider(color: Colors.grey[800], height: 1),
              SizedBox(height: 16),

              // Pickup location
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color(0xFFFF4B6C).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.my_location,
                      color: Color(0xFFFF4B6C),
                      size: 16,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pickup',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          request.pickupAddress,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${request.distanceKm.toStringAsFixed(1)} km away',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.flag,
                      color: Colors.green,
                      size: 16,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Destination',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          request.destinationAddress,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Trip distance: ${tripDistanceKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),
              Divider(color: Colors.grey[800], height: 1),
              SizedBox(height: 16),


              // Accept/Decline buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showRequestPreview = false;
                            _previewedRequest = null;
                            // Maximize bottom panel on decline
                            _isBottomPanelMinimized = false;
                          });
                          // Clear destination preview
                          _mapController.clearDestinationPreview();
                          // Re-show requests list
                          _rideController.setShowRequestsList(true);
                        },
                        icon: Icon(Icons.close, size: 18),
                        label: Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _mapController.clearDestinationPreview();
                          // Accept the request and close the preview
                          setState(() {
                            _showRequestPreview = false;
                          });

                          // Accept the request and proceed to pickup navigation
                          _rideController.acceptRequest(request);
                          // Keep panel minimized when accepting ride
                        },
                        icon: Icon(Icons.check, size: 18),
                        label: Text(
                          'Accept',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF4B6C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                          shadowColor: Color(0xFFFF4B6C).withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerRequestsOverlay() {
    if (!_isBottomPanelMinimized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _isBottomPanelMinimized = true;
        });
      });
    }

    return Positioned(
      bottom: _isBottomPanelMinimized ? 100 : 220,
      left: 16,
      right: 16,
      child: Container(
        constraints: BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: Offset(0, -4),
            ),
          ],
          border: Border.all(
            color: Color(0xFFFF4B6C).withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF222222)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_taxi,
                    color: Color(0xFFFF4B6C),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nearby Requests',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_rideController.nearbyRequests.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _rideController.setShowRequestsList(false);
                      // Maximize bottom panel when closing requests list
                      setState(() {
                        _isBottomPanelMinimized = false;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Color(0xFF2A2A2A),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: 16),
                shrinkWrap: true,
                itemCount: _rideController.nearbyRequests.length,
                separatorBuilder: (context, index) => Divider(
                  color: Colors.grey[800],
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final request = _rideController.nearbyRequests[index];
                  return InkWell(
                    onTap: () {
                      _mapController.clearDestinationPreview();
                      // Show preview instead of accepting immediately
                      setState(() {
                        _showRequestPreview = true;
                        _previewedRequest = request;
                      });

                      // Show the route preview on map
                      if (_mapController.mapController != null) {
                        final pickupLatLng = LatLng(request.pickupLat, request.pickupLng);
                        final destinationLatLng = LatLng(request.destinationLat, request.destinationLng);
                        _mapController.showDestinationPreview(pickupLatLng, destinationLatLng);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: NetworkImage(request.passengerImage),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        request.passengerName,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(Icons.star, color: Colors.amber, size: 12),
                                    Text(
                                      ' ${request.passengerRating.toStringAsFixed(1)}',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      color: Color(0xFFFF4B6C).withOpacity(0.7),
                                      size: 10,
                                    ),
                                    SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '${request.distanceKm.toStringAsFixed(1)} km • ${request.pickupAddress}',
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(0xFFFF4B6C).withOpacity(0.8),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFFFF4B6C).withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '${request.fare} PKR',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFF222222),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _rideController.nearbyRequests.isNotEmpty
                          ? () {
                        // Show preview for the top request instead of accepting immediately
                        setState(() {
                          _showRequestPreview = true;
                          _previewedRequest = _rideController.nearbyRequests[0];
                        });

                        // Show the route preview on map
                        if (_mapController.mapController != null) {
                          final request = _rideController.nearbyRequests[0];
                          final pickupLatLng = LatLng(request.pickupLat, request.pickupLng);
                          final destinationLatLng = LatLng(request.destinationLat, request.destinationLng);
                          _mapController.showDestinationPreview(pickupLatLng, destinationLatLng);
                        }
                      }
                          : null,
                      icon: Icon(Icons.visibility, size: 18), // Changed from check_circle_outline to visibility
                      label: Text(
                        'Preview Top Request', // Changed from 'Accept Top Request'
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFF4B6C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                        shadowColor: Color(0xFFFF4B6C).withOpacity(0.4),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 9,
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: 2),
                      Text(
                        "Last updated just now",
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Color(0xFFFF4B6C),
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 16),
              Text(
                "Loading...",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  void dispose() {
    // Cancel all timers
    _autoFindTimer?.cancel();
    _locationSyncTimer?.cancel();

    // Clean up controllers if we're responsible for them
    if (_controllersInitialized) {
      _rideController.dispose();
      _mapController.dispose();
    }

    // Clean up services
    if (_isLocationServiceInitialized) {
      _locationService.dispose();
    }

    if (_isSosInitialized) {
      _sosService.stopMonitoring();
    }

    super.dispose();
  }
}