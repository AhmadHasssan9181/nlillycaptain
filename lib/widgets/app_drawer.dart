import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class AppDrawer extends StatefulWidget {
  final Function onProfileTap;
  final Function onSettingsTap;
  final Function onRideHistoryTap;
  final Function onEarningsTap;

  const AppDrawer({
    Key? key,
    required this.onProfileTap,
    required this.onSettingsTap,
    required this.onRideHistoryTap,
    required this.onEarningsTap,
  }) : super(key: key);

  @override
  _AppDrawerState createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _driverName = "Loading...";
  String _driverImage = "https://randomuser.me/api/portraits/women/67.jpg";
  String _vehicleType = "Sedan";
  String _rank = "New";
  double _rating = 0.0;
  int _totalRides = 0;
  int _earnings = 0;
  bool _isLoading = true;

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
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _driverName = data['driverName'] ?? "Driver";
          _driverImage = data['driverImage'] ?? "https://randomuser.me/api/portraits/women/67.jpg";
          _vehicleType = data['vehicleType'] ?? "Sedan";
          _rank = data['rank'] ?? "New";
          _rating = (data['rating'] ?? 0.0).toDouble();
          _totalRides = (data['totalRides'] ?? 0) as int;
          _earnings = (data['earnings'] ?? 0) as int;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading drawer driver data: $e');
    }
  }

  Widget _buildRankIndicator(String rank) {
    Color color;
    IconData icon;

    switch (rank.toLowerCase()) {
      case 'gold':
        color = Colors.amber;
        icon = Icons.workspace_premium;
        break;
      case 'silver':
        color = Colors.grey.shade300;
        icon = Icons.military_tech;
        break;
      case 'bronze':
        color = Colors.brown.shade300;
        icon = Icons.shield;
        break;
      case 'platinum':
        color = Colors.blue.shade200;
        icon = Icons.diamond;
        break;
      case 'diamond':
        color = Colors.cyan;
        icon = Icons.stars;
        break;
      default:
        color = Colors.green;
        icon = Icons.auto_awesome;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        SizedBox(width: 4),
        Text(
          rank,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Color(0xFF111111),
      child: Column(
        children: [
          // Header with driver info
          Container(
            padding: EdgeInsets.fromLTRB(16, 60, 16, 16),
            decoration: BoxDecoration(
              color: Color(0xFF1A1A1A),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                )
              ],
            ),
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(color: Color(0xFFFF4B6C)),
            )
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFF2A2A2A),
                      backgroundImage: NetworkImage(_driverImage),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _driverName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Text(
                            _vehicleType,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 14),
                              SizedBox(width: 4),
                              Text(
                                _rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 12),
                              _buildRankIndicator(_rank),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        value: _totalRides.toString(),
                        label: "Total Rides",
                        icon: Icons.directions_car,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _statCard(
                        value: _earnings.toString(),
                        label: "Earnings (PKR)",
                        icon: Icons.account_balance_wallet,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Menu items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  title: 'Home',
                  icon: Icons.home,
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                  },
                ),
                _buildMenuItem(
                  title: 'My Profile',
                  icon: Icons.person,
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    widget.onProfileTap();
                  },
                ),
                _buildMenuItem(
                  title: 'Ride History',
                  icon: Icons.history,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onRideHistoryTap();
                  },
                ),
                _buildMenuItem(
                  title: 'Earnings',
                  icon: Icons.account_balance_wallet,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onEarningsTap();
                  },
                ),
                _buildMenuItem(
                  title: 'Settings',
                  icon: Icons.settings,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onSettingsTap();
                  },
                ),
                Divider(color: Colors.grey[850]),
                _buildMenuItem(
                  title: 'Help & Support',
                  icon: Icons.help,
                  onTap: () {
                    Navigator.pop(context);
                    // Navigate to help
                  },
                ),
                _buildMenuItem(
                  title: 'Logout',
                  icon: Icons.logout,
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseAuth.instance.signOut();
                    context.go('/login');
                  },
                ),
              ],
            ),
          ),
          // Footer with version info
          Container(
            padding: EdgeInsets.all(16),
            color: Color(0xFF1A1A1A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'v1.0.0',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                Text(
                  '2025-07-02 21:51:43',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required String title,
    required IconData icon,
    required Function onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Color(0xFFFF4B6C)),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      onTap: () => onTap(),
    );
  }

  Widget _statCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 10,
                ),
              ),
              SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 10,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}