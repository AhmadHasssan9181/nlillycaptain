import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'dart:math';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onBackPressed;

  const SettingsScreen({Key? key, this.onBackPressed}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _notificationsEnabled = true;
  bool _locationTrackingEnabled = true;
  bool _darkModeEnabled = true;
  String _language = 'English';
  double _arrivalRadius = 50.0;
  bool _autoAcceptRequests = false;
  bool _showEarningsOnMap = true;

  // Developer mode options
  bool _showCnicGenerator = false;
  int _devModeClickCount = 0;

  // Current timestamp and user login info for logging
  final String _currentTimestamp = "2025-07-02 22:48:53";
  final String _currentUserLogin = "lilycaptain";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('Taxis').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data['settings'] != null) {
          final settings = data['settings'] as Map<String, dynamic>;
          setState(() {
            _notificationsEnabled = settings['notificationsEnabled'] ?? true;
            _locationTrackingEnabled = settings['locationTrackingEnabled'] ?? true;
            _darkModeEnabled = settings['darkModeEnabled'] ?? true;
            _language = settings['language'] ?? 'English';
            _arrivalRadius = (settings['arrivalRadius'] ?? 50.0).toDouble();
            _autoAcceptRequests = settings['autoAcceptRequests'] ?? false;
            _showEarningsOnMap = settings['showEarningsOnMap'] ?? true;
          });
        }
      }
    } catch (e) {
      print('Error loading settings: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Update locally
      setState(() {
        switch (key) {
          case 'notificationsEnabled':
            _notificationsEnabled = value as bool;
            break;
          case 'locationTrackingEnabled':
            _locationTrackingEnabled = value as bool;
            break;
          case 'darkModeEnabled':
            _darkModeEnabled = value as bool;
            break;
          case 'language':
            _language = value as String;
            break;
          case 'arrivalRadius':
            _arrivalRadius = value as double;
            break;
          case 'autoAcceptRequests':
            _autoAcceptRequests = value as bool;
            break;
          case 'showEarningsOnMap':
            _showEarningsOnMap = value as bool;
            break;
        }
      });

      // Save to Firestore
      await _firestore.collection('Taxis').doc(user.uid).update({
        'settings.$key': value,
        'lastUpdated': FieldValue.serverTimestamp(),
        'currentTimestamp': _currentTimestamp,
        'currentUserLogin': _currentUserLogin,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Setting updated')),
      );
    } catch (e) {
      print('Error updating setting: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update setting')),
      );
    }
  }

  void _activateDevMode() {
    setState(() {
      _devModeClickCount++;
      if (_devModeClickCount >= 5) {
        _showCnicGenerator = true;
        _devModeClickCount = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Developer mode activated')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Settings'),
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

    return Scaffold(
      backgroundColor: Color(0xFF111111),
      appBar: AppBar(
        title: GestureDetector(
          onTap: _activateDevMode,
          child: Text('Settings'),
        ),
        backgroundColor: Color(0xFF222222),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              _buildSectionTitle('App Settings'),
              _buildSwitchTile(
                title: 'Notifications',
                subtitle: 'Receive push notifications',
                value: _notificationsEnabled,
                onChanged: (value) => _updateSetting('notificationsEnabled', value),
              ),
              _buildSwitchTile(
                title: 'Location Tracking',
                subtitle: 'Allow app to track your location when online',
                value: _locationTrackingEnabled,
                onChanged: (value) => _updateSetting('locationTrackingEnabled', value),
              ),
              _buildSwitchTile(
                title: 'Dark Mode',
                subtitle: 'Use dark theme for the app',
                value: _darkModeEnabled,
                onChanged: (value) => _updateSetting('darkModeEnabled', value),
              ),
              _buildDropdownTile(
                title: 'Language',
                value: _language,
                options: ['English', 'Urdu', 'Arabic', 'Spanish'],
                onChanged: (value) => _updateSetting('language', value),
              ),

              _buildSectionTitle('Driver Settings'),
              _buildSliderTile(
                title: 'Arrival Radius',
                subtitle: 'Distance in meters to consider "arrived"',
                value: _arrivalRadius,
                min: 20.0,
                max: 100.0,
                onChanged: (value) => _updateSetting('arrivalRadius', value),
              ),
              _buildSwitchTile(
                title: 'Auto-Accept Requests',
                subtitle: 'Automatically accept ride requests',
                value: _autoAcceptRequests,
                onChanged: (value) => _updateSetting('autoAcceptRequests', value),
              ),
              _buildSwitchTile(
                title: 'Show Earnings on Map',
                subtitle: 'Display earnings on the map interface',
                value: _showEarningsOnMap,
                onChanged: (value) => _updateSetting('showEarningsOnMap', value),
              ),

              _buildSectionTitle('Account Settings'),
              _buildActionTile(
                title: 'Change Password',
                subtitle: 'Update your account password',
                icon: Icons.lock,
                onTap: () {
                  // Show change password dialog
                  _showChangePasswordDialog();
                },
              ),
              _buildActionTile(
                title: 'Privacy Policy',
                subtitle: 'Read our privacy policy',
                icon: Icons.privacy_tip,
                onTap: () {
                  // Navigate to privacy policy
                  _showInfoDialog('Privacy Policy', 'Our privacy policy details...');
                },
              ),
              _buildActionTile(
                title: 'Terms of Service',
                subtitle: 'Read our terms of service',
                icon: Icons.description,
                onTap: () {
                  // Navigate to terms of service
                  _showInfoDialog('Terms of Service', 'Our terms of service...');
                },
              ),
              _buildActionTile(
                title: 'Delete Account',
                subtitle: 'Permanently delete your account',
                icon: Icons.delete_forever,
                iconColor: Colors.red,
                textColor: Colors.red,
                onTap: () {
                  // Show delete account confirmation
                  _showDeleteAccountDialog();
                },
              ),

              // Add timestamp info at bottom
              Container(
                padding: EdgeInsets.all(16),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Text(
                      'Last Updated: $_currentTimestamp',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'User: $_currentUserLogin',
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

          // CNIC Generator Overlay
          if (_showCnicGenerator)
            Container(
              color: Colors.black.withOpacity(0.8),
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    margin: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CnicGeneratorWidget(
                          onComplete: () {
                            setState(() {
                              _showCnicGenerator = false;
                            });
                          },
                        ),
                        SizedBox(height: 16),
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _showCnicGenerator = false;
                            });
                          },
                          child: Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 13,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Color(0xFFFF4B6C),
      ),
    );
  }

  Widget _buildDropdownTile({
    required String title,
    required String value,
    required List<String> options,
    required Function(String) onChanged,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      trailing: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Color(0xFF222222),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color(0xFF444444)),
        ),
        child: DropdownButton<String>(
          value: value,
          dropdownColor: Color(0xFF222222),
          icon: Icon(Icons.arrow_drop_down, color: Colors.white),
          underline: SizedBox(),
          style: TextStyle(color: Colors.white),
          onChanged: (newValue) {
            if (newValue != null) {
              onChanged(newValue);
            }
          },
          items: options.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: ((max - min) / 5).round(),
                  activeColor: Color(0xFFFF4B6C),
                  inactiveColor: Color(0xFF444444),
                  onChanged: onChanged,
                ),
              ),
              Container(
                width: 48,
                alignment: Alignment.center,
                child: Text(
                  value.round().toString(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Function onTap,
    Color iconColor = Colors.white,
    Color textColor = Colors.white,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 13,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () => onTap(),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xFF222222),
          title: Text(
            'Delete Account',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Are you sure you want to delete your account? This action cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                // Implement account deletion logic
              },
            ),
          ],
        );
      },
    );
  }

  void _showChangePasswordDialog() {
    final TextEditingController _currentPasswordController = TextEditingController();
    final TextEditingController _newPasswordController = TextEditingController();
    final TextEditingController _confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xFF222222),
          title: Text(
            'Change Password',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _currentPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF4B6C)),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF4B6C)),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFFF4B6C)),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                'Change',
                style: TextStyle(color: Color(0xFFFF4B6C)),
              ),
              onPressed: () {
                // Implement password change logic
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Color(0xFF222222),
          title: Text(
            title,
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            content,
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              child: Text(
                'Close',
                style: TextStyle(color: Color(0xFFFF4B6C)),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

// CNIC Generator Widget
class CnicGeneratorWidget extends StatefulWidget {
  final Function? onComplete;

  const CnicGeneratorWidget({Key? key, this.onComplete}) : super(key: key);

  @override
  _CnicGeneratorWidgetState createState() => _CnicGeneratorWidgetState();
}

class _CnicGeneratorWidgetState extends State<CnicGeneratorWidget> {
  bool _isGenerating = false;
  String _status = 'Ready to generate CNIC database';
  int _progress = 0;
  final int TOTAL_ENTRIES = 2000;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'CNIC Database Generator',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          SizedBox(height: 12),
          Text(
            _status,
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          if (_isGenerating)
            Column(
              children: [
                LinearProgressIndicator(
                  value: _progress / TOTAL_ENTRIES,
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF4B6C)),
                ),
                SizedBox(height: 8),
                Text(
                  '$_progress / $TOTAL_ENTRIES entries',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isGenerating ? Colors.grey : Color(0xFFFF4B6C),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: _isGenerating ? null : _generateCnicData,
            child: Text(
              _isGenerating ? 'Generating...' : 'Generate CNIC Database',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateCnicData() async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _status = 'Preparing to generate CNIC database...';
      _progress = 0;
    });

    try {
      await _generateMassiveCnicDatabase();

      setState(() {
        _status = '✅ Success! Generated $TOTAL_ENTRIES CNIC entries.\nYou can now delete this widget.';
      });

      if (widget.onComplete != null) {
        Future.delayed(Duration(seconds: 3), () {
          widget.onComplete!();
        });
      }
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateMassiveCnicDatabase() async {
    final FirebaseFirestore _firestore = FirebaseFirestore.instance;
    final int BATCH_SIZE = 100;

    // Names for random generation
    final List<String> _femaleFirstNames = [
      'Ayesha', 'Fatima', 'Zainab', 'Maryam', 'Amina', 'Aisha', 'Sadia', 'Noor', 'Mehwish', 'Hira',
      'Saima', 'Farah', 'Sana', 'Rabia', 'Mahnoor', 'Iqra', 'Khadija', 'Saba', 'Naila', 'Samina',
      'Asma', 'Farhat', 'Rukhsana', 'Nabila', 'Shaista', 'Uzma', 'Shazia', 'Nazia', 'Bushra', 'Tahira'
    ];

    final List<String> _maleFirstNames = [
      'Ahmed', 'Ali', 'Usman', 'Omar', 'Hassan', 'Muhammad', 'Bilal', 'Zain', 'Faisal', 'Imran',
      'Asad', 'Kamran', 'Shahid', 'Tariq', 'Farhan', 'Saad', 'Rizwan', 'Adnan', 'Salman', 'Naveed',
      'Amir', 'Nasir', 'Jameel', 'Rashid', 'Sajid', 'Junaid', 'Khalid', 'Arshad', 'Waseem', 'Yasir'
    ];

    final List<String> _lastNames = [
      'Khan', 'Ahmed', 'Ali', 'Malik', 'Qureshi', 'Sheikh', 'Siddiqui', 'Baig', 'Shah', 'Awan',
      'Butt', 'Zia', 'Raza', 'Akbar', 'Hussain', 'Javed', 'Iqbal', 'Chaudhry', 'Mahmood', 'Aziz',
      'Mirza', 'Hashmi', 'Rashid', 'Ansari', 'Abbasi', 'Bhatti', 'Farooqi', 'Kazmi', 'Gillani', 'Rizvi'
    ];

    setState(() {
      _status = 'Generating data...';
    });

    List<Map<String, dynamic>> allData = [];
    Random random = Random();

    for (int i = 0; i < TOTAL_ENTRIES; i++) {
      bool isFemale = random.nextBool();
      String firstName = isFemale
          ? _femaleFirstNames[random.nextInt(_femaleFirstNames.length)]
          : _maleFirstNames[random.nextInt(_maleFirstNames.length)];
      String lastName = _lastNames[random.nextInt(_lastNames.length)];
      int age = 18 + random.nextInt(48);

      // Generate CNIC (13 digits)
      String cnic = '';
      for (int j = 0; j < 12; j++) {
        cnic += random.nextInt(10).toString();
      }

      // Last digit - even for females, odd for males
      if (isFemale) {
        cnic += (random.nextInt(5) * 2).toString(); // 0, 2, 4, 6, 8
      } else {
        cnic += (random.nextInt(5) * 2 + 1).toString(); // 1, 3, 5, 7, 9
      }

      allData.add({
        'cnic': cnic,
        'data': {
          'Name': '$firstName $lastName',
          'Gender': isFemale ? 'female' : 'male',
          'Age': age,
          'currentTimestamp': "2025-07-02 22:48:53",
          'currentUserLogin': "AhmadHasssan9181"
        }
      });

      if (i % 50 == 0) {
        setState(() {
          _progress = i;
        });
        await Future.delayed(Duration(milliseconds: 1)); // Allow UI to update
      }
    }

    setState(() {
      _status = 'Writing data to Firestore...';
    });

    for (int i = 0; i < allData.length; i += BATCH_SIZE) {
      WriteBatch batch = _firestore.batch();
      int end = (i + BATCH_SIZE < allData.length) ? i + BATCH_SIZE : allData.length;

      for (int j = i; j < end; j++) {
        DocumentReference docRef = _firestore.collection('lily_drive_users').doc(allData[j]['cnic']);
        batch.set(docRef, allData[j]['data']);
      }

      await batch.commit();

      setState(() {
        _progress = end;
        _status = 'Writing data: ${end}/${TOTAL_ENTRIES} entries';
      });

      await Future.delayed(Duration(milliseconds: 100)); // Allow UI to update
    }
  }
}