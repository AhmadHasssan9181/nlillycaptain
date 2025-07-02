import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lilycaptain/passenger_model.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

// Local imports
import '../controller/map_controller.dart';
import '../controller/ride_controller.dart';
import '../services/permission_service.dart';
import '../widgets/app_drawer.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../providers/emergency_sos_provider.dart';
import '../services/emergency_sos_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/ride_history_screen.dart';  // Add this import
import '../screens/earnings_screen.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Controllers
  late final MapController _mapController;
  late final RideController _rideController;

  // Track initialization to prevent multiple initializations
  bool _controllersInitialized = false;

  bool _showRideHistoryScreen = false;  // Add this
  bool _showEarningsScreen = false;


  // UI State
  String _locationName = "Loading location...";
  bool _isLoadingAddress = false;
  bool _showProfileScreen = false;
  bool _showSettingsScreen = false;

  bool _showRequestPreview = false;
  PassengerRequest? _previewedRequest;

  // Location management
  bool _isUpdatingLocation = false; // Prevent circular updates

  // Add this with your other variables
  late EmergencySosService _sosService;
  bool _isSosInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeEmergencySOS();
    _checkPermissions();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }
// In your _initializeEmergencySOS() method in HomeScreen:
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

      // Set up callbacks with safety checks
      _rideController.onShowSnackBar = _showSnackBar;

      // Only RideController manages location updates to prevent loops
      _rideController.onShowRoute = (destination) async {
        if (_mapController.mapController != null) {
          final success = await _mapController.showRouteToLocation(destination);
          if (!success) {
            _showSnackBar('Failed to get route.');
          }
        } else {
          print("[2025-06-03 18:53:11] [Lilydebug] Map controller not ready for routing");
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

  // Centralized location update method to prevent circular calls
  void _updateLocationInBothControllers(LatLng location) {
    if (_isUpdatingLocation) return; // Prevent circular calls

    _isUpdatingLocation = true;

    // Update both controllers directly without triggering callbacks
    _mapController.updateDriverLocation(location);
    _rideController.setLocation(location);

    // Update address
    _getAddressFromLatLng(location);

    _isUpdatingLocation = false;
  }

  Future<void> _checkPermissions() async {
    await PermissionService.requestLocationPermission(context);
    final location = await PermissionService.getCurrentLocation();
    if (location != null) {
      final driverLocation = LatLng(location.latitude, location.longitude);

      // Use centralized update method
      _updateLocationInBothControllers(driverLocation);

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

  void _onMapCreated(MaplibreMapController controller) {
    _mapController.setMapController(controller);
    if (_rideController.driverLocation != null) {
      _mapController.moveCameraToLocation(_rideController.driverLocation!);
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
  void dispose() {
    // Set flag first to prevent callbacks from accessing disposed controllers
    _controllersInitialized = false;
    _rideController.dispose();
    _mapController.dispose();

    // Stop SOS monitoring when leaving the screen
    if (_isSosInitialized) {
      _sosService.stopMonitoring();
    }

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    // Show Profile screen if active
    if (_showProfileScreen) {
      return ProfileScreen(onBackPressed: _showHome);
    }

    // Show Settings screen if active
    if (_showSettingsScreen) {
      return SettingsScreen(onBackPressed: _showHome);
    }

    // Show Ride History screen if active
    if (_showRideHistoryScreen) {
      return RideHistoryScreen(onBackPressed: _showHome);
    }

    // Show Earnings screen if active
    if (_showEarningsScreen) {
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

              // Bottom Control Panel
              _buildBottomControlPanel(),

              // Passenger Requests Overlay
              if (_rideController.showRequestsList &&
                  _rideController.nearbyRequests.isNotEmpty &&
                  !_rideController.isInRide)
                _buildPassengerRequestsOverlay(),

              // Request Preview Overlay (ADD THIS)
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
          border: Border.all(
            color: Colors.grey[850]!,
            width: 1,
          ),
        ),
        child: Padding(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 9,
                    color: Colors.grey[600],
                  ),
                  SizedBox(width: 4),
                  Text(
                    "2025-06-03 18:53:11",
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 12),
                  Icon(
                    Icons.person,
                    size: 9,
                    color: Colors.grey[600],
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Lilydebug",
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

        // Find Requests Button
        if (_rideController.isOnline) ...[
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _rideController.isLoadingRequests
                  ? null
                  : () async {
                // Add passenger markers to map when fetching requests
                await _rideController.fetchNearbyRequests();
                if (_rideController.nearbyRequests.isNotEmpty && _mapController.mapController != null) {
                  await _mapController.addPassengerMarkersToMap(_rideController.nearbyRequests);
                }
                _rideController.setShowRequestsList(true);
              },
              icon: _rideController.isLoadingRequests
                  ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : Icon(Icons.refresh, color: Colors.white, size: 18),
              label: Text(
                _rideController.isLoadingRequests ? 'Finding...' : 'Find Requests',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF2A2A2A),
                disabledBackgroundColor: Color(0xFF2A2A2A).withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),

          // Preview of top request when not showing full list
          if (_rideController.nearbyRequests.isNotEmpty && !_rideController.showRequestsList)
            _buildRequestPreview(),
        ],
      ],
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

  // Helper methods for the ride UI
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
    final String currentTimestamp = "2025-06-03 18:53:11";
    final String currentUserLogin = "Lilydebug";

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
                        print("[$currentTimestamp] [$currentUserLogin] Opening chat with ${_rideController.currentRide!.passengerName}");
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
                         print("[$currentTimestamp] [$currentUserLogin] Opening chat with ${_rideController.currentRide!.passengerName}");
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
                          print("[$currentTimestamp] [$currentUserLogin] Opening chat with ${_rideController.currentRide!.passengerName}");
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
                            print("[$currentTimestamp] [$currentUserLogin] Opening chat with ${_rideController.currentRide!.passengerName}");
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
                              print("[$currentTimestamp] [$currentUserLogin] Opening chat with ${_rideController.currentRide!.passengerName}");
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

    return Positioned(
      bottom: 220,
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
                      });
                      // Clear destination preview
                      if (_mapController.mapController != null) {
                        _mapController.clearDestinationPreview();
                      }
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

              // Destination location (THIS IS THE MISSING INFORMATION)
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
                          });
                          // Clear destination preview
                          if (_mapController.mapController != null) {
                            _mapController.clearDestinationPreview();
                          }
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
                          // Accept the request and close the preview
                          setState(() {
                            _showRequestPreview = false;
                          });

                          // Accept the request and proceed to pickup navigation
                          _rideController.acceptRequest(request);
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
    return Positioned(
      bottom: 220,
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
              SizedBox(height: 4),
              Text(
                "2025-06-03 18:53:11",
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}