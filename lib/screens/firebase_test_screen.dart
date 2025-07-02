import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class FirebaseTestScreen extends StatefulWidget {
  const FirebaseTestScreen({Key? key}) : super(key: key);

  @override
  _FirebaseTestScreenState createState() => _FirebaseTestScreenState();
}

class _FirebaseTestScreenState extends State<FirebaseTestScreen> {
  String _firestoreStatus = "Testing Firestore connection...";
  String _authStatus = "Testing Auth connection...";
  bool _isFirestoreLoading = true;
  bool _isAuthLoading = true;

  @override
  void initState() {
    super.initState();
    _testFirestore();
    _testAuth();
  }

  // Get current time in specified format
  String get currentFormattedTime {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _testFirestore() async {
    try {
      // Get Firestore instance
      final firestore = FirebaseFirestore.instance;

      // Write a document to a test collection
      await firestore.collection('firebase_test').doc('test_doc').set({
        'message': 'Firebase is working!',
        'timestamp': FieldValue.serverTimestamp(),
        'testDate': currentFormattedTime,
        'testUser': 'Lilydebug',
      });

      // Read the document back
      final docSnapshot = await firestore.collection('firebase_test').doc('test_doc').get();

      if (docSnapshot.exists) {
        setState(() {
          _firestoreStatus = "✅ Firestore is connected and working properly!";
          _isFirestoreLoading = false;
        });
      } else {
        setState(() {
          _firestoreStatus = "❌ Document write succeeded but read failed";
          _isFirestoreLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _firestoreStatus = "❌ Firestore error: $e";
        _isFirestoreLoading = false;
      });
    }
  }

  Future<void> _testAuth() async {
    try {
      // Get Auth instance
      final auth = FirebaseAuth.instance;

      // Check if auth is initialized
      if (auth != null) {
        setState(() {
          _authStatus = "✅ Firebase Auth is initialized properly!";
          _isAuthLoading = false;
        });
      } else {
        setState(() {
          _authStatus = "❌ Firebase Auth instance is null";
          _isAuthLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _authStatus = "❌ Firebase Auth error: $e";
        _isAuthLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Connection Test'),
        backgroundColor: Colors.pink[400],
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Go to App', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Firebase Connection Tests',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              // Firestore Test Section
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Firestore Test',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isFirestoreLoading
                          ? CircularProgressIndicator(color: Colors.pink[400])
                          : Column(
                        children: [
                          Text(
                            _firestoreStatus,
                            style: TextStyle(
                              color: _firestoreStatus.contains("✅") ? Colors.green : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_firestoreStatus.contains("✅"))
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: ElevatedButton(
                                onPressed: _testFirestore,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.pink[400],
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Test Again'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Auth Test Section
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Firebase Auth Test',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isAuthLoading
                          ? CircularProgressIndicator(color: Colors.pink[400])
                          : Column(
                        children: [
                          Text(
                            _authStatus,
                            style: TextStyle(
                              color: _authStatus.contains("✅") ? Colors.green : Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_authStatus.contains("✅"))
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: ElevatedButton(
                                onPressed: _testAuth,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.pink[400],
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Test Again'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // User info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Current Date and Time (UTC):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(currentFormattedTime),
                    const SizedBox(height: 12),
                    const Text(
                      'Current User\'s Login:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text('Lilydebug'),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => context.go('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink[400],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Go to Login'),
                  ),
                  const SizedBox(width: 20),
                  OutlinedButton(
                    onPressed: () => context.go('/'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.pink[400],
                    ),
                    child: const Text('Back to Splash'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}