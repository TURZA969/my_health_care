import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  String currentAddress = 'Detecting location...';
  Position? currentPosition;
  bool isLoadingLocation = true;

  final List<Map<String, dynamic>> nearbyHospitals = [
    {'name': 'Dhaka Medical College Hospital', 'distance': '1.2 km', 'type': 'Government', 'phone': '01711000000'},
    {'name': 'Square Hospital', 'distance': '2.5 km', 'type': 'Private', 'phone': '01711000001'},
    {'name': 'Ibn Sina Hospital', 'distance': '3.1 km', 'type': 'Private', 'phone': '01711000002'},
  ];

  @override
  void initState() {
    super.initState();
    getCurrentLocation();
  }

  Future<void> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          currentPosition = position;
          currentAddress = '${place.subLocality}, ${place.locality}';
          isLoadingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        currentAddress = 'Location unavailable';
        isLoadingLocation = false;
      });
    }
  }

  Future<void> _makeCall(String number) async {
    final Uri uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendSMS() async {
    final lat = currentPosition?.latitude ?? 0;
    final lng = currentPosition?.longitude ?? 0;
    final mapsLink = 'https://maps.google.com/?q=$lat,$lng';
    final message = 'EMERGENCY! I need help. My location: $mapsLink';

    final Uri uri = Uri.parse('sms:?body=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openMaps(String hospitalName) async {
    final query = Uri.encodeComponent(hospitalName);
    final Uri uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _triggerSOS() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning, color: Colors.red),
            ),
            const SizedBox(width: 10),
            const Text('Emergency SOS', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
            'This will share your location and call emergency services. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sendSMS();
              _makeCall('999');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm SOS'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header with SOS Button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 55, 20, 30),
              decoration: const BoxDecoration(
                color: Color(0xFFD63031),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Expanded(
                        child: Text('Emergency Help',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Are you in danger?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 20),

                  // SOS Button
                  GestureDetector(
                    onTap: _triggerSOS,
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3),
                            blurRadius: 0,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🆘', style: TextStyle(fontSize: 38)),
                          const SizedBox(height: 6),
                          const Text('SOS',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFD63031), letterSpacing: 2)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isLoadingLocation)
                        const SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.location_on, color: Colors.white70, size: 14),
                      const SizedBox(width: 6),
                      Text('📍 $currentAddress',
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Call',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(child: _quickCallCard('🚑', '999', 'Ambulance', const Color(0xFFD63031), '999')),
                      const SizedBox(width: 8),
                      Expanded(child: _quickCallCard('👮', '999', 'Police', const Color(0xFF0077B6), '999')),
                      const SizedBox(width: 8),
                      Expanded(child: _quickCallCard('🔥', '199', 'Fire', const Color(0xFFE17055), '199')),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Share Location
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Text('📩', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Share My Location',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                              Text('Send SMS to family',
                                  style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _sendSMS,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD63031),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Send', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Nearby Hospitals',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 12),

                  ...nearbyHospitals.map((hospital) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Text('🏥', style: TextStyle(fontSize: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(hospital['name'],
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                              Text('${hospital['distance']} • ${hospital['type']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _makeCall(hospital['phone']),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD63031),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Call',
                                style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _openMaps(hospital['name']),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0077B6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Map',
                                style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCallCard(String icon, String number, String label, Color color, String phoneNumber) {
    return GestureDetector(
      onTap: () => _makeCall(phoneNumber),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(number, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}