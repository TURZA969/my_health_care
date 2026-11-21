import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

// NOTE: this file now depends on two extra packages. Add to pubspec.yaml:
//   firebase_storage: ^12.0.0
//   image_picker: ^1.1.0
// (versions are indicative — use whatever's compatible with your other
// firebase_* package versions)

/// Chat thread between the user and ONE specific hospital's admin/support team.
///
/// Firestore structure used:
///   hospitals/{hospitalId}/chats/{userId}                 -> metadata (lastMessage, unreadByAdmin, userName, topic)
///   hospitals/{hospitalId}/chats/{userId}/messages/{id}    -> { text, imageUrl, senderId, isAdmin, createdAt }
///
/// Storage structure used:
///   chat_images/{hospitalId}/{userId}/{timestamp}.jpg
///
/// `topic` is purely a label (Appointment / Lab Test / Medicine Order) shown
/// so both sides know what the conversation is about — the hospital still
/// has just ONE thread per user regardless of topic, since the same admin
/// handles appointments and lab tests for that hospital.
///
/// Each hospital's admin dashboard only reads/writes under its OWN
/// hospitals/{theirHospitalId}/chats/* path. Enforce with a security rule like:
///
///   match /hospitals/{hospitalId}/chats/{userId}/{document=**} {
///     allow read, write: if request.auth.uid == userId
///       || (isAdmin(request.auth.uid) && getAdminHospitalId(request.auth.uid) == hospitalId);
///   }
class HospitalChatScreen extends StatefulWidget {
  final String hospitalId;
  final String hospitalName;
  final String? topic;

  const HospitalChatScreen({
    super.key,
    required this.hospitalId,
    required this.hospitalName,
    this.topic,
  });

  @override
  State<HospitalChatScreen> createState() => _HospitalChatScreenState();
}

class _HospitalChatScreenState extends State<HospitalChatScreen> {
  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kPrimaryLight = Color(0xFF00B4D8);
  static const Color kOnline = Color(0xFF00B894);
  static const Color kBgTop = Color(0xFFEAF6FB);
  static const Color kBgBottom = Color(0xFFF6FBFD);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  String? _userId;
  String _userName = 'You';
  bool _sending = false;
  bool _uploadingImage = false;
  bool _deletingChat = false;

