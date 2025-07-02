import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseTestWidget extends StatefulWidget {
  const FirebaseTestWidget({Key? key}) : super(key: key);

  @override
  _FirebaseTestWidgetState createState() => _FirebaseTestWidgetState();
}

class _FirebaseTestWidgetState extends State<FirebaseTestWidget> {
  String _status = "Testing Firebase connection...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _testFirebase();
  }

  Future<void> _testFirebase() async {
    try {
      // Get Firestore instance
      final firestore = FirebaseFirestore.instance;

      // Write a document to a test collection
      await firestore.collection('firebase_test').doc('test_doc').set({
        'message': 'Firebase is working!',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Read the document back
      final docSnapshot = await firestore.collection('firebase_test').doc('test_doc').get();

      if (docSnapshot.exists) {
        setState(() {
          _status = "✅ Firebase is connected and working properly!";
          _isLoading = false;
        });
      } else {
        setState(() {
          _status = "❌ Document write succeeded but read failed";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = "❌ Firebase error: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Text(
          _status,
          style: TextStyle(
            color: _status.contains("✅") ? Colors.green : Colors.red,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}