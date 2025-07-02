// This is a standalone script to generate CNIC data
// Run with: flutter run -d chrome -t lib/tools/generate_cnic_data.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import '../firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: Text('CNIC Generator')),
      body: CnicGeneratorScreen(),
    ),
  ));
}

class CnicGeneratorScreen extends StatefulWidget {
  @override
  _CnicGeneratorScreenState createState() => _CnicGeneratorScreenState();
}

class _CnicGeneratorScreenState extends State<CnicGeneratorScreen> {
  bool _isGenerating = false;
  String _status = 'Ready to generate CNIC database';
  int _progress = 0;
  final int TOTAL_ENTRIES = 2000;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_status,
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            if (_isGenerating)
              Column(
                children: [
                  LinearProgressIndicator(value: _progress / TOTAL_ENTRIES),
                  SizedBox(height: 10),
                  Text('$_progress / $TOTAL_ENTRIES')
                ],
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isGenerating ? null : _generateCnicData,
              child: Text('Generate CNIC Database'),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _generateCnicData() async {
    setState(() {
      _isGenerating = true;
      _status = 'Generating CNIC database...';
      _progress = 0;
    });

    try {
      await generateMassiveCnicDatabase(
          onProgress: (count) {
            setState(() {
              _progress = count;
            });
          }
      );

      setState(() {
        _status = 'Successfully generated $TOTAL_ENTRIES CNIC entries!\nYou can close this page and delete the generator code.';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> generateMassiveCnicDatabase({Function(int)? onProgress}) async {
    final FirebaseFirestore _firestore = FirebaseFirestore.instance;
    final int TOTAL_ENTRIES = 2000;
    final int BATCH_SIZE = 100;
    Set<String> usedCnics = {}; // Track used CNICs to ensure uniqueness

    // Expanded list of female names - 50 Pakistani female names
    final List<String> _femaleFirstNames = [
      'Ayesha', 'Fatima', 'Zainab', 'Maryam', 'Amina', 'Aisha', 'Sadia', 'Noor', 'Mehwish', 'Hira',
      'Saima', 'Farah', 'Sana', 'Rabia', 'Mahnoor', 'Iqra', 'Khadija', 'Saba', 'Naila', 'Samina',
      'Asma', 'Farhat', 'Rukhsana', 'Nabila', 'Shaista', 'Uzma', 'Shazia', 'Nazia', 'Bushra', 'Tahira',
      'Tabassum', 'Kulsoom', 'Yasmin', 'Shabana', 'Fariha', 'Sobia', 'Afshan', 'Lubna', 'Iram', 'Sadia',
      'Nadia', 'Safia', 'Abida', 'Mumtaz', 'Shagufta', 'Rizwana', 'Nusrat', 'Shamim', 'Rubina', 'Tehmina'
    ];

    // List of male names
    final List<String> _maleFirstNames = [
      'Ahmed', 'Ali', 'Usman', 'Omar', 'Hassan', 'Muhammad', 'Bilal', 'Zain', 'Faisal', 'Imran',
      'Asad', 'Kamran', 'Shahid', 'Tariq', 'Farhan', 'Saad', 'Rizwan', 'Adnan', 'Salman', 'Naveed',
      'Amir', 'Nasir', 'Jameel', 'Rashid', 'Sajid', 'Junaid', 'Khalid', 'Arshad', 'Waseem', 'Yasir'
    ];

    // Pakistani last names
    final List<String> _lastNames = [
      'Khan', 'Ahmed', 'Ali', 'Malik', 'Qureshi', 'Sheikh', 'Siddiqui', 'Baig', 'Shah', 'Awan',
      'Butt', 'Zia', 'Raza', 'Akbar', 'Hussain', 'Javed', 'Iqbal', 'Chaudhry', 'Mahmood', 'Aziz',
      'Mirza', 'Hashmi', 'Rashid', 'Ansari', 'Abbasi', 'Bhatti', 'Farooqi', 'Kazmi', 'Gillani', 'Rizvi'
    ];

    // Generate a unique CNIC number
    String _generateUniqueCNIC(bool isFemale, Set<String> usedCnics) {
      Random random = Random();
      String cnic;

      do {
        // Format: XXXXX-XXXXXXX-X (without dashes)
        // First 5 digits: area code (varies by region in Pakistan)
        String areaCode = '';
        for (int i = 0; i < 5; i++) {
          areaCode += random.nextInt(10).toString();
        }

        // Middle 7 digits: family number
        String familyNumber = '';
        for (int i = 0; i < 7; i++) {
          familyNumber += random.nextInt(10).toString();
        }

        // Last digit: gender indicator (even for female, odd for male)
        String lastDigit;
        if (isFemale) {
          // Even digit (0, 2, 4, 6, 8)
          lastDigit = (random.nextInt(5) * 2).toString();
        } else {
          // Odd digit (1, 3, 5, 7, 9)
          lastDigit = (random.nextInt(5) * 2 + 1).toString();
        }

        cnic = areaCode + familyNumber + lastDigit;

      } while (usedCnics.contains(cnic)); // Ensure uniqueness

      usedCnics.add(cnic);
      return cnic;
    }

    List<Map<String, dynamic>> allData = [];
    Random random = Random();

    // Ensure balanced distribution of male/female
    int femaleCount = TOTAL_ENTRIES ~/ 2;
    int maleCount = TOTAL_ENTRIES - femaleCount;

    // First add females
    for (int i = 0; i < femaleCount; i++) {
      String firstName = _femaleFirstNames[random.nextInt(_femaleFirstNames.length)];
      String lastName = _lastNames[random.nextInt(_lastNames.length)];
      int age = 18 + random.nextInt(48);
      String cnic = _generateUniqueCNIC(true, usedCnics);

      allData.add({
        'cnic': cnic,
        'data': {
          'Name': '$firstName $lastName',
          'Gender': 'female',
          'Age': age,
        }
      });

      if (i % 50 == 0 && onProgress != null) {
        onProgress(i);
      }
    }

    // Then add males
    for (int i = 0; i < maleCount; i++) {
      String firstName = _maleFirstNames[random.nextInt(_maleFirstNames.length)];
      String lastName = _lastNames[random.nextInt(_lastNames.length)];
      int age = 18 + random.nextInt(48);
      String cnic = _generateUniqueCNIC(false, usedCnics);

      allData.add({
        'cnic': cnic,
        'data': {
          'Name': '$firstName $lastName',
          'Gender': 'male',
          'Age': age,
        }
      });

      if ((femaleCount + i) % 50 == 0 && onProgress != null) {
        onProgress(femaleCount + i);
      }
    }

    // Shuffle to mix male/female entries
    allData.shuffle(Random());

    for (int i = 0; i < allData.length; i += BATCH_SIZE) {
      WriteBatch batch = _firestore.batch();
      int end = (i + BATCH_SIZE < allData.length) ? i + BATCH_SIZE : allData.length;

      for (int j = i; j < end; j++) {
        DocumentReference docRef = _firestore.collection('lily_drive_users').doc(allData[j]['cnic']);
        batch.set(docRef, allData[j]['data']);
      }

      await batch.commit();

      if (onProgress != null) {
        onProgress(end);
      }
    }
  }
}