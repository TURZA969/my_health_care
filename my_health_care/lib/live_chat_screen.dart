import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'hospital_chat_screen.dart';
import 'appointment_screen.dart';
// TODO (Lab Test only): if you have a dedicated LabTestScreen, import it
// and swap it in below (_NoBookingState.onPressed) instead of
// AppointmentScreen, so users with 0 lab bookings land on the right
// booking flow. Appointment/Medicine fallback to AppointmentScreen stays
// as-is for now since only Lab Test schema has been verified below.

/// Entry point for Live Chat.
///
/// Flow:
///  1. Greet the signed-in user by name.
///  2. Ask which topic they need help with: Appointment / Lab Test /
///     Medicine Order.
///  3. Work out which hospital(s) are relevant to that topic:
///       - Lab Test          -> `lab_bookings` collection
///       - Appointment       -> `appointments` collection
///       - Medicine Order    -> `appointments` collection (medicine currently
///         piggy-backs on the same hospital admin as appointments)
///  4. 0 hospitals  -> prompt user to book first
///     1 hospital   -> jump straight into that hospital's chat
///     2+ hospitals -> let the user pick which hospital to chat with
///
/// NOTE ON THREADING: a single hospital has ONE chat thread with the user
/// (hospitals/{hospitalId}/chats/{userId}), regardless of topic, since the
/// same admin handles both Appointment and Lab Test for that hospital. The
/// chosen topic is only passed along as a label so the admin/user can see
/// what the conversation was started about — it does NOT create a separate
/// thread. See HospitalChatScreen's `topic` param.
///
/// FIELD NAMES CONFIRMED (verified against actual Firestore data,
/// `lab_bookings/{doc}`):
///   userId          : String  (matches signed-in user's uid)
///   hospitalId      : String
///   hospitalName    : String  (e.g. "Square Hospital")
///   date            : String  ("yyyy-MM-dd", e.g. "2026-06-30")
///   createdAt       : Timestamp
///   status          : String  (e.g. "approved")
///   testName        : String  (e.g. "Blood Sugar")
///   testFee / kitCharge / platformCharge / totalFee : num
///   location        : String
///   paymentMethod / paymentNumber / transactionId   : String
///   reportUrl       : String (may be empty until report is uploaded)
///   statusHistory   : List<Map> (adminId, changedAt, status)
/// -> `_fetchBookedHospitals` only reads userId/hospitalId/hospitalName/
///    date/createdAt, all of which exist as-is, so no changes needed there
///    for Lab Test.
///
/// appointments/{doc}  : { userId, hospitalId, hospitalName, date/createdAt, ... }
///   (not yet verified against real data — adjust if needed)
/// users/{uid}         : { name, ... }
class LiveChatScreen extends StatefulWidget {
  const LiveChatScreen({super.key});

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

enum ChatTopic { appointment, labTest, medicine }

extension on ChatTopic {
  String get label => switch (this) {
        ChatTopic.appointment => 'Appointment',
        ChatTopic.labTest => 'Lab Test',
        ChatTopic.medicine => 'Medicine Order',
      };

  IconData get icon => switch (this) {
        ChatTopic.appointment => Icons.event_available_rounded,
        ChatTopic.labTest => Icons.biotech_rounded,
        ChatTopic.medicine => Icons.medication_rounded,
      };

  String get collection =>
      this == ChatTopic.labTest ? 'lab_bookings' : 'appointments';
}

enum _Step { greeting, topic, hospitalList }

class _LiveChatScreenState extends State<LiveChatScreen> {
  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kPrimaryLight = Color(0xFF00B4D8);
  static const Color kBg = Color(0xFFEAF6FB);

  _Step _step = _Step.greeting;
  ChatTopic? _topic;
  String _userName = '';
  bool _loadingName = true;

  Future<List<_HospitalSummary>>? _hospitalsFuture;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    String name = user?.displayName ?? '';
    if (user != null) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final data = doc.data();
        final fetched = data?['name'] ?? data?['fullName'];
        if (fetched != null && fetched.toString().trim().isNotEmpty) {
          name = fetched.toString();
        }
      } catch (_) {
        // ignore, fall back to whatever we already have
      }
    }
    if (!mounted) return;
    setState(() {
      _userName = name.trim().isEmpty ? 'there' : name.trim().split(' ').first;
      _loadingName = false;
    });
  }

  Future<List<_HospitalSummary>> _fetchBookedHospitals(String collection) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where('userId', isEqualTo: user.uid)
        .get();

    final Map<String, _HospitalSummary> byHospital = {};

    for (final doc in snap.docs) {
      final data = doc.data();
      final hospitalId = data['hospitalId']?.toString();
      final hospitalName = data['hospitalName']?.toString();
      if (hospitalId == null || hospitalId.isEmpty) continue;

      final ts = data['date'] ?? data['createdAt'] ?? data['appointmentDate'];
      DateTime? when;
      if (ts is Timestamp) when = ts.toDate();

      final existing = byHospital[hospitalId];
      if (existing == null ||
          (when != null &&
              (existing.lastVisit == null || when.isAfter(existing.lastVisit!)))) {
        byHospital[hospitalId] = _HospitalSummary(
          hospitalId: hospitalId,
          hospitalName: hospitalName ?? 'Hospital',
          lastVisit: when ?? existing?.lastVisit,
        );
      }
    }

    final list = byHospital.values.toList();
    list.sort((a, b) {
      if (a.lastVisit == null) return 1;
      if (b.lastVisit == null) return -1;
      return b.lastVisit!.compareTo(a.lastVisit!);
    });
    return list;
  }

  void _selectTopic(ChatTopic topic) {
    setState(() {
      _topic = topic;
      _step = _Step.hospitalList;
      _hospitalsFuture = _fetchBookedHospitals(topic.collection);
    });
  }

  void _openHospitalChat(_HospitalSummary hospital) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HospitalChatScreen(
          hospitalId: hospital.hospitalId,
          hospitalName: hospital.hospitalName,
          topic: _topic!.label,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        automaticallyImplyLeading: _step != _Step.greeting,
        leading: _step == _Step.hospitalList
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => setState(() => _step = _Step.topic),
              )
            : (_step == _Step.topic
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() => _step = _Step.greeting),
                  )
                : null),
        title: const Text('Live Chat',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.greeting:
        return _GreetingStep(
          key: const ValueKey('greeting'),
          loading: _loadingName,
          userName: _userName,
          onContinue: () => setState(() => _step = _Step.topic),
        );
      case _Step.topic:
        return _TopicStep(
          key: const ValueKey('topic'),
          onSelect: _selectTopic,
        );
      case _Step.hospitalList:
        return _HospitalListStep(
          key: const ValueKey('hospitals'),
          topic: _topic!,
          future: _hospitalsFuture!,
          onPick: _openHospitalChat,
        );
    }
  }
}

