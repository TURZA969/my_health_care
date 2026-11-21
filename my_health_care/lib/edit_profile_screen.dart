import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'dart:io';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController nameController;
  late TextEditingController phoneController;
  late TextEditingController addressController;
  late String selectedBloodGroup;
  bool isLoading = false;
  bool isLocationLoading = false;
  String errorMessage = '';
  File? newProfileImage;
  String? existingImageUrl;
  final ImagePicker _picker = ImagePicker();

  final List<String> bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.userData['name'] ?? '');
    phoneController = TextEditingController(text: widget.userData['phone'] ?? '');
    addressController = TextEditingController(text: widget.userData['address'] ?? '');
    selectedBloodGroup = widget.userData['bloodGroup'] ?? 'A+';
    existingImageUrl = widget.userData['profileImage'];
  }

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
                    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
                    if (image != null) setState(() => newProfileImage = File(image.path));
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Color(0xFF0077B6), size: 30),
                      ),
                      const SizedBox(height: 8),
                      const Text('Camera'),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (image != null) setState(() => newProfileImage = File(image.path));
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library, color: Color(0xFF0077B6), size: 30),
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

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = '${place.subLocality}, ${place.locality}, ${place.administrativeArea}';
        setState(() => addressController.text = address);
      }
    } catch (e) {
      setState(() => errorMessage = 'Could not get location!');
    } finally {
      setState(() => isLocationLoading = false);
    }
  }

  Future<void> saveProfile() async {
    if (nameController.text.isEmpty || phoneController.text.isEmpty || addressController.text.isEmpty) {
      setState(() => errorMessage = 'Please fill in all fields!');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      String imageUrl = existingImageUrl ?? '';

      if (newProfileImage != null) {
        final bytes = await newProfileImage!.readAsBytes();
        imageUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'bloodGroup': selectedBloodGroup,
        'address': addressController.text.trim(),
        'profileImage': imageUrl,
      });

      if (mounted) {
        Navigator.pop(context, true);
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
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0077B6),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Edit Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Picture
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: newProfileImage != null
                        ? FileImage(newProfileImage!)
                        : (existingImageUrl != null && existingImageUrl!.isNotEmpty
                            ? MemoryImage(base64Decode(existingImageUrl!.split(',').last))
                            : null) as ImageProvider?,
                    child: (newProfileImage == null && (existingImageUrl == null || existingImageUrl!.isEmpty))
                        ? const Icon(Icons.person, size: 60, color: Colors.grey)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0077B6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Full Name',
                prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF0077B6)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF0077B6)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              initialValue: selectedBloodGroup,
              decoration: InputDecoration(
                labelText: 'Blood Group',
                prefixIcon: const Icon(Icons.bloodtype_outlined, color: Color(0xFF0077B6)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: bloodGroups.map((bg) => DropdownMenuItem(value: bg, child: Text(bg))).toList(),
              onChanged: (value) => setState(() => selectedBloodGroup = value!),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: addressController,
              decoration: InputDecoration(
                labelText: 'Address',
                prefixIcon: const Icon(Icons.location_on_outlined, color: Color(0xFF0077B6)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                suffixIcon: isLocationLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.my_location, color: Color(0xFF0077B6)),
                        onPressed: getLiveLocation,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('📍 Tap the location icon to auto-fill your address',
                style: TextStyle(fontSize: 12, color: Colors.grey)),

            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(errorMessage, style: const TextStyle(color: Colors.red)),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0077B6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}