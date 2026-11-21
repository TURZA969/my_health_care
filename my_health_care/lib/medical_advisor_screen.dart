import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MedicalAdvisorScreen extends StatefulWidget {
  const MedicalAdvisorScreen({super.key});

  @override
  State<MedicalAdvisorScreen> createState() => _MedicalAdvisorScreenState();
}

class _MedicalAdvisorScreenState extends State<MedicalAdvisorScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  String _userName = 'there';

  // API key সরানো হয়েছে। অ্যাপ চালাতে নিচে নিজের নতুন কী বসান, কিন্তু সেই অবস্থায় GitHub-এ পুশ করবেন না।
  final String _apiKey = 'YOUR_GROQ_API_KEY';
  final String _apiUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Text model
  final String _textModel = 'openai/gpt-oss-120b';
  // Vision model (image analysis) - must be a Groq model that supports
  // image_url inputs
  final String _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final name = doc.data()?['name'] ?? 'there';
        final firstName = name.split(' ')[0];
        setState(() {
          _userName = firstName;
          _messages.add({
            'role': 'assistant',
            'text': 'Hello, $_userName! 👋\n\nI\'m your AI Medical Advisor. How can I help you today?\n\nYou can:\n• Describe your symptoms\n• Send a photo for analysis\n• Ask any health related question'
          });
        });
      }
    }
  }

  Future<void> _sendMessage(String userMessage) async {
    if (userMessage.trim().isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': userMessage});
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      final url = Uri.parse(_apiUrl);

      final body = jsonEncode({
        "model": _textModel,
        "messages": [
          {
            "role": "system",
            "content":
                "You are a professional medical advisor for the My Health Care app. The user's name is $_userName. Always address them by their first name in a friendly way. Help users understand their symptoms, suggest possible conditions, recommend specialist doctors, suggest lab tests if needed, and provide general health advice. Always remind users that your advice does not replace professional medical consultation. If symptoms seem serious or life-threatening, immediately advise to seek emergency care. Keep responses concise and easy to understand."
          },
          {
            "role": "user",
            "content": userMessage
          }
        ],
        "temperature": 0.7,
        "max_tokens": 1024
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices'][0]['message']['content'] ?? 'No response';
        setState(() {
          _messages.add({'role': 'assistant', 'text': text});
          _isLoading = false;
        });
      } else {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'text': 'Error: ${response.statusCode} - ${response.body}. Please try again.'
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'Connection error. Please check your internet and try again.'
        });
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  Future<void> _sendImageMessage() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Send Image',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await _picker.pickImage(
                        source: ImageSource.camera, imageQuality: 70);
                    if (image != null) {
                      await _sendImageToGemini(File(image.path));
                    }
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Color(0xFF0077B6), size: 30),
                      ),
                      const SizedBox(height: 8),
                      const Text('Camera'),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await _picker.pickImage(
                        source: ImageSource.gallery, imageQuality: 70);
                    if (image != null) {
                      await _sendImageToGemini(File(image.path));
                    }
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library,
                            color: Color(0xFF0077B6), size: 30),
                      ),
                      const SizedBox(height: 8),
                      const Text('Gallery'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _sendImageToGemini(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    setState(() {
      _messages.add({'role': 'user', 'text': '📷 Image sent for analysis'});
      _selectedImage = imageFile;
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final url = Uri.parse(_apiUrl);

      final body = jsonEncode({
        "model": _visionModel,
        "messages": [
          {
            "role": "system",
            "content":
                "You are a professional medical advisor. The user's name is $_userName. Always address them by their first name. Analyze the image and provide medical advice. Always remind users to consult a real doctor."
          },
          {
            "role": "user",
            "content": [
              {
                "type": "text",
                "text": "Please analyze this medical image and provide advice."
              },
              {
                "type": "image_url",
                "image_url": {
                  "url": "data:image/jpeg;base64,$base64Image"
                }
              }
            ]
          }
        ],
        "temperature": 0.7,
        "max_tokens": 1024
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices'][0]['message']['content'] ?? 'No response';
        setState(() {
          _messages.add({'role': 'assistant', 'text': text});
          _isLoading = false;
        });
      } else {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'text': 'Could not analyze image. Error: ${response.statusCode}. Please try again.'
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'Connection error. Please try again.'
        });
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0077B6),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 18,
              child: Icon(Icons.headset_mic, color: Color(0xFF0077B6), size: 20),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Medical Advisor',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text('AI Powered • Always Available',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Disclaimer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            color: const Color(0xFFFFF3CD),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI advice does not replace professional medical consultation.',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),

          // Chat
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(15),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isLoading) {
                  return _buildTypingIndicator();
                }
                final message = _messages[index];
                return _buildMessageBubble(
                  message['text']!,
                  message['role'] == 'user',
                );
              },
            ),
          ),

          // Quick Symptoms
          if (_messages.length <= 1)
            Container(
              height: 50,
              padding: const EdgeInsets.only(bottom: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                children: [
                  'Fever & Headache',
                  'Chest Pain',
                  'Stomach Ache',
                  'Cough & Cold',
                  'Back Pain',
                ]
                    .map((symptom) => GestureDetector(
                          onTap: () =>
                              _sendMessage('I have $symptom, what should I do?'),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF0077B6)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(symptom,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF0077B6))),
                          ),
                        ))
                    .toList(),
              ),
            ),

          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 15),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Describe your symptoms...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFFF0F4F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendImageMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00B4D8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_a_photo,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _sendMessage(_messageController.text),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0077B6),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF0077B6),
              child: Icon(Icons.headset_mic, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF0077B6) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: isUser ? Colors.white : const Color(0xFF1A1A2E),
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF00B4D8),
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFF0077B6),
            child: Icon(Icons.headset_mic, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                _DotAnimation(delay: 0),
                SizedBox(width: 4),
                _DotAnimation(delay: 300),
                SizedBox(width: 4),
                _DotAnimation(delay: 600),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DotAnimation extends StatefulWidget {
  final int delay;
  const _DotAnimation({required this.delay});

  @override
  State<_DotAnimation> createState() => _DotAnimationState();
}

class _DotAnimationState extends State<_DotAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF0077B6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}