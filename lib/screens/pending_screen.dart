import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({Key? key}) : super(key: key);

  @override
  _PendingScreenState createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  Map<String, dynamic>? _driverData;
  Map<String, dynamic>? _carData;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    // Set up a listener to automatically redirect when status changes
    _setupStatusListener();
  }

  void _setupStatusListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    // Listen to changes in the taxi document
    _firestore.collection('Taxis').doc(user.uid).snapshots().listen((docSnapshot) {
      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>?;
        if (data != null) {
          final status = data['status'] as String?;

          // If status changed to approved, available, online, or offline, go to home screen
          if (status == 'approved' || status == 'available' ||
              status == 'online' || status == 'offline') {
            // Navigate to home screen
            context.go('/home');
          }
        }
      }
    });
  }

  Future<void> _loadDriverData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        // Handle not logged in case
        context.go('/login');
        return;
      }

      // Get all data from the Taxis collection
      final taxiDoc = await _firestore.collection('Taxis').doc(user.uid).get();
      if (taxiDoc.exists) {
        final taxiData = taxiDoc.data() as Map<String, dynamic>?;
        if (taxiData != null) {
          setState(() {
            _driverData = taxiData;
            _carData = taxiData['car'] as Map<String, dynamic>?;
          });

          // Check if already approved, redirect to home
          final status = taxiData['status'] as String?;
          if (status == 'approved' || status == 'available' ||
              status == 'online' || status == 'offline') {
            // Already approved, go to home screen
            context.go('/home');
            return;
          }
        } else {
          // No taxi data, go to registration
          context.go('/driver-registration');
        }
      } else {
        // No taxi document, go to registration
        context.go('/driver-registration');
      }
    } catch (e) {
      print('Error loading driver data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4B6C)),
        ),
      );
    }

    final String driverName = _driverData?['driverName'] ?? 'Driver';
    final String driverImage = _driverData?['driverImage'] ?? "https://randomuser.me/api/portraits/women/67.jpg";
    final String registrationStatus = _driverData?['status'] ?? 'pending';
    final String carModel = _driverData?['vehicleModel'] ?? _carData?['model'] ?? 'Unknown';
    final String vehicleType = _driverData?['vehicleType'] ?? 'Sedan';
    final String vehiclePlate = _driverData?['vehiclePlate'] ?? _carData?['licensePlate'] ?? '';
    final String rank = _driverData?['rank'] ?? 'New';
    final double rating = (_driverData?['rating'] ?? 0.0).toDouble();
    final int totalRides = (_driverData?['totalRides'] ?? 0) as int;

    return Scaffold(
      appBar: AppBar(
        title: Text('Application Status'),
        backgroundColor: Color(0xFF222222),
        actions: [
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: () async {
              await _auth.signOut();
              context.go('/login');
            },
          ),
        ],
      ),
      body: Container(
        color: Color(0xFF111111),
        child: Column(
          children: [
            // Driver Profile Card
            Container(
              width: double.infinity,
              margin: EdgeInsets.all(16),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFF222222),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Driver image
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: NetworkImage(driverImage),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '$vehicleType · $carModel',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          vehiclePlate,
                          style: TextStyle(color: Colors.white70),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            _buildInfoChip(
                              icon: Icons.star,
                              label: rating.toStringAsFixed(1),
                              color: Colors.amber,
                            ),
                            SizedBox(width: 8),
                            _buildInfoChip(
                              icon: Icons.military_tech,
                              label: rank,
                              color: _getRankColor(rank),
                            ),
                            SizedBox(width: 8),
                            _buildInfoChip(
                              icon: Icons.directions_car,
                              label: '$totalRides rides',
                              color: Colors.blue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Status Card
            Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(horizontal: 16),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFF222222),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getStatusIcon(registrationStatus),
                        color: _getStatusColor(registrationStatus),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Status: ${_getStatusText(registrationStatus)}',
                        style: TextStyle(
                          color: _getStatusColor(registrationStatus),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Status-specific content
            if (registrationStatus == 'pending')
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hourglass_bottom,
                          color: Colors.amber,
                          size: 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Your registration is pending approval',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'We\'re reviewing your information. This usually takes 24-48 hours.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (registrationStatus == 'rejected')
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Your registration was not approved',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Unfortunately, we couldn\'t approve your registration at this time. Please contact support for more information.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF4B6C),
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: () {
                            // Contact support
                          },
                          child: Text('Contact Support'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRankColor(String rank) {
    switch (rank.toLowerCase()) {
      case 'gold':
        return Colors.amber;
      case 'silver':
        return Colors.grey.shade300;
      case 'bronze':
        return Colors.brown.shade300;
      case 'platinum':
        return Colors.blue.shade200;
      case 'diamond':
        return Colors.cyan;
      default:
        return Colors.green;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
      case 'available':
        return Icons.check_circle;
      case 'online':
        return Icons.visibility;
      case 'offline':
        return Icons.visibility_off;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
      default:
        return Icons.hourglass_empty;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
      case 'available':
        return Colors.green;
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.amber;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'available':
        return 'Available';
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
      case 'rejected':
        return 'Rejected';
      case 'pending':
      default:
        return 'Pending Approval';
    }
  }
}