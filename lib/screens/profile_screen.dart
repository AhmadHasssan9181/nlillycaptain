import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBackPressed;

  const ProfileScreen({Key? key, this.onBackPressed}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  bool _isLoading = true;
  Map<String, dynamic>? _driverData;
  Map<String, dynamic>? _carData;
  File? _newProfileImage;

  // Current timestamp and user login info for logging
  final String _currentTimestamp = "2025-06-01 18:20:35";
  final String _currentUserLogin = "Lilydebug";

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  Future<void> _loadDriverData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('Taxis').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          setState(() {
            _driverData = data;
            _carData = data['car'] as Map<String, dynamic>?;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading driver data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 70,
    );

    if (image != null) {
      setState(() {
        _newProfileImage = File(image.path);
      });

      // Upload immediately
      _uploadProfileImage();
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_newProfileImage == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final ref = _storage.ref().child('driver_profile_images/${user.uid}.jpg');
      final uploadTask = ref.putFile(_newProfileImage!);
      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update profile image URL in Firestore
      await _firestore.collection('Taxis').doc(user.uid).update({
        'driverImage': downloadUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
        'currentTimestamp': _currentTimestamp,
        'currentUserLogin': _currentUserLogin,
      });

      // Refresh driver data
      _loadDriverData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile image updated successfully')),
      );
    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile image')),
      );
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
        appBar: AppBar(
          title: Text('My Profile'),
          backgroundColor: Color(0xFF222222),
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4B6C)),
        ),
      );
    }

    final String driverName = _driverData?['driverName'] ?? 'Driver';
    final String driverImage = _driverData?['driverImage'] ?? "https://randomuser.me/api/portraits/women/67.jpg";
    final String phoneNumber = _driverData?['phoneNumber'] ?? '';
    final String cnic = _driverData?['cnic'] ?? '';
    final String driverLicense = _driverData?['driverLicense'] ?? '';
    final String city = _driverData?['city'] ?? '';
    final String vehicleType = _driverData?['vehicleType'] ?? 'Sedan';
    final String vehicleModel = _driverData?['vehicleModel'] ?? _carData?['model'] ?? '';
    final String vehiclePlate = _driverData?['vehiclePlate'] ?? _carData?['licensePlate'] ?? '';
    final String rank = _driverData?['rank'] ?? 'New';
    final double rating = (_driverData?['rating'] ?? 0.0).toDouble();
    final int totalRides = (_driverData?['totalRides'] ?? 0) as int;
    final int earnings = (_driverData?['earnings'] ?? 0) as int;

    return Scaffold(
      backgroundColor: Color(0xFF111111),
      appBar: AppBar(
        title: Text('My Profile'),
        backgroundColor: Color(0xFF222222),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Color(0xFF222222),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: _newProfileImage != null
                              ? FileImage(_newProfileImage!) as ImageProvider
                              : NetworkImage(driverImage),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Color(0xFFFF4B6C),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    driverName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 18,
                      ),
                      SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 16),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getRankColor(rank).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getRankColor(rank), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getRankIcon(rank), color: _getRankColor(rank), size: 14),
                            SizedBox(width: 4),
                            Text(
                              rank,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  // Statistics row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem(
                        value: totalRides.toString(),
                        label: 'Rides',
                        icon: Icons.directions_car,
                        color: Colors.blue,
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey[800],
                      ),
                      _statItem(
                        value: earnings.toString(),
                        label: 'Earnings (PKR)',
                        icon: Icons.monetization_on,
                        color: Colors.green,
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey[800],
                      ),
                      _statItem(
                        value: city,
                        label: 'City',
                        icon: Icons.location_city,
                        color: Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // Driver Information
            _sectionTitle('Driver Information'),
            _infoItem('Full Name', driverName, Icons.person),
            _infoItem('Phone Number', phoneNumber, Icons.phone),
            _infoItem('CNIC', _formatCNIC(cnic), Icons.credit_card),
            _infoItem('Driver License', driverLicense, Icons.badge),
            _infoItem('City', city, Icons.location_city),

            SizedBox(height: 20),

            // Vehicle Information
            _sectionTitle('Vehicle Information'),
            _infoItem('Vehicle Type', vehicleType, Icons.local_taxi),
            _infoItem('Vehicle Model', vehicleModel, Icons.directions_car),
            _infoItem('License Plate', vehiclePlate, Icons.featured_play_list),
            if (_carData != null) ...[
              _infoItem('Color', _carData!['color'] ?? '', Icons.color_lens),
              _infoItem('Engine Power', '${_carData!['enginePowerCC'] ?? ''} CC', Icons.speed),
              _infoItem('Seating Capacity', '${_carData!['seatingCapacity'] ?? ''} seats', Icons.event_seat),
            ],

            SizedBox(height: 20),

            // Account Info
            _sectionTitle('Account Information'),
            _infoItem('Email', _auth.currentUser?.email ?? '', Icons.email),
            _infoItem('Account Created', _formatTimestamp(_driverData?['registrationDate']), Icons.calendar_today),
            _infoItem('Last Online', _formatTimestamp(_driverData?['lastUpdated']), Icons.access_time),
            _infoItem('Current Session', _currentTimestamp, Icons.access_time),

            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _statItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      width: double.infinity,
      color: Color(0xFF1A1A1A),
      child: Text(
        title,
        style: TextStyle(
          color: Color(0xFFFF4B6C),
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[850]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.grey[400],
            size: 20,
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : "Not specified",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCNIC(String cnic) {
    if (cnic.length != 13) return cnic;
    return '${cnic.substring(0, 5)}-${cnic.substring(5, 12)}-${cnic.substring(12)}';
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "Not available";

    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)} ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
      }
    } catch (e) {
      print('Error formatting timestamp: $e');
    }

    return "Not available";
  }

  String _twoDigits(int n) {
    if (n >= 10) return "$n";
    return "0$n";
  }

  IconData _getRankIcon(String rank) {
    switch (rank.toLowerCase()) {
      case 'gold':
        return Icons.workspace_premium;
      case 'silver':
        return Icons.military_tech;
      case 'bronze':
        return Icons.shield;
      case 'platinum':
        return Icons.diamond;
      case 'diamond':
        return Icons.stars;
      default:
        return Icons.auto_awesome;
    }
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
}