import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../providers/auth_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String passengerName;
  final String passengerImage;

  const ChatScreen({
    Key? key,
    required this.rideId,
    required this.passengerName,
    required this.passengerImage,
  }) : super(key: key);

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Mark messages as read when screen opens
    _chatService.markMessagesAsRead(widget.rideId);

    print('[2025-06-05 19:51:19] [Lilydebug] Driver ChatScreen opened for ride: ${widget.rideId}');
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get current user info from auth provider
    final authState = ref.watch(authProvider);
    final currentUserId = ref.read(authProvider.notifier).currentUserId ??
        FirebaseAuth.instance.currentUser?.uid ?? 'driver123';

    // Get driver image from auth state if available
    final driverImage = authState.user?.photoURL ??
        'https://randomuser.me/api/portraits/men/32.jpg';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF222222),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(widget.passengerImage),
              radius: 16,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.passengerName,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    'Passenger',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Unread count indicator
          StreamBuilder<int>(
            stream: _chatService.getUnreadMessageCount(widget.rideId),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount > 0) {
                return Container(
                  margin: EdgeInsets.only(right: 16),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFFFF4B6C),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Container(
        color: Color(0xFF111111),
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _chatService.getChatMessages(widget.rideId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(color: Color(0xFFFF4B6C))
                    );
                  }

                  if (snapshot.hasError) {
                    print('[2025-06-05 19:51:19] [Lilydebug] Error loading messages: ${snapshot.error}');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 48),
                          SizedBox(height: 16),
                          Text(
                            'Error loading messages',
                            style: TextStyle(color: Colors.white),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => setState(() {}),
                            child: Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.white54,
                            size: 64,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.white70, fontSize: 18),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Say hi to ${widget.passengerName}!',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isFromDriver = message.senderRole == 'driver';
                      final isFromCurrentUser = message.senderId == currentUserId;

                      // Determine if message is read
                      bool isRead = false;
                      if (isFromCurrentUser && message.senderRole == 'driver') {
                        // If I'm the driver and sent this, check if passenger read it
                        // We'll check for passenger in readBy array (you may need to adjust this logic)
                        isRead = message.readBy.length > 1; // More than just the sender
                      } else {
                        // If passenger sent it, mark as read since we're viewing it
                        isRead = true;
                      }

                      return Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: isFromDriver
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isFromDriver) ...[
                              CircleAvatar(
                                backgroundImage: NetworkImage(widget.passengerImage),
                                radius: 16,
                                onBackgroundImageError: (_, __) {},
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              SizedBox(width: 8),
                            ],
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.7
                              ),
                              decoration: BoxDecoration(
                                color: isFromDriver
                                    ? Color(0xFFFF4B6C)
                                    : Color(0xFF333333),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(18),
                                  topRight: Radius.circular(18),
                                  bottomLeft: Radius.circular(isFromDriver ? 18 : 4),
                                  bottomRight: Radius.circular(isFromDriver ? 4 : 18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isFromCurrentUser) ...[
                                    Text(
                                      message.senderName,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                  ],
                                  Text(
                                    message.content,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatDateTime(message.timestamp),
                                        style: TextStyle(
                                          color: isFromDriver
                                              ? Colors.white70
                                              : Colors.white60,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (isFromCurrentUser) ...[
                                        SizedBox(width: 6),
                                        Icon(
                                          isRead ? Icons.done_all : Icons.done,
                                          size: 14,
                                          color: isRead
                                              ? Colors.lightBlueAccent
                                              : Colors.white70,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isFromDriver) ...[
                              SizedBox(width: 8),
                              CircleAvatar(
                                backgroundImage: NetworkImage(driverImage),
                                radius: 16,
                                onBackgroundImageError: (_, __) {},
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Message input
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Color(0xFF222222),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.emoji_emotions, color: Colors.white70),
                    onPressed: () {
                      // Emoji picker could be implemented here
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Emoji picker coming soon!')),
                      );
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: TextStyle(color: Colors.white),
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Color(0xFF333333),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFFF4B6C),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isLoading
                          ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Icon(Icons.send, color: Colors.white),
                      onPressed: _isLoading ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('[2025-06-05 19:51:19] [Lilydebug] Sending message: "$messageText" to ride: ${widget.rideId}');

      // Clear input immediately for better UX
      final textToSend = messageText;
      _messageController.clear();

      // Send message using your existing ride ID
      await _chatService.sendMessage(widget.rideId, textToSend);

      print('[2025-06-05 19:51:19] [Lilydebug] Message sent successfully');

    } catch (e) {
      print('[2025-06-05 19:51:19] [Lilydebug] Error sending message: $e');

      // Restore the message text if sending failed
      _messageController.text = messageText;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message. Please try again.'),
          backgroundColor: Colors.red.shade700,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              // Retry sending
              _sendMessage();
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (messageDate == yesterday) {
      return 'Yesterday, ${DateFormat('HH:mm').format(dateTime)}';
    } else if (now.difference(dateTime).inDays < 7) {
      return '${DateFormat('EEE').format(dateTime)}, ${DateFormat('HH:mm').format(dateTime)}';
    } else {
      return '${DateFormat('MMM d').format(dateTime)}, ${DateFormat('HH:mm').format(dateTime)}';
    }
  }
}