// ───────────────────────── Greeting ─────────────────────────

class _GreetingStep extends StatelessWidget {
  final bool loading;
  final String userName;
  final VoidCallback onContinue;

  const _GreetingStep({
    super.key,
    required this.loading,
    required this.userName,
    required this.onContinue,
  });

  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kPrimaryLight = Color(0xFF00B4D8);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [kPrimary, kPrimaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: Color(0x330077B6), blurRadius: 24, offset: Offset(0, 10)),
                ],
              ),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 24),
            loading
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary),
                  )
                : Text(
                    'Hi, $userName! \u{1F44B}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
                  ),
            const SizedBox(height: 10),
            Text(
              'Welcome to Live Chat. We\'re here to help you\nget things sorted quickly.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  elevation: 0,
                ),
                child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Topic selection ─────────────────────────

class _TopicStep extends StatelessWidget {
  final ValueChanged<ChatTopic> onSelect;
  const _TopicStep({super.key, required this.onSelect});

  static const Color kPrimary = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'What do you need help with?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
        ),
        const SizedBox(height: 4),
        Text('Pick a topic to connect with the right team',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 20),
        for (final topic in ChatTopic.values) ...[
          _TopicCard(topic: topic, onTap: () => onSelect(topic)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  final ChatTopic topic;
  final VoidCallback onTap;
  const _TopicCard({required this.topic, required this.onTap});

  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kPrimaryLight = Color(0xFF00B4D8);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPrimary, kPrimaryLight]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(topic.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(topic.label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Hospital list ─────────────────────────

class _HospitalListStep extends StatefulWidget {
  final ChatTopic topic;
  final Future<List<_HospitalSummary>> future;
  final ValueChanged<_HospitalSummary> onPick;

  const _HospitalListStep({
    super.key,
    required this.topic,
    required this.future,
    required this.onPick,
  });

  @override
  State<_HospitalListStep> createState() => _HospitalListStepState();
}

class _HospitalListStepState extends State<_HospitalListStep> {
  static const Color kPrimary = Color(0xFF0077B6);
  bool _autoNavTriggered = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_HospitalSummary>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kPrimary));
        }

        final hospitals = snapshot.data ?? [];

        if (hospitals.isEmpty) {
          return _NoBookingState(topic: widget.topic);
        }

        if (hospitals.length == 1) {
          if (!_autoNavTriggered) {
            _autoNavTriggered = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onPick(hospitals.first);
            });
          }
          return const Center(child: CircularProgressIndicator(color: kPrimary));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: hospitals.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Choose a hospital for ${widget.topic.label}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
              );
            }
            final hospital = hospitals[index - 1];
            return _HospitalTile(hospital: hospital, onTap: () => widget.onPick(hospital));
          },
        );
      },
    );
  }
}

class _HospitalTile extends StatelessWidget {
  final _HospitalSummary hospital;
  final VoidCallback onTap;

  const _HospitalTile({required this.hospital, required this.onTap});

  static const Color kPrimary = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_hospital, color: kPrimary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hospital.hospitalName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  if (hospital.lastVisit != null) ...[
                    const SizedBox(height: 2),
                    Text('Last visit: ${DateFormat('MMM d, yyyy').format(hospital.lastVisit!)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class _NoBookingState extends StatelessWidget {
  final ChatTopic topic;
  const _NoBookingState({required this.topic});

  static const Color kPrimary = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final needsBookingLabel = topic == ChatTopic.labTest ? 'a lab test' : 'an appointment';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: kPrimary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(topic.icon, color: kPrimary, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('No hospital linked yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 6),
            Text(
              'Book $needsBookingLabel with a hospital first, then you can chat with their support team here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // TODO (Lab Test only): swap for LabTestScreen once available.
                // Appointment/Medicine still fall back to AppointmentScreen.
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AppointmentScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('Book now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HospitalSummary {
  final String hospitalId;
  final String hospitalName;
  final DateTime? lastVisit;

  _HospitalSummary({required this.hospitalId, required this.hospitalName, this.lastVisit});
}