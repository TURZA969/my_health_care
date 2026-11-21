import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dashboard_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  String selectedBloodGroup = 'A+';
  bool isLoading = false;
  bool isLocationLoading = false;
  String errorMessage = '';
  File? profileImage;
  final ImagePicker _picker = ImagePicker();

  final List<String> bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];

  Future<void> pickImage() async {
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
            const Text('Select Profile Picture',
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
                      setState(() => profileImage = File(image.path));
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
                      setState(() => profileImage = File(image.path));
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

  Future<void> getLiveLocation() async {
    setState(() => isLocationLoading = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            errorMessage = 'Location permission denied!';
            isLocationLoading = false;
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address =
            '${place.subLocality}, ${place.locality}, ${place.administrativeArea}';
        setState(() => addressController.text = address);
      }
    } catch (e) {
      setState(() => errorMessage = 'Could not get location!');
    } finally {
      setState(() => isLocationLoading = false);
    }
  }

  Future<void> saveProfile() async {
    if (nameController.text.isEmpty ||
        phoneController.text.isEmpty ||
        addressController.text.isEmpty) {
      setState(() => errorMessage = 'Please fill in all fields!');
      return;
    }

    if (phoneController.text.length < 11) {
      setState(() => errorMessage = 'Please enter a valid phone number!');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      String imageUrl = '';
      if (profileImage != null) {
        final bytes = await profileImage!.readAsBytes();
        imageUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .set({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'bloodGroup': selectedBloodGroup,
        'address': addressController.text.trim(),
        'email': user.email,
        'profileImage': imageUrl,
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      setState(() => errorMessage = 'Something went wrong!');
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
            begin: Alignment.topCenter,
            end: Alignment.center,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.person_add, size: 55, color: Colors.white),
              const SizedBox(height: 8),
              const Text('Setup Your Profile',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 5),
              const Text('Please fill in your details',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(25, 25, 25, 10),
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
                        // Profile Picture
                        Center(
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: profileImage != null
                                    ? FileImage(profileImage!)
                                    : null,
                                child: profileImage == null
                                    ? const Icon(Icons.person,
                                        size: 60, color: Colors.grey)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: pickImage,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0077B6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Full Name
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person_outline,
                                color: Color(0xFF0077B6)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0077B6), width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),

                        // Phone Number
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: const Icon(Icons.phone_outlined,
                                color: Color(0xFF0077B6)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0077B6), width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),

                        // Blood Group
                        DropdownButtonFormField<String>(
                          value: selectedBloodGroup,
                          decoration: InputDecoration(
                            labelText: 'Blood Group',
                            prefixIcon: const Icon(Icons.bloodtype_outlined,
                                color: Color(0xFF0077B6)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0077B6), width: 2),
                            ),
                          ),
                          items: bloodGroups
                              .map((bg) => DropdownMenuItem(
                                  value: bg, child: Text(bg)))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => selectedBloodGroup = value!),
                        ),
                        const SizedBox(height: 15),

                        // Address
                        TextField(
                          controller: addressController,
                          decoration: InputDecoration(
                            labelText: 'Address',
                            prefixIcon: const Icon(Icons.location_on_outlined,
                                color: Color(0xFF0077B6)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0077B6), width: 2),
                            ),
                            suffixIcon: isLocationLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.my_location,
                                        color: Color(0xFF0077B6)),
                                    onPressed: getLiveLocation,
                                    tooltip: 'Use Live Location',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '📍 Tap the location icon to auto-fill your address',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),

                        if (errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 10),
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
                        ],

                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0077B6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)
                                : const Text('Save & Continue',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 20),
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