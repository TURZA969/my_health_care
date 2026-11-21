import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart'; // 👈 প্লাগিন/timezone import এখন এখানে লাগবে না

class MedicineReminderScreen extends StatefulWidget {
  const MedicineReminderScreen({super.key});

  @override
  State<MedicineReminderScreen> createState() => _MedicineReminderScreenState();
}

class _MedicineReminderScreenState extends State<MedicineReminderScreen> {
  // ❌ FlutterLocalNotificationsPlugin, initState/_initNotifications,
  //    _configureLocalTimeZone, _scheduleNotification — সব বাদ, NotificationService-এ চলে গেছে

  Future<void> _testNotification() async {
    await NotificationService.showTestNotification();
  }

  Future<void> _testScheduledNotification() async {
    await NotificationService.scheduleTestNotification();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scheduled! Wait 10 seconds and minimize the app.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  CollectionReference get remindersRef {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('reminders');
  }

  Future<void> _showAddReminderSheet() async {
    final nameController = TextEditingController();
    int frequency = 1;
    String mealTiming = 'After Meal';
    List<TimeOfDay> times = [const TimeOfDay(hour: 8, minute: 0)];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20, right: 20, top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Add Medicine Reminder',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Medicine Name',
                    prefixIcon: const Icon(Icons.medication, color: Color(0xFF6C5CE7)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('How many times per day?',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [1, 2, 3].map((freq) {
                    final isSelected = frequency == freq;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setModalState(() {
                            frequency = freq;
                            if (times.length < freq) {
                              while (times.length < freq) {
                                times.add(const TimeOfDay(hour: 12, minute: 0));
                              }
                            } else {
                              times = times.sublist(0, freq);
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF6C5CE7) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF6C5CE7) : Colors.grey.shade300,
                            ),
                          ),
                          child: Text('$freq${freq == 1 ? ' time' : ' times'}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.black87,
                              )),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                const Text('Select Times',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                ...List.generate(times.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: times[index],
                        );
                        if (picked != null) {
                          setModalState(() => times[index] = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EEFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, color: Color(0xFF6C5CE7), size: 18),
                            const SizedBox(width: 8),
                            Text('Dose ${index + 1}: ${times[index].format(context)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),

                const Text('Timing',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => mealTiming = 'Before Meal'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: mealTiming == 'Before Meal' ? const Color(0xFF6C5CE7) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF6C5CE7)),
                          ),
                          child: Text('Before Meal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold,
                                color: mealTiming == 'Before Meal' ? Colors.white : const Color(0xFF6C5CE7),
                              )),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => mealTiming = 'After Meal'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: mealTiming == 'After Meal' ? const Color(0xFF6C5CE7) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF6C5CE7)),
                          ),
                          child: Text('After Meal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold,
                                color: mealTiming == 'After Meal' ? Colors.white : const Color(0xFF6C5CE7),
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter medicine name!'), backgroundColor: Colors.red),
                        );
                        return;
                      }

                      final docRef = await remindersRef.add({
                        'medicineName': nameController.text.trim(),
                        'frequency': frequency,
                        'mealTiming': mealTiming,
                        'times': times.map((t) => '${t.hour}:${t.minute}').toList(),
                        'takenToday': List.filled(frequency, false),
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      // 👇 এখন NotificationService দিয়ে schedule করা হচ্ছে
                      for (int i = 0; i < times.length; i++) {
                        final id = NotificationService.safeNotificationId(docRef.id, i);
                        try {
                          await NotificationService.scheduleNotification(
                            id: id,
                            title: 'Medicine Time! 💊',
                            body: 'Time to take ${nameController.text.trim()} ($mealTiming)',
                            hour: times[i].hour,
                            minute: times[i].minute,
                          );
                        } catch (e) {
                          debugPrint('FAILED to schedule notification id=$id: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Could not schedule reminder: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reminder saved and scheduled!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save Reminder',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _markAsTaken(String docId, int doseIndex, List<dynamic> takenToday) async {
    final updated = List<bool>.from(takenToday);
    updated[doseIndex] = true;
    await remindersRef.doc(docId).update({'takenToday': updated});
  }

  Future<void> _deleteReminder(String docId) async {
    await remindersRef.doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C5CE7),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Medicine Reminder',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Test instant notification',
            onPressed: _testNotification,
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Test scheduled notification (10s)',
            onPressed: _testScheduledNotification,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: remindersRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)));
          }

          final reminders = snapshot.data!.docs;
          int totalDoses = 0;
          int takenDoses = 0;

          for (final doc in reminders) {
            final data = doc.data() as Map<String, dynamic>;
            final taken = List<bool>.from(data['takenToday'] ?? []);
            totalDoses += taken.length;
            takenDoses += taken.where((t) => t).length;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Medicine Reminder',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                              Text('Today\'s Schedule',
                                  style: TextStyle(fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _statBox('$totalDoses', 'Total')),
                          const SizedBox(width: 10),
                          Expanded(child: _statBox('$takenDoses', 'Taken')),
                          const SizedBox(width: 10),
                          Expanded(child: _statBox('${totalDoses - takenDoses}', 'Pending')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text('Active Reminders',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 12),

                if (reminders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        Text('💊', style: TextStyle(fontSize: 40)),
                        SizedBox(height: 10),
                        Text('No reminders yet', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                else
                  ...reminders.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final times = List<String>.from(data['times'] ?? []);
                    final taken = List<bool>.from(data['takenToday'] ?? []);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 46, height: 46,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0EEFF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Center(child: Text('💊', style: TextStyle(fontSize: 22))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(data['medicineName'] ?? '',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    Text('${data['frequency']}x daily • ${data['mealTiming']}',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _deleteReminder(doc.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(times.length, (i) {
                              final isTaken = i < taken.length ? taken[i] : false;
                              final parts = times[i].split(':');
                              final timeOfDay = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));

                              return GestureDetector(
                                onTap: isTaken ? null : () => _markAsTaken(doc.id, i, taken),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isTaken ? const Color(0xFFE8FAF5) : const Color(0xFFF0EEFF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isTaken ? Icons.check_circle : Icons.access_time,
                                        size: 14,
                                        color: isTaken ? const Color(0xFF00B894) : const Color(0xFF6C5CE7),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        timeOfDay.format(context),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isTaken ? const Color(0xFF00B894) : const Color(0xFF6C5CE7),
                                        ),
                                      ),
                                      if (!isTaken) ...[
                                        const SizedBox(width: 6),
                                        const Text('Tap to take',
                                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReminderSheet,
        backgroundColor: const Color(0xFF6C5CE7),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Reminder', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _statBox(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }
}