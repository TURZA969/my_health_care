import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

/// =====================================================================
/// Professional & colorful "My History" screen
/// Tabs: Appointment Booked | Lab Test Booked | Medicine Orders
/// Reads directly from Firestore based on the collection structure:
///   appointments, lab_bookings, medicine_orders
/// Filter by current logged-in userId.
///
/// NOTE: `userId` is now OPTIONAL. If you don't pass it (e.g. calling
/// `const HistoryScreen()` from dashboard_screen.dart with no args),
/// this screen automatically reads the logged-in user's uid from
/// FirebaseAuth.instance.currentUser itself. No need to touch
/// dashboard_screen.dart at all.
///
/// NEW IN THIS VERSION:
///  - Appointments: "Mark as Complete" button under every card. Tapping
///    it lets the user leave a 1-5 star rating for the doctor. On
///    submit, the appointment's status is set to "completed" and the
///    doctor's `rating` / `ratingSum` / `totalRatings` fields (in the
///    `doctors` collection) are updated atomically via a Firestore
///    transaction. `ratingGiven` on the appointment prevents rating the
///    same appointment twice.
///  - Lab Bookings & Medicine Orders: a "Receipt No." row was added to
///    match the Appointments tab. Since `receiptNumber` does not exist
///    yet on those two collections, the label always shows, and the
///    value falls back to the literal text "null" when the field is
///    missing.
///  - Lab Bookings: an approved booking now shows a "Download Your Lab
///    Report" button. Since this project stores the report directly in
///    Firestore (no Firebase Storage), `reportUrl` actually holds the
///    **base64-encoded file bytes**, not a real http/https link. The
///    button now base64-decodes that field, writes it to a temp file on
///    the device, and opens it with the native viewer — instead of
///    trying (and failing) to `launchUrl()` it as if it were a web URL.
///    If the field is empty/missing/corrupt, the user sees a "Please
///    contact your hospital" message instead.
/// =====================================================================

