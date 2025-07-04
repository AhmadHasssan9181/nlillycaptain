import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({Key? key}) : super(key: key);

  @override
  _DriverRegistrationScreenState createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = false;
  String? _cnicError;
  String? _autoVerificationMessage;
  File? _cnicImage;
  bool _isScanning = false;
  String? _cnicImageUrl;
  String? _detectedGender;

  // Additional extracted CNIC data
  String? _extractedName;
  String? _extractedFatherName;
  String? _extractedDob;
  String? _nameTypeDetected; // Track whether father's or husband's name was detected

  // Form fields
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _genderController = TextEditingController(); // Read-only gender field
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

  // Gender selection
  String _selectedGender = 'Female'; // Default to female since this is for female drivers
  final List<String> _genderOptions = ['Female', 'Male'];

  @override
  void dispose() {
    _fullNameController.dispose();
    _fatherNameController.dispose();
    _dobController.dispose();
    _genderController.dispose();
    _phoneController.dispose();
    _cnicController.dispose();
    _driverLicenseController.dispose();
    _carNameController.dispose();
    _carModelController.dispose();
    _carColorController.dispose();
    _licensePlateController.dispose();
    _enginePowerController.dispose();
    _seatingCapacityController.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // Pick image from gallery or camera
  Future<void> _pickCnicImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85, // Higher quality for better text recognition
        maxWidth: 1600,    // Higher resolution for better OCR
      );

      if (pickedFile != null) {
        setState(() {
          _cnicImage = File(pickedFile.path);
          _isScanning = true;
          _detectedGender = null; // Reset detected data
          _extractedName = null;
          _extractedFatherName = null;
          _extractedDob = null;
          _nameTypeDetected = null;
        });

        // Process the image
        await _processCnicImage();
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e'))
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  // Process the image using ML Kit to extract all relevant information
  Future<void> _processCnicImage() async {
    if (_cnicImage == null) return;

    try {
      // Convert to InputImage for ML Kit
      final inputImage = InputImage.fromFile(_cnicImage!);

      // Process with text recognizer
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // Extract CNIC using regex pattern
      final cnicPattern = RegExp(r'[0-9]{5}[-]?[0-9]{7}[-]?[0-9]{1}');
      String? cnic;
      String? detectedGender;
      String? extractedName;
      String? extractedFatherName;
      String? extractedDob;
      String? nameTypeDetected;

      // Variables to help with extraction
      bool foundNameLabel = false;
      bool foundFatherNameLabel = false;
      bool foundGenderLabel = false;
      bool foundDobLabel = false;

      // Debug full text recognition
      print('--- Full OCR Text ---');
      String fullText = "";
      for (TextBlock block in recognizedText.blocks) {
        print(block.text);
        fullText += block.text + "\n";
      }
      print('--------------------');

      // Process all detected text blocks
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String lineText = line.text.trim();
          String lowerText = lineText.toLowerCase();

          // Check for CNIC number
          final match = cnicPattern.firstMatch(lineText.replaceAll(" ", ""));
          if (match != null) {
            // Remove any dashes and spaces to get clean digits
            cnic = match.group(0)?.replaceAll(RegExp(r'[^\d]'), '');
            print('Found CNIC: $cnic');
          }

          // Extract Name - enhanced to catch more formats
          if (lowerText.contains('name') && !lowerText.contains('father') &&
              !lowerText.contains('husband') && !foundNameLabel) {
            foundNameLabel = true;
            // Try to extract name from the same line
            List<String> parts = lineText.split(RegExp(r'[:]'));
            if (parts.length > 1 && parts[1].trim().isNotEmpty) {
              extractedName = parts[1].trim();
              print('Found Name (same line): $extractedName');
            } else {
              // Name might be on the next line
              int blockIndex = recognizedText.blocks.indexOf(block);
              int lineIndex = block.lines.indexOf(line);

              // Check if there are more lines in this block
              if (lineIndex + 1 < block.lines.length) {
                String nextLine = block.lines[lineIndex + 1].text.trim();
                if (!nextLine.toLowerCase().contains(':') && !nextLine.toLowerCase().contains('father') &&
                    !nextLine.toLowerCase().contains('husband')) {
                  extractedName = nextLine;
                  print('Found Name (next line in same block): $extractedName');
                }
              }
              // Check next block if needed
              else if (blockIndex + 1 < recognizedText.blocks.length) {
                if (recognizedText.blocks[blockIndex + 1].lines.isNotEmpty) {
                  String nextLine = recognizedText.blocks[blockIndex + 1].lines[0].text.trim();
                  if (!nextLine.toLowerCase().contains(':') && !nextLine.toLowerCase().contains('father') &&
                      !nextLine.toLowerCase().contains('husband')) {
                    extractedName = nextLine;
                    print('Found Name (next block): $extractedName');
                  }
                }
              }
            }
          }

          // Extract Father's/Husband's Name - enhanced to handle both cases
          if (lowerText.contains('father') || lowerText.contains('husband') ||
              lowerText.contains('father name') || lowerText.contains('father\'s name') ||
              lowerText.contains('husband name') || lowerText.contains('husband\'s name')) {

            foundFatherNameLabel = true;
            nameTypeDetected = lowerText.contains('husband') ? "Husband's" : "Father's";
            print('Found ${nameTypeDetected} name label in: $lineText');

            // Try to extract the name from the same line
            List<String> parts = lineText.split(RegExp(r'[:]'));
            if (parts.length > 1 && parts[1].trim().isNotEmpty) {
              extractedFatherName = parts[1].trim();
              print('Found ${nameTypeDetected} name (same line): $extractedFatherName');
            } else {
              // Name might be on the next line
              int blockIndex = recognizedText.blocks.indexOf(block);
              int lineIndex = block.lines.indexOf(line);

              // Check if there are more lines in this block
              if (lineIndex + 1 < block.lines.length) {
                String nextLine = block.lines[lineIndex + 1].text.trim();
                if (!nextLine.toLowerCase().contains(':') && !nextLine.toLowerCase().contains('gender')) {
                  extractedFatherName = nextLine;
                  print('Found ${nameTypeDetected} name (next line in same block): $extractedFatherName');
                }
              }
              // Check next block if needed
              else if (blockIndex + 1 < recognizedText.blocks.length) {
                if (recognizedText.blocks[blockIndex + 1].lines.isNotEmpty) {
                  String nextLine = recognizedText.blocks[blockIndex + 1].lines[0].text.trim();
                  if (!nextLine.toLowerCase().contains(':') && !nextLine.toLowerCase().contains('gender')) {
                    extractedFatherName = nextLine;
                    print('Found ${nameTypeDetected} name (next block): $extractedFatherName');
                  }
                }
              }
            }
          }

          // Look for gender field - enhanced for better detection
          if (lowerText.contains('gender') || lineText.contains('M') && lineText.length < 3 || lineText.contains('F') && lineText.length < 3) {
            // Case 1: Explicit gender label
            if (lowerText.contains('gender')) {
              foundGenderLabel = true;
              // Check if the gender value is on the same line
              if ((lineText.contains('F') || lineText.contains('f')) && !lowerText.contains('father')) {
                detectedGender = 'F';
                print('Found Gender (F) in line: $lineText');
              } else if ((lineText.contains('M') || lineText.contains('m')) && !lowerText.contains('mother')) {
                detectedGender = 'M';
                print('Found Gender (M) in line: $lineText');
              }
            }
            else if ((lineText.trim() == 'M' || lineText.trim() == 'm') && detectedGender == null) {
              detectedGender = 'M';
              print('Found isolated Gender (M)');
            } else if ((lineText.trim() == 'F' || lineText.trim() == 'f') && detectedGender == null) {
              detectedGender = 'F';
              print('Found isolated Gender (F)');
            }
          }
          // Check for gender in a table-like format (looking at your screenshot)
          else if (lineText.contains('M') && lineText.length < 5 && detectedGender == null) {
            detectedGender = 'M';
            print('Found Gender (M) in short text: $lineText');
          } else if (lineText.contains('F') && lineText.length < 5 && detectedGender == null) {
            detectedGender = 'F';
            print('Found Gender (F) in short text: $lineText');
          }

          // Extract Date of Birth - enhanced for better detection
          if (lowerText.contains('date of birth') || lowerText.contains('dob') || lowerText.contains('birth')) {
            foundDobLabel = true;
            // Try to extract DOB from the same line
            // Look for date patterns like DD.MM.YYYY or DD-MM-YYYY or DD/MM/YYYY
            RegExp datePattern = RegExp(r'\d{2}[./-]\d{2}[./-]\d{4}|\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}\.\d{1,2}\.\d{2}');
            var dateMatch = datePattern.firstMatch(lineText);
            if (dateMatch != null) {
              extractedDob = dateMatch.group(0);
              print('Found DOB (same line): $extractedDob');
            } else {
              // Check the next line for date pattern
              int blockIndex = recognizedText.blocks.indexOf(block);
              int lineIndex = block.lines.indexOf(line);

              // Check if there are more lines in this block
              if (lineIndex + 1 < block.lines.length) {
                String nextLine = block.lines[lineIndex + 1].text.trim();
                dateMatch = RegExp(r'\d{2}[./-]\d{2}[./-]\d{4}|\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}\.\d{1,2}\.\d{2}').firstMatch(nextLine);
                if (dateMatch != null) {
                  extractedDob = dateMatch.group(0);
                  print('Found DOB (next line): $extractedDob');
                }
              }
            }
          }
          // Look for standalone dates in a standard format that might be DOB
          else if (extractedDob == null) {
            RegExp datePattern = RegExp(r'\d{2}[./-]\d{2}[./-]\d{4}|\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}\.\d{1,2}\.\d{2}');
            var dateMatch = datePattern.firstMatch(lineText);
            if (dateMatch != null) {
              extractedDob = dateMatch.group(0);
              print('Found potential DOB (from standalone date): $extractedDob');
            }
          }
        }
      }

      // If CNIC was found, set it and other extracted fields
      if (cnic != null && cnic.length == 13) {
        setState(() {
          _cnicController.text = cnic!;
          _detectedGender = detectedGender;
          _extractedName = extractedName;
          _extractedFatherName = extractedFatherName;
          _extractedDob = extractedDob;
          _nameTypeDetected = nameTypeDetected;

          // Auto-fill form fields with extracted data
          if (extractedName != null && extractedName.isNotEmpty) {
            _fullNameController.text = extractedName;
          }

          // Set father's or husband's name if found
          if (extractedFatherName != null && extractedFatherName.isNotEmpty) {
            _fatherNameController.text = extractedFatherName;
            if (nameTypeDetected != null) {
              print('Setting ${nameTypeDetected.toLowerCase()} name to: $extractedFatherName');
            } else {
              print('Setting father\'s name to: $extractedFatherName');
            }
          }

          if (extractedDob != null && extractedDob.isNotEmpty) {
            _dobController.text = extractedDob;
          }

          // Set gender dropdown and controller
          if (detectedGender != null) {
            _selectedGender = detectedGender == 'F' ? 'Female' : 'Male';
            _genderController.text = _selectedGender;
          }
        });

        // Validate gender
        _validateGender(cnic, detectedGender);

        // Show feedback to user with context about what was detected
        String nameTypeMsg = nameTypeDetected != null ? " ${nameTypeDetected} name detected." : "";
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('CNIC scanned successfully. Information has been auto-filled.$nameTypeMsg'),
              backgroundColor: Colors.green,
            )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not detect a valid CNIC number. Please try again or enter manually.'))
        );
      }
    } catch (e) {
      print('Error processing CNIC image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing image: $e'))
      );
    }
  }

  // Open date picker
  Future<void> _selectDate() async {
    DateTime? initialDate;
    try {
      if (_dobController.text.isNotEmpty) {
        // Try to parse existing date in controller
        List<String> parts = _dobController.text.split(RegExp(r'[./-]'));
        if (parts.length == 3) {
          int day = int.tryParse(parts[0]) ?? 1;
          int month = int.tryParse(parts[1]) ?? 1;
          int year = int.tryParse(parts[2]) ?? 1980;

          // Handle 2-digit years
          if (year < 100) {
            year += year >= 50 ? 1900 : 2000;
          }

          initialDate = DateTime(year, month, day);
        }
      }
    } catch (e) {
      print('Error parsing date: $e');
    }

    initialDate ??= DateTime(1990, 1, 1); // Default to 1990 if parsing fails

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: DateTime(DateTime.now().year - 18, DateTime.now().month, DateTime.now().day),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: Color(0xFFFF4B6C),
              onPrimary: Colors.white,
              surface: Color(0xFF222222),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Color(0xFF333333),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Format the date as DD-MM-YYYY
      final formattedDate = DateFormat('dd-MM-yyyy').format(picked);
      setState(() {
        _dobController.text = formattedDate;
      });
    }
  }

  // Upload CNIC image to Firebase Storage
  Future<String?> _uploadCnicImage() async {
    if (_cnicImage == null) return null;

    try {
      final String uid = _auth.currentUser?.uid ?? DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'cnic_${uid}_${path.basename(_cnicImage!.path)}';
      final Reference storageRef = _storage.ref().child('cnic_images/$fileName');

      // Upload the file
      await storageRef.putFile(_cnicImage!);

      // Get download URL
      return await storageRef.getDownloadURL();
    } catch (e) {
      print('Error uploading CNIC image: $e');
      return null;
    }
  }

  // Validate gender from CNIC and/or detected gender field
  bool _validateGender(String cnic, String? detectedGender) {
    // Clean CNIC number
    String cleanCNIC = cnic.replaceAll(RegExp(r'[^\d]'), '');

    // Check if CNIC is 13 digits
    if (cleanCNIC.length != 13) {
      setState(() {
        _cnicError = 'CNIC must be 13 digits';
        _autoVerificationMessage = null;
      });
      return false;
    }

    // Determine gender from CNIC's last digit (even = female, odd = male)
    int lastDigit = int.parse(cleanCNIC[12]);
    bool isFemaleByLastDigit = lastDigit % 2 == 0;

    // If we have detected gender from the card, use that as primary
    bool isFemale = false;
    String genderSource = '';

    if (detectedGender != null) {
      isFemale = detectedGender == 'F';
      genderSource = 'OCR detected gender: $detectedGender';
    } else {
      isFemale = isFemaleByLastDigit;
      genderSource = 'CNIC last digit ${isFemaleByLastDigit ? '(even)' : '(odd)'}';
    }

    // Set the gender selection based on detection
    setState(() {
      _selectedGender = isFemale ? 'Female' : 'Male';
    });

    // Check if female based on final determination
    if (!isFemale) {
      setState(() {
        _cnicError = 'Only females can register as drivers. Your CNIC indicates you are male.';
        _autoVerificationMessage = null;
      });
      return false;
    }

    // If we get here, the person is female
    setState(() {
      _cnicError = null;
      _autoVerificationMessage = 'Gender verified: Female ($genderSource)';
    });

    // Check if CNIC is in the verified database
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
        // Only show gender verification if not in verified database
        setState(() {
          if (_autoVerificationMessage == null) {
            _autoVerificationMessage = 'Gender verified: Female';
          }
        });
      }
    } catch (e) {
      print('Error checking CNIC in verified database: $e');
    }
  }

  Future<void> _submitRegistration() async {
    // Check if CNIC image is mandatory (for scanning purposes only, not for storage)
    if (_cnicImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please scan your CNIC. This is required for verification.'),
            backgroundColor: Colors.red,
          )
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Final gender validation check
    String cleanCNIC = _cnicController.text.replaceAll(RegExp(r'[^\d]'), '');
    bool genderValid = _validateGender(cleanCNIC, _detectedGender);
    if (!genderValid) {
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

      // Use default image - no need to upload
      String driverImage = "https://randomuser.me/api/portraits/women/67.jpg";

      // Clean text input data
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
      final bool isExistingInDatabase = verificationDoc.exists;

      // Since we've validated that this is a female, always approve
      final bool isAutoApproved = true;

      // If CNIC doesn't exist in lily_drive_users, add it there
      if (!isExistingInDatabase) {
        // Add to lily_drive_users collection for future auto-verification
        await _firestore.collection('lily_drive_users').doc(cleanCNIC).set({
          'Age': _calculateAge(_extractedDob ?? _dobController.text),
          'Gender': _selectedGender.toLowerCase(),
          'Name': _extractedName ?? _fullNameController.text,
          'FatherName': _extractedFatherName ?? _fatherNameController.text,
          'DateOfBirth': _extractedDob ?? _dobController.text,
          'NameType': _nameTypeDetected ?? "Father's", // Store whether it's father's or husband's name
          'OCRScanTimestamp': FieldValue.serverTimestamp(),
          'HasScannedDocument': true,  // Note that we scanned a document, even if we didn't store it
          'ScannedBy': currentUser.uid,
        });

        print("Added new CNIC to lily_drive_users collection");
      }

      // Since gender is female, always set status to approved
      String status = 'approved';

      // Set verification data - storing text data without the image URL
      Map<String, dynamic> verificationData = {
        'verificationMethod': 'automatic',
        'isPreVerified': true,
        'genderVerified': true,
        'detectedGender': _selectedGender.toLowerCase(),
        'nameType': _nameTypeDetected ?? "Father's", // Store whether it's father's or husband's name
        'hasScannedDocument': true,  // Document was scanned, even if not stored
        'extractedDataTime': FieldValue.serverTimestamp(),
        'extractionSuccess': true,
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
        'fatherName': _fatherNameController.text, // Could be father's or husband's name
        'nameType': _nameTypeDetected ?? "Father's", // Store type of name detected
        'dateOfBirth': _dobController.text,
        'phoneNumber': cleanPhone,
        'cnic': cleanCNIC,
        'driverLicense': cleanLicense,
        'city': _selectedCity,
        'gender': _selectedGender.toLowerCase(),

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
        'status': status, // Always 'approved' for female drivers
        'isApproved': true, // Always approved for female drivers
        'verificationData': verificationData,
        'isOnline': false,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      print("Registration data successfully saved to Firestore");
      print("Driver automatically approved (female)");

      // Always navigate to home screen for approved female drivers
      context.go('/home');

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

  // Helper to calculate age from date of birth
  int _calculateAge(String dob) {
    try {
      // Parse DOB string to DateTime
      List<String> parts = dob.split(RegExp(r'[./-]'));
      if (parts.length == 3) {
        int? day = int.tryParse(parts[0]);
        int? month = int.tryParse(parts[1]);
        int? year = int.tryParse(parts[2]);

        if (day != null && month != null && year != null) {
          // Handle 2-digit years
          if (year < 100) {
            year += year >= 50 ? 1900 : 2000;
          }

          DateTime birthDate = DateTime(year, month, day);
          DateTime today = DateTime.now();

          int age = today.year - birthDate.year;
          if (today.month < birthDate.month ||
              (today.month == birthDate.month && today.day < birthDate.day)) {
            age--;
          }
          return age;
        }
      }
    } catch (e) {
      print('Error calculating age: $e');
    }
    return 20; // Default age if calculation fails
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

                // Father's/Husband's Name
                _buildTextField(
                  controller: _fatherNameController,
                  labelText: _nameTypeDetected ?? 'Father\'s Name',
                  icon: Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter ${_nameTypeDetected != null ? _nameTypeDetected?.toLowerCase() : "father\'s"} name';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Gender Selection
                _buildDropdownField(
                  icon: _selectedGender == 'Female' ? Icons.female : Icons.male,
                  iconColor: _selectedGender == 'Female' ? Colors.pink : Colors.blue,
                  labelText: 'Gender',
                  value: _selectedGender,
                  items: _genderOptions.map((gender) {
                    return DropdownMenuItem(
                      value: gender,
                      child: Text(gender),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedGender = value.toString();
                      if (_selectedGender == 'Male') {
                        _cnicError = 'Only females can register as drivers';
                      } else {
                        _cnicError = null;
                      }
                    });
                  },
                ),
                SizedBox(height: 16),

                // Date of Birth
                GestureDetector(
                  onTap: _selectDate,
                  child: AbsorbPointer(
                    child: _buildTextField(
                      controller: _dobController,
                      labelText: 'Date of Birth (DD-MM-YYYY)',
                      icon: Icons.calendar_today,
                      suffixIcon: Icons.arrow_drop_down,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your date of birth';
                        }
                        // Simple validation for date format
                        if (!RegExp(r'\d{1,2}[./-]\d{1,2}[./-]\d{2,4}').hasMatch(value)) {
                          return 'Use format: DD-MM-YYYY';
                        }
                        return null;
                      },
                    ),
                  ),
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
                SizedBox(height: 24),

                // CNIC Scanning Section
                _sectionTitle('CNIC Information'),
                SizedBox(height: 8),

                // "Required" text if no image is selected
                if (_cnicImage == null)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'CNIC scanning is mandatory for verification',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                // CNIC Image preview if available
                if (_cnicImage != null)
                  Container(
                    height: 140,
                    margin: EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Color(0xFF333333)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          // Image
                          Positioned.fill(
                            child: Image.file(
                              _cnicImage!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Remove button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: IconButton(
                                icon: Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _cnicImage = null;
                                    _detectedGender = null;
                                    _extractedName = null;
                                    _extractedFatherName = null;
                                    _extractedDob = null;
                                    _nameTypeDetected = null;
                                  });
                                },
                                iconSize: 20,
                                constraints: BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          // Scanning overlay
                          if (_isScanning)
                            Container(
                              color: Colors.black54,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: Color(0xFFFF4B6C)),
                                    SizedBox(height: 16),
                                    Text(
                                      'Scanning CNIC...',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Scan buttons
                Container(
                  margin: EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.camera_alt),
                          label: Text('SCAN WITH CAMERA'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Color(0xFFFF4B6C),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _pickCnicImage(ImageSource.camera),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.photo_library),
                          label: Text('UPLOAD IMAGE'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Color(0xFF333333),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _pickCnicImage(ImageSource.gallery),
                        ),
                      ),
                    ],
                  ),
                ),

                // CNIC input field
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
                      _validateGender(value, _detectedGender);
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
                    foregroundColor: Colors.white,
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

  // Widget for read-only text fields
  Widget _buildReadOnlyField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    Color iconColor = const Color(0xFFFF4B6C),
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      readOnly: true,
      enabled: false,
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: iconColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Color(0xFF333333),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
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
    IconData? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Color(0xFFFF4B6C)),
        suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: Colors.white70) : null,
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
    Color iconColor = const Color(0xFFFF4B6C),
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Color(0xFF222222),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
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