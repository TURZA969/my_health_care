import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'order_medicine_screen.dart';

/// Home screen এ add করার জন্য widget
/// তোমার existing home screen এ যেখানে দেখাতে চাও সেখানে রাখো:
/// const MedicineHomeSection()
class MedicineHomeSection extends StatefulWidget {
  const MedicineHomeSection({super.key});

  @override
  State<MedicineHomeSection> createState() => _MedicineHomeSectionState();
}

class _MedicineHomeSectionState extends State<MedicineHomeSection> {
  List<Map<String, dynamic>> _medicines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRandomMedicines();
  }

  Future<void> _loadRandomMedicines() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('medicines').get();

      final all =
          snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();

      // Random shuffle করে প্রথম ৮টা নাও
      all.shuffle(Random());
      setState(() {
        _medicines = all.take(8).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Category অনুযায়ী color
  Color _categoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'tablet':
        return const Color(0xFF00B894);
      case 'capsule':
        return const Color(0xFF0984E3);
      case 'syrup':
        return const Color(0xFFFDCB6E);
      case 'drop':
        return const Color(0xFF6C5CE7);
      case 'injection':
        return const Color(0xFFD63031);
      case 'cream':
      case 'ointment':
        return const Color(0xFF00CEC9);
      default:
        return const Color(0xFFE17055);
    }
  }

  // Category অনুযায়ী icon
  String _categoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'tablet':
        return '💊';
      case 'capsule':
        return '💉';
      case 'syrup':
        return '🍶';
      case 'drop':
        return '💧';
      case 'injection':
        return '🩺';
      case 'cream':
      case 'ointment':
        return '🧴';
      default:
        return '💊';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💊 Available Medicines',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E))),
                  Text('Order at your doorstep',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const OrderMedicineScreen()),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF0EC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('See All →',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE17055))),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Medicine Grid ──
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Color(0xFFE17055)),
            ),
          )
        else if (_medicines.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No medicines available',
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _medicines.length,
              itemBuilder: (context, index) {
                final med = _medicines[index];
                final color = _categoryColor(med['category']);
                final icon = _categoryIcon(med['category']);

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const OrderMedicineScreen()),
                  ),
                  child: Container(
                    width: 130,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon badge
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child:
                                Text(icon, style: const TextStyle(fontSize: 22)),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Name
                        Text(
                          med['name'] ?? '',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // Category chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            med['category'] ?? '',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: color),
                          ),
                        ),
                        const Spacer(),

                        // Price
                        Text(
                          '৳${med['price'] ?? 0}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: color),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),

        // ── Order Now Banner ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrderMedicineScreen()),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE17055), Color(0xFFFDCB6E)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Text('🏥', style: TextStyle(fontSize: 28)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Upload Prescription',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text('AI scan করে medicine detect করবে!',
                            style:
                                TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}