/// ---------------------------------------------------------------------
/// A Tab that never overflows: the label shrinks to fit and can wrap to
/// two lines instead of clipping or spilling outside the tab's box.
/// ---------------------------------------------------------------------
class _SafeTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SafeTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 3),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  final String? userId; // optional now — auto-detected if not passed

  const HistoryScreen({super.key, this.userId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _resolvedUserId;

  static const Color kPrimary = Color(0xFF0077B6);
  static const Color kSecondary = Color(0xFF00B4D8);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Use the passed userId if given, otherwise auto-detect from
    // the currently logged-in Firebase user.
    _resolvedUserId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If no user is logged in, show a friendly message instead of crashing.
    if (_resolvedUserId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: AppBar(
          backgroundColor: kPrimary,
          elevation: 0,
          title: const Text('My History',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: emptyState(
          icon: Icons.lock_outline,
          title: 'Please log in',
          subtitle: 'You need to be logged in to view your history.',
          color: kPrimary,
        ),
      );
    }

    final userId = _resolvedUserId!;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              floating: true,
              expandedHeight: 130,
              backgroundColor: kPrimary,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 60),
                title: const Text(
                  'My History',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimary, kSecondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Container(
                  color: kPrimary,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    tabs: const [
                      _SafeTab(icon: Icons.medical_services_outlined, label: 'Appointment Booked'),
                      _SafeTab(icon: Icons.biotech_outlined, label: 'Lab Test Booked'),
                      _SafeTab(icon: Icons.medication_outlined, label: 'Medicine Orders'),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _OverviewStrip(userId: userId),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _AppointmentsTab(userId: userId),
            _LabBookingsTab(userId: userId),
            _MedicineOrdersTab(userId: userId),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// Overview strip — shows a live count for each history type at a glance.
/// Purely visual polish; the actual data-scoping to "only my history" is
/// enforced by the userId filter in each query below AND should also be
/// enforced server-side via Firestore Security Rules, e.g.:
///
///   match /appointments/{doc} {
///     allow read: if request.auth.uid == resource.data.userId;
///   }
///   // same pattern for lab_bookings and medicine_orders
///
/// ---------------------------------------------------------------------

class _OverviewStrip extends StatelessWidget {
  final String userId;
  const _OverviewStrip({required this.userId});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _CountTile(
              collection: 'appointments',
              userId: userId,
              icon: Icons.medical_services_outlined,
              label: 'Appointments',
              color: const Color(0xFF0077B6),
            ),
          ),
          _divider(),
          Expanded(
            child: _CountTile(
              collection: 'lab_bookings',
              userId: userId,
              icon: Icons.biotech_outlined,
              label: 'Lab Tests',
              color: const Color(0xFF7B2CBF),
            ),
          ),
          _divider(),
          Expanded(
            child: _CountTile(
              collection: 'medicine_orders',
              userId: userId,
              icon: Icons.medication_outlined,
              label: 'Medicines',
              color: const Color(0xFF2D9D78),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 42,
        color: Colors.grey.shade200,
      );
}

class _CountTile extends StatelessWidget {
  final String collection;
  final String userId;
  final IconData icon;
  final String label;
  final Color color;

  const _CountTile({
    required this.collection,
    required this.userId,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection(collection)
        .where('userId', isEqualTo: userId);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            count == null
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Text(
                    '$count',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold, color: color),
                  ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ],
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------
/// Shared helpers
/// ---------------------------------------------------------------------

class StatusColors {
  static Color bg(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
      case 'delivered':
        return const Color(0xFFE6F7EE);
      case 'pending':
        return const Color(0xFFFFF4E0);
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFFDE8E8);
      default:
        return const Color(0xFFE8ECF3);
    }
  }

  static Color fg(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
      case 'delivered':
        return const Color(0xFF1B9C63);
      case 'pending':
        return const Color(0xFFE08E0B);
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFE0413F);
      default:
        return const Color(0xFF5C6B85);
    }
  }

  static IconData icon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
      case 'delivered':
        return Icons.check_circle;
      case 'pending':
        return Icons.hourglass_top;
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: StatusColors.bg(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(StatusColors.icon(status), size: 14, color: StatusColors.fg(status)),
          const SizedBox(width: 4),
          Text(
            status.isEmpty ? 'Unknown' : status[0].toUpperCase() + status.substring(1),
            style: TextStyle(
              color: StatusColors.fg(status),
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

String formatDate(dynamic dateField) {
  try {
    if (dateField is Timestamp) {
      return DateFormat('dd MMM yyyy, hh:mm a').format(dateField.toDate());
    }
    if (dateField is String) {
      final parsed = DateTime.tryParse(dateField);
      if (parsed != null) return DateFormat('dd MMM yyyy').format(parsed);
      return dateField;
    }
  } catch (_) {}
  return '-';
}

/// Sorts query result docs by their `createdAt` field, newest first.
/// Done client-side (instead of `.orderBy()` in the query) so that a
/// `where(userId) + orderBy(createdAt)` combo never requires creating a
/// composite index in the Firebase console.
List<QueryDocumentSnapshot> sortByCreatedAtDesc(
    List<QueryDocumentSnapshot> docs) {
  final sorted = List<QueryDocumentSnapshot>.from(docs);
  sorted.sort((a, b) {
    final aData = a.data() as Map<String, dynamic>;
    final bData = b.data() as Map<String, dynamic>;
    final aTime = aData['createdAt'];
    final bTime = bData['createdAt'];
    if (aTime is Timestamp && bTime is Timestamp) {
      return bTime.compareTo(aTime); // descending
    }
    return 0;
  });
  return sorted;
}

/// Returns the receipt number for display, or the literal string "null"
/// when the field doesn't exist on the document (used by Lab Bookings
/// and Medicine Orders, where `receiptNumber` isn't stored yet).
String receiptNumberOrNull(Map<String, dynamic> data) {
  final value = data['receiptNumber'];
  if (value == null) return 'null';
  final asString = value.toString();
  return asString.isEmpty ? 'null' : asString;
}

/// ---------------------------------------------------------------------
/// Soft delete / restore (per user, "app theke delete, database e thake")
///
/// Deleting an item never removes the Firestore document. It only sets
/// two fields on it:
///   deletedByUser : true
///   deletedAt     : server Timestamp (when it was hidden)
///
/// Every tab query already reads ALL of the user's docs for that
/// collection (no extra Firestore query / composite index needed). From
/// that same snapshot we split into:
///   - "active"     -> deletedByUser != true            (shown in list)
///   - "restorable" -> deletedByUser == true AND deletedAt within the
///                     last 60 days                      (can be undone)
///
/// Pending items can never be deleted (single or "Delete All"), since a
/// pending request may still need hospital/pharmacy action.
/// ---------------------------------------------------------------------

const int kHistoryRestoreWindowDays = 60;

bool isPendingStatus(Map<String, dynamic> data) {
  return (data['status'] ?? '').toString().toLowerCase() == 'pending';
}

bool isSoftDeleted(Map<String, dynamic> data) {
  return data['deletedByUser'] == true;
}

/// True when the doc was soft-deleted within the last [kHistoryRestoreWindowDays].
bool isRestorableWithin60Days(Map<String, dynamic> data) {
  if (!isSoftDeleted(data)) return false;
  final deletedAt = data['deletedAt'];
  if (deletedAt is! Timestamp) {
    // No timestamp recorded (older data) — be conservative and still
    // allow restore so nothing gets stranded as permanently hidden.
    return true;
  }
  final cutoff = DateTime.now().subtract(const Duration(days: kHistoryRestoreWindowDays));
  return deletedAt.toDate().isAfter(cutoff);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Color confirmColor = const Color(0xFFE0413F),
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: Text(message, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _showHistorySnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? const Color(0xFFE0413F) : const Color(0xFF1B9C63),
    ),
  );
}

/// Soft-deletes a single document (hides it from the app only).
/// Refuses if the item is still pending.
Future<void> softDeleteSingleDoc(
  BuildContext context, {
  required String collection,
  required String docId,
  required Map<String, dynamic> data,
  required String itemLabel,
}) async {
  if (isPendingStatus(data)) {
    _showHistorySnack(context, 'Pending items can\'t be deleted.', isError: true);
    return;
  }
  final confirmed = await _confirm(
    context,
    title: 'Delete this item?',
    message:
        '$itemLabel will be removed from your history on this app. It will not be permanently deleted and you can restore it within $kHistoryRestoreWindowDays days.',
    confirmLabel: 'Delete',
  );
  if (!confirmed) return;

  try {
    await FirebaseFirestore.instance.collection(collection).doc(docId).update({
      'deletedByUser': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
    if (context.mounted) _showHistorySnack(context, 'Removed from your history.');
  } catch (e) {
    if (context.mounted) _showHistorySnack(context, 'Failed to delete: $e', isError: true);
  }
}

/// Soft-deletes every eligible (non-pending, not-already-deleted) doc in
/// [eligibleDocs] using a single batched write.
Future<void> softDeleteAllDocs(
  BuildContext context, {
  required String collection,
  required List<QueryDocumentSnapshot> eligibleDocs,
  required String sectionLabel,
}) async {
  if (eligibleDocs.isEmpty) {
    _showHistorySnack(context, 'Nothing to delete right now.', isError: true);
    return;
  }
  final confirmed = await _confirm(
    context,
    title: 'Delete all $sectionLabel history?',
    message:
        'All ${eligibleDocs.length} item(s) (pending items are skipped) will be removed from your history on this app. You can restore them within $kHistoryRestoreWindowDays days.',
    confirmLabel: 'Delete All',
  );
  if (!confirmed) return;

  try {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in eligibleDocs) {
      batch.update(doc.reference, {
        'deletedByUser': true,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (context.mounted) {
      _showHistorySnack(context, 'All $sectionLabel history removed from this app.');
    }
  } catch (e) {
    if (context.mounted) _showHistorySnack(context, 'Failed to delete all: $e', isError: true);
  }
}

/// Restores every doc in [restorableDocs] (soft-deleted within the last
/// 60 days) back into the visible history for this section.
Future<void> restoreLast60DaysDocs(
  BuildContext context, {
  required String collection,
  required List<QueryDocumentSnapshot> restorableDocs,
  required String sectionLabel,
}) async {
  if (restorableDocs.isEmpty) {
    _showHistorySnack(context, 'No deleted items from the last $kHistoryRestoreWindowDays days.', isError: true);
    return;
  }
  final confirmed = await _confirm(
    context,
    title: 'Restore last $kHistoryRestoreWindowDays days?',
    message:
        '${restorableDocs.length} item(s) deleted from this app within the last $kHistoryRestoreWindowDays days will reappear in your $sectionLabel history.',
    confirmLabel: 'Restore',
    confirmColor: const Color(0xFF1B9C63),
  );
  if (!confirmed) return;

  try {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in restorableDocs) {
      batch.update(doc.reference, {
        'deletedByUser': false,
        'deletedAt': FieldValue.delete(),
      });
    }
    await batch.commit();
    if (context.mounted) {
      _showHistorySnack(context, '$sectionLabel history restored.');
    }
  } catch (e) {
    if (context.mounted) _showHistorySnack(context, 'Failed to restore: $e', isError: true);
  }
}

/// Small delete icon-button used on every card footer. Hidden entirely
/// while the item is still pending, since pending items can't be deleted.
class DeleteHistoryButton extends StatelessWidget {
  final String collection;
  final String docId;
  final Map<String, dynamic> data;
  final String itemLabel;

  const DeleteHistoryButton({
    super.key,
    required this.collection,
    required this.docId,
    required this.data,
    required this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (isPendingStatus(data)) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Delete from history',
      onPressed: () => softDeleteSingleDoc(
        context,
        collection: collection,
        docId: docId,
        data: data,
        itemLabel: itemLabel,
      ),
      icon: const Icon(Icons.delete_outline_rounded, size: 20),
      color: const Color(0xFFE0413F),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}

/// Bar shown above each tab's list with "Delete All" + "Restore" actions.
class HistoryActionsBar extends StatelessWidget {
  final Color accent;
  final String sectionLabel;
  final String collection;
  final List<QueryDocumentSnapshot> eligibleForDeleteAll;
  final List<QueryDocumentSnapshot> restorableDocs;

  const HistoryActionsBar({
    super.key,
    required this.accent,
    required this.sectionLabel,
    required this.collection,
    required this.eligibleForDeleteAll,
    required this.restorableDocs,
  });

  @override
  Widget build(BuildContext context) {
    final hasDeletable = eligibleForDeleteAll.isNotEmpty;
    final hasRestorable = restorableDocs.isNotEmpty;
    if (!hasDeletable && !hasRestorable) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: !hasDeletable
                  ? null
                  : () => softDeleteAllDocs(
                        context,
                        collection: collection,
                        eligibleDocs: eligibleForDeleteAll,
                        sectionLabel: sectionLabel,
                      ),
              icon: const Icon(Icons.delete_sweep_outlined, size: 17),
              label: const Text('Delete All', style: TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE0413F),
                side: const BorderSide(color: Color(0xFFE0413F)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: !hasRestorable
                  ? null
                  : () => restoreLast60DaysDocs(
                        context,
                        collection: collection,
                        restorableDocs: restorableDocs,
                        sectionLabel: sectionLabel,
                      ),
              icon: const Icon(Icons.history_rounded, size: 17),
              label: Text(
                hasRestorable ? 'Restore (${restorableDocs.length})' : 'Restore',
                style: const TextStyle(fontSize: 12.5),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// Lab report download/open
///
/// IMPORTANT: this project stores the report directly inside the
/// Firestore document (no Firebase Storage bucket involved). Looking at
/// the actual data (see `lab_bookings/{doc}`), the `reportUrl` field is
/// NOT an http/https link — it is the **raw file bytes, base64-encoded**
/// (it starts with "JVBERi0x..." which decodes to the PDF file header
/// "%PDF-1.x"). The old implementation tried to `launchUrl()` that
/// string as if it were a real URL, which always failed silently and
/// showed the "contact your hospital" message.
///
/// The fix: base64-decode the field, write the bytes to a temp file on
/// the device, then open that local file with the native viewer via
/// `open_filex` (add to pubspec.yaml: `path_provider` + `open_filex`).
/// ---------------------------------------------------------------------
Future<void> downloadLabReport(
  BuildContext context,
  dynamic reportUrlRaw, {
  String? fileName,
  String? mimeType,
}) async {
  final rawData = reportUrlRaw?.toString().trim() ?? '';

  if (rawData.isEmpty) {
    _showReportUnavailableSnack(context);
    return;
  }

  try {
    // Handle both a plain base64 string and a "data:mime;base64,...." URI,
    // in case some documents end up saving it either way.
    String base64Str = rawData;
    String? mimeFromDataUri;
    if (rawData.startsWith('data:') && rawData.contains(',')) {
      final parts = rawData.split(',');
      base64Str = parts.last;
      final header = parts.first; // e.g. data:application/pdf;base64
      final mimeMatch = RegExp(r'data:(.*?);base64').firstMatch(header);
      mimeFromDataUri = mimeMatch?.group(1);
    }

    final bytes = base64Decode(base64Str);

    final resolvedMime = mimeType ?? mimeFromDataUri ?? 'application/pdf';
    final ext = _extensionForMimeType(resolvedMime);

    final dir = await getTemporaryDirectory();
    final safeName = (fileName == null || fileName.trim().isEmpty)
        ? 'lab_report_${DateTime.now().millisecondsSinceEpoch}'
        : fileName.trim().replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    final file = File('${dir.path}/$safeName.$ext');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFile.open(file.path);

    if (result.type != ResultType.done) {
      if (context.mounted) _showReportUnavailableSnack(context);
    }
  } catch (_) {
    // Malformed/incomplete base64, or nothing could open the file type.
    if (context.mounted) _showReportUnavailableSnack(context);
  }
}

String _extensionForMimeType(String mimeType) {
  final mime = mimeType.toLowerCase();
  if (mime.contains('pdf')) return 'pdf';
  if (mime.contains('png')) return 'png';
  if (mime.contains('jpeg') || mime.contains('jpg')) return 'jpg';
  if (mime.contains('webp')) return 'webp';
  return 'pdf'; // sensible default for lab reports
}

void _showReportUnavailableSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Please contact your hospital'),
      backgroundColor: Color(0xFFE0413F),
    ),
  );
}

Widget emptyState({
  required IconData icon,
  required String title,
  required String subtitle,
  required Color color,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 40),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
        ],
      ),
    ),
  );
}

Widget errorState(Object error) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Something went wrong.\n$error',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.redAccent),
      ),
    ),
  );
}

Widget loadingState(Color color) {
  return Center(child: CircularProgressIndicator(color: color));
}

/// A small row used inside cards for key/value details
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// TAB 1 — Appointments
/// ---------------------------------------------------------------------

class _AppointmentsTab extends StatelessWidget {
  final String userId;
  const _AppointmentsTab({required this.userId});

  static const Color accent = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('appointments')
        .where('userId', isEqualTo: userId);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return errorState(snapshot.error!);
        if (!snapshot.hasData) return loadingState(accent);

        final allDocs = snapshot.data!.docs;
        final activeDocs = sortByCreatedAtDesc(allDocs
            .where((d) => !isSoftDeleted(d.data() as Map<String, dynamic>))
            .toList());
        final eligibleForDeleteAll = activeDocs
            .where((d) => !isPendingStatus(d.data() as Map<String, dynamic>))
            .toList();
        final restorableDocs = allDocs
            .where((d) => isRestorableWithin60Days(d.data() as Map<String, dynamic>))
            .toList();

        final actionsBar = HistoryActionsBar(
          accent: accent,
          sectionLabel: 'Appointment',
          collection: 'appointments',
          eligibleForDeleteAll: eligibleForDeleteAll,
          restorableDocs: restorableDocs,
        );

        if (activeDocs.isEmpty) {
          return Column(
            children: [
              actionsBar,
              Expanded(
                child: emptyState(
                  icon: Icons.medical_services_outlined,
                  title: 'No appointments yet',
                  subtitle: 'Your booked doctor appointments will show up here.',
                  color: accent,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            actionsBar,
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                itemCount: activeDocs.length,
                itemBuilder: (context, i) {
                  final doc = activeDocs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  return _AppointmentCard(docId: doc.id, data: data);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A single appointment card. Stateful because it owns the
/// "Mark as Complete" + star-rating flow and needs a local
/// submitting/loading flag while writing to Firestore.
class _AppointmentCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const _AppointmentCard({required this.docId, required this.data});

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  static const Color accent = Color(0xFF0077B6);
  static const Color star = Color(0xFFFFC107);

  bool _isSubmitting = false;

  /// Shows the 1-5 star rating dialog. Returns:
  ///  - 1..5  -> the star rating the user picked and wants to submit
  ///  - 0     -> user chose "Skip" (still mark as complete, no rating)
  ///  - null  -> user dismissed the dialog entirely (do nothing)
  Future<int?> _showRatingDialog() {
    int selected = 0;
    final doctorName = widget.data['doctorName']?.toString() ?? 'the doctor';

    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text(
                'Rate your doctor',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'How was your experience with Dr. $doctorName?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        return InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            setDialogState(() => selected = starIndex);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(
                              starIndex <= selected ? Icons.star_rounded : Icons.star_border_rounded,
                              color: star,
                              size: 30,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(0),
                  child: Text('Skip', style: TextStyle(color: Colors.grey.shade600)),
                ),
                ElevatedButton(
                  onPressed: selected == 0
                      ? null
                      : () => Navigator.of(dialogContext).pop(selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleMarkAsComplete() async {
    final result = await _showRatingDialog();
    if (result == null) return; // dialog dismissed, no action

    setState(() => _isSubmitting = true);

    try {
      final apptRef =
          FirebaseFirestore.instance.collection('appointments').doc(widget.docId);

      if (result == 0) {
        // Skipped rating — just mark the appointment complete.
        await apptRef.update({'status': 'completed'});
      } else {
        final doctorId = widget.data['doctorId']?.toString();
        final doctorRef = (doctorId != null && doctorId.isNotEmpty)
            ? FirebaseFirestore.instance.collection('doctors').doc(doctorId)
            : null;

        await FirebaseFirestore.instance.runTransaction((tx) async {
          // --- ALL READS FIRST ---
          // Firestore transactions require every read to happen before
          // any write is issued, otherwise it throws
          // "Transactions require all reads to be executed before all writes".
          DocumentSnapshot? doctorSnap;
          if (doctorRef != null) {
            doctorSnap = await tx.get(doctorRef);
          }

          // --- THEN ALL WRITES ---
          tx.update(apptRef, {
            'status': 'completed',
            'ratingGiven': true,
            'userRating': result,
          });

          if (doctorRef != null && doctorSnap != null && doctorSnap.exists) {
            final doctorData = doctorSnap.data() as Map<String, dynamic>? ?? {};
            final currentSum = (doctorData['ratingSum'] ?? 0) as num;
            final currentTotal = (doctorData['totalRatings'] ?? 0) as num;

            final newSum = currentSum + result;
            final newTotal = currentTotal + 1;
            final newRating = newTotal > 0 ? newSum / newTotal : 0;

            tx.update(doctorRef, {
              'ratingSum': newSum,
              'totalRatings': newTotal,
              'rating': newRating,
            });
          }
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result == 0
                ? 'Appointment marked as complete.'
                : 'Thanks! Your rating was submitted.'),
            backgroundColor: const Color(0xFF1B9C63),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: const Color(0xFFE0413F),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final status = (data['status'] ?? '').toString();
    final normalizedStatus = status.toLowerCase();
    final ratingGiven = data['ratingGiven'] == true;

    // Only an "approved" appointment can be marked complete / rated.
    // Pending, cancelled, rejected, or already-completed appointments
    // won't show a working button.
    final canMarkComplete = normalizedStatus == 'approved';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: StatusColors.fg(status), width: 4)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['doctorName']?.toString() ?? 'Doctor',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: Color(0xFF1A1A2E)),
                    ),
                    Text(
                      data['specialty']?.toString() ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              StatusChip(status: status),
            ],
          ),
          const Divider(height: 20),
          InfoRow(
              icon: Icons.local_hospital,
              label: 'Hospital',
              value: data['hospitalName']?.toString() ?? '-',
              iconColor: accent),
          InfoRow(
              icon: Icons.event,
              label: 'Date',
              value: data['date']?.toString() ?? '-',
              iconColor: accent),
          InfoRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Slot',
              value: '${data['slotNumber'] ?? '-'}',
              iconColor: accent),
          InfoRow(
              icon: Icons.payments_outlined,
              label: 'Fee',
              value: '৳${data['fee'] ?? 0}  (Paid: ৳${data['amountPaid'] ?? 0})',
              iconColor: accent),
          if ((data['dueAmount'] ?? 0) > 0)
            InfoRow(
                icon: Icons.warning_amber_rounded,
                label: 'Due',
                value: '৳${data['dueAmount']}',
                iconColor: const Color(0xFFE08E0B)),
          InfoRow(
              icon: Icons.receipt_long,
              label: 'Receipt No.',
              value: data['receiptNumber']?.toString() ?? '-',
              iconColor: accent),
          InfoRow(
              icon: Icons.credit_card,
              label: 'Payment',
              value: data['paymentType']?.toString() ?? '-',
              iconColor: accent),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Created: ${formatDate(data['createdAt'])}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              DeleteHistoryButton(
                collection: 'appointments',
                docId: widget.docId,
                data: data,
                itemLabel: 'This appointment',
              ),
            ],
          ),

          // --- Mark as Complete / status footer -------------------------
          if (canMarkComplete) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _handleMarkAsComplete,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_isSubmitting ? 'Please wait...' : 'Mark as Complete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ] else if (normalizedStatus == 'completed') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Color(0xFF1B9C63)),
                const SizedBox(width: 6),
                Text(
                  ratingGiven
                      ? 'Completed • Thanks for rating!'
                      : 'Completed',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// TAB 2 — Lab Bookings
/// ---------------------------------------------------------------------

class _LabBookingsTab extends StatelessWidget {
  final String userId;
  const _LabBookingsTab({required this.userId});

  static const Color accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('lab_bookings')
        .where('userId', isEqualTo: userId);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return errorState(snapshot.error!);
        if (!snapshot.hasData) return loadingState(accent);

        final allDocs = snapshot.data!.docs;
        final activeDocs = sortByCreatedAtDesc(allDocs
            .where((d) => !isSoftDeleted(d.data() as Map<String, dynamic>))
            .toList());
        final eligibleForDeleteAll = activeDocs
            .where((d) => !isPendingStatus(d.data() as Map<String, dynamic>))
            .toList();
        final restorableDocs = allDocs
            .where((d) => isRestorableWithin60Days(d.data() as Map<String, dynamic>))
            .toList();

        final actionsBar = HistoryActionsBar(
          accent: accent,
          sectionLabel: 'Lab Test',
          collection: 'lab_bookings',
          eligibleForDeleteAll: eligibleForDeleteAll,
          restorableDocs: restorableDocs,
        );

        if (activeDocs.isEmpty) {
          return Column(
            children: [
              actionsBar,
              Expanded(
                child: emptyState(
                  icon: Icons.biotech_outlined,
                  title: 'No lab bookings yet',
                  subtitle: 'Your booked lab tests will show up here.',
                  color: accent,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            actionsBar,
            Expanded(
              child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          itemCount: activeDocs.length,
          itemBuilder: (context, i) {
            final docId = activeDocs[i].id;
            final data = activeDocs[i].data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString();
            final homeCollection = data['homeCollection'] == true;
            // Report download is only offered once the booking is approved.
            final isApproved = status.toLowerCase() == 'approved';
            // Only show the button if there's actually report data saved.
            final hasReportData =
                (data['reportUrl']?.toString().trim().isNotEmpty ?? false);

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border(left: BorderSide(color: StatusColors.fg(status), width: 4)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.science_outlined, color: accent, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['testName']?.toString() ?? 'Lab Test',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: Color(0xFF1A1A2E)),
                            ),
                            Text(
                              data['hospitalName']?.toString() ?? '',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(status: status),
                    ],
                  ),
                  const Divider(height: 20),
                  InfoRow(
                      icon: Icons.event,
                      label: 'Date',
                      value: data['date']?.toString() ?? '-',
                      iconColor: accent),
                  InfoRow(
                      icon: homeCollection ? Icons.home_outlined : Icons.local_hospital,
                      label: 'Collection',
                      value: homeCollection ? 'Home collection' : 'At hospital',
                      iconColor: accent),
                  if (data['location'] != null)
                    InfoRow(
                        icon: Icons.location_on_outlined,
                        label: 'Location',
                        value: data['location'].toString(),
                        iconColor: accent),
                  if (data['kitRequired'] == true)
                    InfoRow(
                        icon: Icons.inventory_2_outlined,
                        label: 'Kit',
                        value:
                            '${data['kitName'] ?? '-'} (৳${data['kitCharge'] ?? 0})',
                        iconColor: accent),
                  InfoRow(
                      icon: Icons.payments_outlined,
                      label: 'Test Fee',
                      value: '৳${data['testFee'] ?? 0}',
                      iconColor: accent),
                  InfoRow(
                      icon: Icons.summarize_outlined,
                      label: 'Total Fee',
                      value: '৳${data['totalFee'] ?? 0}',
                      iconColor: accent),
                  InfoRow(
                      icon: Icons.receipt_long,
                      label: 'Receipt No.',
                      value: receiptNumberOrNull(data),
                      iconColor: accent),
                  InfoRow(
                      icon: Icons.credit_card,
                      label: 'Payment',
                      value: data['paymentMethod']?.toString() ?? '-',
                      iconColor: accent),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Created: ${formatDate(data['createdAt'])}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                      DeleteHistoryButton(
                        collection: 'lab_bookings',
                        docId: docId,
                        data: data,
                        itemLabel: 'This lab booking',
                      ),
                    ],
                  ),

                  // --- Download Your Lab Report (approved only) ---------
                  if (isApproved) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: !hasReportData
                            ? null
                            : () => downloadLabReport(
                                  context,
                                  data['reportUrl'],
                                  fileName: data['reportFileName']?.toString(),
                                  mimeType: data['reportMimeType']?.toString(),
                                ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(hasReportData
                            ? 'Download Your Lab Report'
                            : 'Report Not Uploaded Yet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasReportData
                              ? accent
                              : Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// ---------------------------------------------------------------------
/// TAB 3 — Medicine Orders
/// ---------------------------------------------------------------------

class _MedicineOrdersTab extends StatelessWidget {
  final String userId;
  const _MedicineOrdersTab({required this.userId});

  static const Color accent = Color(0xFF2D9D78);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('medicine_orders')
        .where('userId', isEqualTo: userId);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return errorState(snapshot.error!);
        if (!snapshot.hasData) return loadingState(accent);

        final allDocs = snapshot.data!.docs;
        final activeDocs = sortByCreatedAtDesc(allDocs
            .where((d) => !isSoftDeleted(d.data() as Map<String, dynamic>))
            .toList());
        final eligibleForDeleteAll = activeDocs
            .where((d) => !isPendingStatus(d.data() as Map<String, dynamic>))
            .toList();
        final restorableDocs = allDocs
            .where((d) => isRestorableWithin60Days(d.data() as Map<String, dynamic>))
            .toList();

        final actionsBar = HistoryActionsBar(
          accent: accent,
          sectionLabel: 'Medicine Order',
          collection: 'medicine_orders',
          eligibleForDeleteAll: eligibleForDeleteAll,
          restorableDocs: restorableDocs,
        );

        if (activeDocs.isEmpty) {
          return Column(
            children: [
              actionsBar,
              Expanded(
                child: emptyState(
                  icon: Icons.medication_outlined,
                  title: 'No medicine orders yet',
                  subtitle: 'Your medicine orders will show up here.',
                  color: accent,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            actionsBar,
            Expanded(
              child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          itemCount: activeDocs.length,
          itemBuilder: (context, i) {
            final docId = activeDocs[i].id;
            final data = activeDocs[i].data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString();
            final items = (data['items'] as List<dynamic>? ?? []);
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border(left: BorderSide(color: StatusColors.fg(status), width: 4)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.medication_outlined, color: accent, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${items.length} item${items.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Color(0xFF1A1A2E)),
                        ),
                      ),
                      StatusChip(status: status),
                    ],
                  ),
                  const Divider(height: 20),
                  ...items.map((raw) {
                    final item = raw as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 5, right: 8),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                                color: accent, shape: BoxShape.circle),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name']?.toString() ?? 'Medicine',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A2E)),
                                ),
                                Text(
                                  '${item['dosage'] ?? ''}  •  Qty: ${item['qty'] ?? 1}  •  ৳${item['price'] ?? 0}',
                                  style: TextStyle(
                                      fontSize: 11.5, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 20),
                  InfoRow(
                      icon: Icons.receipt_long,
                      label: 'Receipt No.',
                      value: receiptNumberOrNull(data),
                      iconColor: accent),
                  InfoRow(
                      icon: Icons.credit_card,
                      label: 'Payment',
                      value: data['paymentMethod']?.toString() ?? '-',
                      iconColor: accent),
                  InfoRow(
                      icon: Icons.summarize_outlined,
                      label: 'Total',
                      value: '৳${data['totalAmount'] ?? 0}',
                      iconColor: accent),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Created: ${formatDate(data['createdAt'])}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                      DeleteHistoryButton(
                        collection: 'medicine_orders',
                        docId: docId,
                        data: data,
                        itemLabel: 'This medicine order',
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
              ),
            ),
          ],
        );
      },
    );
  }
}