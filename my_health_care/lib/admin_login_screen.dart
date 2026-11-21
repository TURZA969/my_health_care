import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool obscurePassword = true;
  String errorMessage = '';

  Future<void> adminSignIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please fill in all fields!');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      // Firestore এ admins collection এ email ও password check করো
      final querySnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .where('email', isEqualTo: email)
          .where('password', isEqualTo: password)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() => errorMessage = 'Invalid admin email or password!');
        return;
      }

      // Admin পাওয়া গেছে, Firebase Auth দিয়েও login করো
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Something went wrong!';
      if (e.code == 'invalid-credential') {
        message = 'Invalid admin email or password!';
      }
      setState(() => errorMessage = message);
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong!');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.admin_panel_settings,
                    size: 70, color: Colors.white),
              ),
              const SizedBox(height: 15),
              const Text('Admin Login',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 5),
              const Text('Restricted Access Only',
                  style: TextStyle(fontSize: 13, color: Colors.white54)),
              const SizedBox(height: 30),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(25, 30, 25, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(35),
                      topRight: Radius.circular(35),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Welcome, Admin 👨‍💼',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        const Text('Enter your admin credentials',
                            style:
                                TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 25),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Admin Email',
                            prefixIcon: const Icon(Icons.email_outlined,
                                color: Color(0xFF1A1A2E)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF1A1A2E), width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline,
                                color: Color(0xFF1A1A2E)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                              onPressed: () => setState(
                                  () => obscurePassword = !obscurePassword),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF1A1A2E), width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        if (errorMessage.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(errorMessage,
                                        style: const TextStyle(
                                            color: Colors.red))),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : adminSignIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A1A2E),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)
                                : const Text('Login as Admin',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This area is restricted to authorized administrators only.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}