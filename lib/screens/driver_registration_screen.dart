import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({Key? key}) : super(key: key);

  @override
  _DriverRegistrationScreenState createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  String? _cnicError;
  String? _autoVerificationMessage;

  // Form fields
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _driverLicenseController = TextEditingController();
  final TextEditingController _carNameController = TextEditingController();
  final TextEditingController _carModelController = TextEditingController();
  final TextEditingController _carColorController = TextEditingController();
  final TextEditingController _licensePlateController = TextEditingController();
  final TextEditingController _enginePowerController = TextEditingController();
  final TextEditingController _seatingCapacityController = TextEditingController();

  String _selectedCity = 'Lahore';
  String _selectedVehicleType = 'Sedan';
  final List<String> _cities = ['Lahore', 'Karachi', 'Islamabad', 'Rawalpindi', 'Multan', 'Faisalabad', 'Peshawar'];
  final List<String> _vehicleTypes = ['Sedan', 'Mini-SUV', 'SUV', 'Hatchback', 'Van'];

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _cnicController.dispose();
    _driverLicenseController.dispose();
    _carNameController.dispose();
    _carModelController.dispose();
    _carColorController.dispose();
    _licensePlateController.dispose();
    _enginePowerController.dispose();
    _seatingCapacityController.dispose();
    super.dispose();
  }

  // Validate CNIC for female (even last digit)
  bool _validateCNIC(String cnic) {
    // Remove any dashes or spaces
    String cleanCNIC = cnic.replaceAll(RegExp(r'[^\d]'), '');

    // Check if CNIC is 13 digits
    if (cleanCNIC.length != 13) {
      setState(() {
        _cnicError = 'CNIC must be 13 digits';
        _autoVerificationMessage = null;
      });
      return false;
    }

    // Check if last digit is even (female)
    int lastDigit = int.parse(cleanCNIC[12]);
    if (lastDigit % 2 != 0) {
      setState(() {
        _cnicError = 'Only females can register as drivers. CNIC last digit must be even.';
        _autoVerificationMessage = null;
      });
      return false;
    }

    // If we get here, the CNIC is valid (female)
    setState(() {
      _cnicError = null;
    });

    // Check if CNIC is in the database
    _checkCnicInVerifiedDatabase(cleanCNIC);

    return true;
  }

  // Check if CNIC is in the verified database
  Future<void> _checkCnicInVerifiedDatabase(String cnic) async {
    try {
      final doc = await _firestore.collection('lily_drive_users').doc(cnic).get();

      if (doc.exists) {
        setState(() {
          _autoVerificationMessage = 'Your CNIC has been verified! You will be automatically approved.';
        });
      } else {
        setState(() {
          _autoVerificationMessage = null;
        });
      }
    } catch (e) {
      print('Error checking CNIC in verified database: $e');
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Additional CNIC validation
    if (!_validateCNIC(_cnicController.text)) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }

      // Use default image - no upload
      String driverImage = "https://randomuser.me/api/portraits/women/67.jpg";

      // Clean text input data
      String cleanCNIC = _cnicController.text.replaceAll(RegExp(r'[^\d]'), '');
      String cleanLicense = _driverLicenseController.text.replaceAll(RegExp(r'[^\d]'), '');
      String cleanPhone = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');

      // Parse numeric fields safely
      int enginePower = 0;
      try {
        enginePower = int.parse(_enginePowerController.text);
      } catch (e) {
        print("Error parsing engine power: $e");
      }

      int seatingCapacity = 4;
      try {
        seatingCapacity = int.parse(_seatingCapacityController.text);
      } catch (e) {
        print("Error parsing seating capacity: $e");
      }

      // Check if CNIC is in verified database for auto-approval
      final verificationDoc = await _firestore.collection('lily_drive_users').doc(cleanCNIC).get();
      final bool isAutoApproved = verificationDoc.exists;

      // Set status based on verification
      String status = isAutoApproved ? 'approved' : 'pending';

      // Set verification data
      Map<String, dynamic> verificationData = {
        'verificationMethod': isAutoApproved ? 'automatic' : 'pending',
        'verificationTimestamp': FieldValue.serverTimestamp(),
        'isPreVerified': isAutoApproved,
      };

      // Store ALL information in the Taxis collection
      await _firestore.collection('Taxis').doc(currentUser.uid).set({
        // Authentication info
        'driverId': currentUser.uid,
        'email': currentUser.email,
        'photoURL': currentUser.photoURL,
        'driverImage': driverImage,

        // Driver personal info
        'driverName': _fullNameController.text,
        'phoneNumber': cleanPhone,
        'cnic': cleanCNIC,
        'driverLicense': cleanLicense,
        'city': _selectedCity,

        // Car details
        'car': {
          'name': _carNameController.text,
          'model': _carModelController.text,
          'color': _carColorController.text,
          'licensePlate': _licensePlateController.text,
          'enginePowerCC': enginePower,
          'seatingCapacity': seatingCapacity,
        },

        // Vehicle fields from the example
        'vehicleModel': _carModelController.text,
        'vehiclePlate': _licensePlateController.text,
        'vehicleType': _selectedVehicleType,

        // Location data
        'lat': 33.6514140949972,
        'lng': 73.07966650879322,

        // Rating and stats
        'rank': 'New',
        'rating': 0.0,
        'totalRides': 0,

        // System fields
        'registrationDate': FieldValue.serverTimestamp(),
        'status': status, // 'approved' or 'pending' based on verification
        'isApproved': isAutoApproved,
        'verificationData': verificationData,
        'isOnline': false,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      print("Registration data successfully saved to Firestore");
      print("Driver ${isAutoApproved ? 'automatically approved' : 'pending manual approval'}");

      // Navigate to appropriate screen based on approval status
      if (isAutoApproved) {
        context.go('/home'); // Go to driver home if approved
      } else {
        context.go('/driver-dashboard'); // Go to dashboard/pending screen
      }

    } catch (e) {
      print('Error during driver registration: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${e.toString()}'))
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Registration'),
        backgroundColor: Color(0xFF222222),
      ),
      body: Container(
        color: Color(0xFF111111),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: Color(0xFFFF4B6C)))
            : SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Section
                Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        // Static avatar, no onTap
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Color(0xFF333333),
                          backgroundImage: NetworkImage("https://randomuser.me/api/portraits/women/67.jpg"),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Complete Your Driver Profile',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'We need some additional information to verify your account',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // Personal Information Section
                _sectionTitle('Personal Information'),
                SizedBox(height: 16),

                // Full Name
                _buildTextField(
                  controller: _fullNameController,
                  labelText: 'Full Name',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your full name';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Phone Number
                _buildTextField(
                  controller: _phoneController,
                  labelText: 'Phone Number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (value.replaceAll(RegExp(r'[^\d]'), '').length < 10) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // CNIC
                _buildTextField(
                  controller: _cnicController,
                  labelText: 'CNIC Number (13 digits)',
                  icon: Icons.credit_card,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(13),
                  ],
                  errorText: _cnicError,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your CNIC';
                    }
                    if (value.replaceAll(RegExp(r'[^\d]'), '').length != 13) {
                      return 'CNIC must be 13 digits';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    if (value.length == 13) {
                      _validateCNIC(value);
                    }
                  },
                ),

                // Auto-verification message
                if (_autoVerificationMessage != null)
                  Container(
                    margin: EdgeInsets.only(top: 8, bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _autoVerificationMessage!,
                            style: TextStyle(color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),

                SizedBox(height: 16),

                // Driver License
                _buildTextField(
                  controller: _driverLicenseController,
                  labelText: 'Driver\'s License Number',
                  icon: Icons.assignment_ind,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your driver\'s license number';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // City Dropdown
                _buildDropdownField(
                  icon: Icons.location_city,
                  labelText: 'City of Residence',
                  value: _selectedCity,
                  items: _cities.map((city) {
                    return DropdownMenuItem(
                      value: city,
                      child: Text(city),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCity = value.toString();
                    });
                  },
                ),

                SizedBox(height: 24),

                // Vehicle Information
                _sectionTitle('Vehicle Information'),
                SizedBox(height: 16),

                // Car Name
                _buildTextField(
                  controller: _carNameController,
                  labelText: 'Car Name/Make',
                  icon: Icons.directions_car,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your car name';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Car Model
                _buildTextField(
                  controller: _carModelController,
                  labelText: 'Car Model/Year',
                  icon: Icons.calendar_today,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your car model';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Car Color
                _buildTextField(
                  controller: _carColorController,
                  labelText: 'Car Color',
                  icon: Icons.color_lens,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your car color';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // License Plate
                _buildTextField(
                  controller: _licensePlateController,
                  labelText: 'License Plate Number',
                  icon: Icons.credit_card,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your license plate number';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Vehicle Type Dropdown
                _buildDropdownField(
                  icon: Icons.local_taxi,
                  labelText: 'Vehicle Type',
                  value: _selectedVehicleType,
                  items: _vehicleTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVehicleType = value.toString();
                    });
                  },
                ),
                SizedBox(height: 16),

                // Engine Power CC
                _buildTextField(
                  controller: _enginePowerController,
                  labelText: 'Engine Power (CC)',
                  icon: Icons.speed,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter engine power in CC';
                    }
                    int? power = int.tryParse(value);
                    if (power == null || power < 500 || power > 10000) {
                      return 'Enter a valid power (500-10000 CC)';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Seating Capacity
                _buildTextField(
                  controller: _seatingCapacityController,
                  labelText: 'Seating Capacity',
                  icon: Icons.event_seat,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter seating capacity';
                    }
                    int? capacity = int.tryParse(value);
                    if (capacity == null || capacity < 1 || capacity > 10) {
                      return 'Enter a valid capacity (1-10)';
                    }
                    return null;
                  },
                ),

                SizedBox(height: 32),

                // Terms and Conditions
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFF222222),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'By registering, you agree to:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      _bulletPoint('Verify your identity documents are authentic'),
                      _bulletPoint('Undergo a background verification check'),
                      _bulletPoint('Comply with all local transportation laws'),
                      _bulletPoint('Maintain your vehicle in excellent condition'),
                      _bulletPoint('Provide accurate location tracking during rides'),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Submit Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF4B6C),
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      )
                  ),
                  onPressed: _submitRegistration,
                  child: Text(
                    'SUBMIT REGISTRATION',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFFF4B6C), width: 1),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Color(0xFFFF4B6C)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Color(0xFF222222),
        errorText: errorText,
        errorStyle: TextStyle(color: Colors.redAccent),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Color(0xFFFF4B6C)),
        ),
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownField({
    required IconData icon,
    required String labelText,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required void Function(Object?) onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Color(0xFFFF4B6C)),
          SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                items: items,
                onChanged: onChanged,
                isExpanded: true,
                dropdownColor: Color(0xFF333333),
                style: TextStyle(color: Colors.white),
                icon: Icon(Icons.arrow_drop_down, color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: TextStyle(color: Color(0xFFFF4B6C), fontSize: 14)),
          SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}