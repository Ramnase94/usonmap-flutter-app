
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _sending = false;

  // Messages will be stored in a single private chat room.
  static const String _chatRoomId = 'private_chat';

  Future<void> _sendMessage() async {
    final user = _auth.currentUser;
    final message = _messageController.text.trim();

    if (user == null || message.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _firestore
          .collection('private_chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add({
        'text': message,
        'senderId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _messageController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Message पाठवता आला नाही. Security Rules तपासा.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Private Chat')),
        body: const Center(
          child: Text('कृपया आधी Login करा.'),
        ),
      );
    }

    final messagesQuery = _firestore
        .collection('private_chats')
        .doc(_chatRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Chat ❤️'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messagesQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'चॅट उपलब्ध नाही. Security Rules तपासा.',
                    ),
                  );
                }

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return const Center(
                    child: Text('पहिला संदेश पाठवा ❤️'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final isMine = data['senderId'] == user.uid;
                    final text = data['text'] as String? ?? '';

                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: const BoxConstraints(
                          maxWidth: 280,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMine
                                ? Theme.of(context)
                                    .colorScheme
                                    .onPrimary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization:
                          TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'संदेश लिहा...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                    tooltip: 'संदेश पाठवा',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
