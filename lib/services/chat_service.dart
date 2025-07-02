import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current timestamp and user info for logging
  final String _currentTimestamp = "2025-06-05 20:02:01";
  final String _currentUserLogin = "Lilydebug";

  // Create or get existing Ride document for chat
  Future<String> _ensureRideDocumentExists(String passengerRequestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      print('[2025-06-05 20:02:01] [Lilydebug] Ensuring ride document exists for PassengerRequest: $passengerRequestId');

      // First, check if a Ride document already exists for this PassengerRequest
      QuerySnapshot existingRides = await _firestore
          .collection('Rides')
          .where('passengerRequestId', isEqualTo: passengerRequestId)
          .limit(1)
          .get();

      if (existingRides.docs.isNotEmpty) {
        String existingRideId = existingRides.docs.first.id;
        print('[2025-06-05 20:02:01] [Lilydebug] Found existing Ride document: $existingRideId');
        return existingRideId;
      }

      // Get PassengerRequest data to populate Ride document
      DocumentSnapshot passengerRequestDoc = await _firestore
          .collection('PassengerRequests')
          .doc(passengerRequestId)
          .get();

      if (!passengerRequestDoc.exists) {
        throw Exception('PassengerRequest not found');
      }

      final passengerRequestData = passengerRequestDoc.data() as Map<String, dynamic>;

      // Create new Ride document with same ID as PassengerRequest for simplicity
      String rideId = passengerRequestId;

      await _firestore.collection('Rides').doc(rideId).set({
        'passengerRequestId': passengerRequestId,
        'driverId': currentUser.uid,
        'driverName': currentUser.displayName ?? 'Captain',
        'passengerId': passengerRequestData['passengerId'],
        'passengerName': passengerRequestData['passengerName'] ?? 'Passenger',
        'passengerImage': passengerRequestData['passengerImage'] ?? 'https://randomuser.me/api/portraits/women/44.jpg',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'driverUnreadCount': 0,
        'passengerUnreadCount': 0,
        'currentTimestamp': _currentTimestamp,
        'currentUserLogin': _currentUserLogin,

        // Copy relevant data from PassengerRequest
        'pickupAddress': passengerRequestData['pickupAddress'],
        'destinationAddress': passengerRequestData['destinationAddress'],
        'fare': passengerRequestData['rideFare'] ?? passengerRequestData['fare'],
      }, SetOptions(merge: true));

      print('[2025-06-05 20:02:01] [Lilydebug] Created new Ride document: $rideId');
      return rideId;

    } catch (e) {
      print('[2025-06-05 20:02:01] [Lilydebug] Error ensuring ride document exists: $e');
      rethrow;
    }
  }

  // Get chat messages for a specific ride
  Stream<List<ChatMessage>> getChatMessages(String passengerRequestId) async* {
    try {
      print('[2025-06-05 20:02:01] [Lilydebug] Getting chat messages for PassengerRequest: $passengerRequestId');

      // Ensure Ride document exists and get its ID
      String rideId = await _ensureRideDocumentExists(passengerRequestId);

      // Now stream messages from the Ride document
      yield* _firestore
          .collection('Rides')
          .doc(rideId)
          .collection('Messages')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
        print('[2025-06-05 20:02:01] [Lilydebug] Received ${snapshot.docs.length} messages for ride: $rideId');

        return snapshot.docs.map((doc) {
          try {
            return ChatMessage.fromMap(doc.data(), doc.id);
          } catch (e) {
            print('[2025-06-05 20:02:01] [Lilydebug] Error parsing message ${doc.id}: $e');
            rethrow;
          }
        }).toList();
      });
    } catch (e) {
      print('[2025-06-05 20:02:01] [Lilydebug] Error in getChatMessages: $e');
      yield [];
    }
  }

  Future<void> sendMessage(String passengerRequestId, String content) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      print('[2025-06-05 20:02:01] [Lilydebug] Sending message for PassengerRequest: $passengerRequestId');

      // Ensure Ride document exists and get its ID
      String rideId = await _ensureRideDocumentExists(passengerRequestId);

      final message = ChatMessage(
        id: '',
        senderId: currentUser.uid,
        senderName: currentUser.displayName ?? 'Captain',
        senderRole: 'driver',
        content: content,
        timestamp: DateTime.now(),
        readBy: [currentUser.uid], // Driver automatically reads their own message
      );

      // Add message to the Ride's messages collection
      await _firestore
          .collection('Rides')
          .doc(rideId)
          .collection('Messages')
          .add(message.toMap());

      print('[2025-06-05 20:02:01] [Lilydebug] Message added to Ride Messages collection');

      // Update Ride document with last message info
      Map<String, dynamic> rideData = {
        'lastMessage': content,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUser.uid,
        'lastMessageSenderRole': 'driver',
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'currentTimestamp': _currentTimestamp,
        'currentUserLogin': _currentUserLogin,
      };

      await _firestore.collection('Rides').doc(rideId).set(
          rideData,
          SetOptions(merge: true)
      );

      print('[2025-06-05 20:02:01] [Lilydebug] Ride document updated with last message');

      // Handle notifications and unread counts
      DocumentSnapshot rideDoc = await _firestore.collection('Rides').doc(rideId).get();
      if (rideDoc.exists && rideDoc.data() != null) {
        final Map<String, dynamic> existingRideData = rideDoc.data() as Map<String, dynamic>;

        // If passenger exists, send notification and increment unread count
        if (existingRideData.containsKey('passengerId')) {
          final passengerId = existingRideData['passengerId'];

          print('[2025-06-05 20:02:01] [Lilydebug] Sending notification to passenger: $passengerId');

          // Create notification for passenger
          await _firestore.collection('Notifications').add({
            'userId': passengerId,
            'title': 'New message from your driver',
            'body': content,
            'type': 'chat',
            'data': {
              'rideId': rideId,
              'passengerRequestId': passengerRequestId,
              'senderRole': 'driver',
              'senderName': currentUser.displayName ?? 'Your Driver',
            },
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'currentTimestamp': _currentTimestamp,
            'currentUserLogin': _currentUserLogin,
          });

          // Update passenger unread count
          await _firestore.collection('Rides').doc(rideId).set({
            'passengerUnreadCount': FieldValue.increment(1),
          }, SetOptions(merge: true));

          print('[2025-06-05 20:02:01] [Lilydebug] Passenger notification sent and unread count updated');
        }
      }
    } catch (e) {
      print('[2025-06-05 20:02:01] [Lilydebug] Error sending message: $e');
      rethrow;
    }
  }

  // Mark messages as read for the current driver
  Future<void> markMessagesAsRead(String passengerRequestId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      print('[2025-06-05 20:02:01] [Lilydebug] Marking messages as read for PassengerRequest: $passengerRequestId');

      // Get the Ride document ID
      String rideId = await _ensureRideDocumentExists(passengerRequestId);

      // Reset driver unread count
      await _firestore.collection('Rides').doc(rideId).set({
        'driverUnreadCount': 0,
        'lastReadByDriver': FieldValue.serverTimestamp(),
        'currentTimestamp': _currentTimestamp,
        'currentUserLogin': _currentUserLogin,
      }, SetOptions(merge: true));

      // Find all unread messages sent by the passenger
      QuerySnapshot unreadMessages = await _firestore
          .collection('Rides')
          .doc(rideId)
          .collection('Messages')
          .where('senderRole', isEqualTo: 'passenger')
          .get();

      print('[2025-06-05 20:02:01] [Lilydebug] Found ${unreadMessages.docs.length} passenger messages to mark as read');

      // Create a batch to update all messages at once
      WriteBatch batch = _firestore.batch();

      for (var doc in unreadMessages.docs) {
        final Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        final List<dynamic> readBy = List<dynamic>.from(data?['readBy'] ?? []);
        if (!readBy.contains(currentUser.uid)) {
          readBy.add(currentUser.uid);
          batch.update(doc.reference, {
            'readBy': readBy,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // Commit the batch
      await batch.commit();

      print('[2025-06-05 20:02:01] [Lilydebug] All passenger messages marked as read');
    } catch (e) {
      print('[2025-06-05 20:02:01] [Lilydebug] Error marking messages as read: $e');
    }
  }

  // Get unread message count for driver
  Stream<int> getUnreadMessageCount(String passengerRequestId) async* {
    try {
      // Get the Ride document ID
      String rideId = await _ensureRideDocumentExists(passengerRequestId);

      yield* _firestore
          .collection('Rides')
          .doc(rideId)
          .snapshots()
          .map((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data() as Map<String, dynamic>;
          final count = data['driverUnreadCount'] ?? 0;
          return count is int ? count : 0;
        }
        return 0;
      });
    } catch (e) {
      yield 0;
    }
  }

  // Get current user ID
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  // Get current user name
  String getCurrentUserName() {
    final user = _auth.currentUser;
    return user?.displayName ?? 'Captain';
  }

  // Get current user role (always driver for this app)
  String getCurrentUserRole() {
    return 'driver';
  }
}