  DocumentReference<Map<String, dynamic>> get _chatRef => _firestore
      .collection('hospitals')
      .doc(widget.hospitalId)
      .collection('chats')
      .doc(_userId);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userId = user?.uid;
    _initChatDoc();
  }

  Future<void> _initChatDoc() async {
    if (_userId == null) return;
    final userDoc = await _firestore.collection('users').doc(_userId).get();
    final data = userDoc.data();
    _userName = data?['name'] ?? 'User';

    final chatSnap = await _chatRef.get();
    if (!chatSnap.exists) {
      await _chatRef.set({
        'userId': _userId,
        'userName': _userName,
        'hospitalId': widget.hospitalId,
        'hospitalName': widget.hospitalName,
        'topic': widget.topic,
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByAdmin': 0,
        'unreadByUser': 0,
      });
    } else if (widget.topic != null) {
      // keep the topic label fresh to whatever the user most recently picked
      await _chatRef.set({'topic': widget.topic}, SetOptions(merge: true));
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _userId == null || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      await _chatRef.collection('messages').add({
        'text': text,
        'imageUrl': null,
        'senderId': _userId,
        'isAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _chatRef.set({
        'userId': _userId,
        'userName': _userName,
        'hospitalId': widget.hospitalId,
        'hospitalName': widget.hospitalName,
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByAdmin': FieldValue.increment(1),
      }, SetOptions(merge: true));

      _scrollToBottom();
    } catch (e) {
      _showSnack('Message could not be sent. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_userId == null || _uploadingImage) return;
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploadingImage = true);
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('chat_images')
          .child(widget.hospitalId)
          .child(_userId!)
          .child(fileName);

      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();

      await _chatRef.collection('messages').add({
        'text': '',
        'imageUrl': url,
        'senderId': _userId,
        'isAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _chatRef.set({
        'userId': _userId,
        'userName': _userName,
        'hospitalId': widget.hospitalId,
        'hospitalName': widget.hospitalName,
        'lastMessage': '\u{1F4F7} Photo',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadByAdmin': FieldValue.increment(1),
      }, SetOptions(merge: true));

      _scrollToBottom();
    } catch (e) {
      _showSnack('Image could not be sent. Try again.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await _confirm(
      title: 'Delete message?',
      message: 'This message will be permanently deleted for everyone.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true) return;

    try {
      await _chatRef.collection('messages').doc(messageId).delete();
    } catch (e) {
      _showSnack('Could not delete message.');
    }
  }

  Future<void> _deleteWholeChat() async {
    final confirmed = await _confirm(
      title: 'Delete entire conversation?',
      message: 'All messages with ${widget.hospitalName} will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete all',
    );
    if (confirmed != true) return;

    setState(() => _deletingChat = true);
    try {
      // delete messages in batches of 400 (Firestore batch limit is 500)
      const batchSize = 400;
      while (true) {
        final snap = await _chatRef.collection('messages').limit(batchSize).get();
        if (snap.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        if (snap.docs.length < batchSize) break;
      }
      await _chatRef.delete();

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Could not delete the conversation.');
      if (mounted) setState(() => _deletingChat = false);
    }
  }

  Future<bool?> _confirm({required String title, required String message, required String confirmLabel}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    return DateFormat('h:mm a').format(ts.toDate());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to start a chat.')),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kBgTop, kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _chatRef
                      .collection('messages')
                      .orderBy('createdAt', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('Could not load messages.'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: kPrimary));
                    }

                    final docs = snapshot.data!.docs;

                    if (docs.isEmpty) {
                      return _EmptyChatState(hospitalName: widget.hospitalName, topic: widget.topic);
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final isAdmin = data['isAdmin'] == true;
                        final text = data['text'] ?? '';
                        final imageUrl = data['imageUrl'] as String?;
                        final ts = data['createdAt'] as Timestamp?;
                        final showDateHeader = _shouldShowDateHeader(docs, index);
                        final isMine = !isAdmin;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (showDateHeader && ts != null) _dateHeader(ts),
                            Align(
                              alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                              child: GestureDetector(
                                onLongPress: isMine ? () => _deleteMessage(doc.id) : null,
                                child: _MessageBubble(
                                  isAdmin: isAdmin,
                                  text: text,
                                  imageUrl: imageUrl,
                                  time: _formatTime(ts),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimary, kPrimaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Color(0x330077B6), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: Icon(Icons.local_hospital, color: kPrimary, size: 18),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: kOnline,
                    shape: BoxShape.circle,
                    border: Border.all(color: kPrimary, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.hospitalName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Text('Online', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    if (widget.topic != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(widget.topic!, style: const TextStyle(color: Colors.white, fontSize: 9.5)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          _deletingChat
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (value) {
                    if (value == 'delete_chat') _deleteWholeChat();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'delete_chat',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                          SizedBox(width: 8),
                          Text('Delete conversation'),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  bool _shouldShowDateHeader(List<QueryDocumentSnapshot> docs, int index) {
    if (index == 0) return true;
    final current = docs[index].data() as Map<String, dynamic>;
    final previous = docs[index - 1].data() as Map<String, dynamic>;
    final currentTs = current['createdAt'] as Timestamp?;
    final previousTs = previous['createdAt'] as Timestamp?;
    if (currentTs == null || previousTs == null) return false;
    final c = currentTs.toDate();
    final p = previousTs.toDate();
    return c.year != p.year || c.month != p.month || c.day != p.day;
  }

  Widget _dateHeader(Timestamp ts) {
    final date = ts.toDate();
    final now = DateTime.now();
    String label;
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day;

    if (isToday) {
      label = 'Today';
    } else if (isYesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMM d, yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        ]),
        child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -3))],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _uploadingImage ? null : _pickAndSendImage,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: _uploadingImage
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary),
                      )
                    : const Icon(Icons.image_outlined, color: kPrimary, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: kBgTop, borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _sendMessage,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [kPrimary, kPrimaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isAdmin;
  final String text;
  final String? imageUrl;
  final String time;

  const _MessageBubble({required this.isAdmin, required this.text, required this.imageUrl, required this.time});

  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kPrimaryLight = Color(0xFF00B4D8);

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: EdgeInsets.all(hasImage ? 6 : 0),
      decoration: BoxDecoration(
        color: isAdmin ? Colors.white : null,
        gradient: isAdmin ? null : const LinearGradient(colors: [kPrimary, kPrimaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isAdmin ? 4 : 16),
          bottomRight: Radius.circular(isAdmin ? 16 : 4),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Padding(
        padding: hasImage ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 180, height: 180,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary)),
                    );
                  },
                  errorBuilder: (ctx, err, st) => const SizedBox(
                    width: 180, height: 120,
                    child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
                  ),
                ),
              ),
            if (!hasImage && text.isNotEmpty)
              Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: isAdmin ? const Color(0xFF1A1A2E) : Colors.white)),
            Padding(
              padding: EdgeInsets.only(top: 4, right: hasImage ? 6 : 0, bottom: hasImage ? 2 : 0),
              child: Text(time, style: TextStyle(fontSize: 10, color: isAdmin ? Colors.grey.shade500 : Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  final String hospitalName;
  final String? topic;
  const _EmptyChatState({required this.hospitalName, required this.topic});

  static const Color kPrimary = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline, color: kPrimary, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Chat with $hospitalName',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 6),
            Text(
              topic != null
                  ? 'Ask about your $topic — their support team usually replies within a few minutes.'
                  : 'Their support team usually replies within a few minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}