import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/app_strings.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';

/// "My Time" tab for foremen: clock in/out at one of their assigned job
/// sites, take lunch and finish the day.
///
/// Foremen clock in at the whole job site rather than an area, so their
/// hours show on timesheets but are not counted against any area's
/// crew days.
class ForemanTimeTab extends StatefulWidget {
  final UserModel user;

  const ForemanTimeTab({super.key, required this.user});

  @override
  State<ForemanTimeTab> createState() => _ForemanTimeTabState();
}

class _ForemanTimeTabState extends State<ForemanTimeTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoadingLog = true;

  /// Which button is working right now (e.g. `'site:<projectId>'`,
  /// 'clockOut'). Only that button shows a spinner; the rest ignore taps
  /// until it finishes.
  String? _busyKey;
  bool get _isBusy => _busyKey != null;

  List<Map<String, dynamic>> _timeEntries = [];
  bool _isClockedIn = false;
  bool _isOnLunch = false;
  bool _hasHadLunch = false;
  bool _isDayComplete = false;
  DateTime? _lunchStartTime;

  @override
  void initState() {
    super.initState();
    _loadTodaysState();
  }

  Future<void> _loadTodaysState() async {
    try {
      final log = await _firestoreService.getTodaysLog(widget.user.id);
      final entries = List<Map<String, dynamic>>.from(
        log?['time_entries'] ?? [],
      );
      final hasOpenEntry =
          entries.isNotEmpty && entries.last['clockOut'] == null;
      final isDayComplete = log?['is_day_complete'] ?? false;

      // Remind at 4:30 PM if still clocked in; cancel once clocked out.
      NotificationService.syncClockOutReminder(
        isClockedIn: hasOpenEntry && !isDayComplete,
      );

      if (!mounted) return;
      setState(() {
        _timeEntries = entries;
        _isClockedIn = hasOpenEntry;
        _isDayComplete = isDayComplete;
        _isOnLunch = log?['is_on_lunch'] ?? false;
        _hasHadLunch = log?['lunch_end'] != null;
        _lunchStartTime = _isOnLunch
            ? (log?['lunch_start'] as Timestamp?)?.toDate()
            : null;
        _isLoadingLog = false;
      });
    } catch (e) {
      debugPrint('Failed to load foreman\'s day: $e');
      if (mounted) setState(() => _isLoadingLog = false);
    }
  }

  /// Runs [action] for the button [key], shows [message] on success and any
  /// error in red, then reloads today's state.
  Future<void> _run(
    String key,
    Future<void> Function() action,
    String? message,
  ) async {
    setState(() => _busyKey = key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (message != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.black87),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      await _loadTodaysState();
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _clockIn(String projectId, String projectName) async {
    final key = 'site:$projectId';
    setState(() => _busyKey = key);
    try {
      final position = await getClockInLocation(context);
      if (position == null) {
        // Permission permanently denied — the Settings dialog was shown.
        if (mounted) setState(() => _busyKey = null);
        return;
      }
      if (!mounted) return;
      await _run(
        key,
        () => _firestoreService.clockInToArea(
          userId: widget.user.id,
          userName: widget.user.name,
          userRole: widget.user.role,
          projectId: projectId,
          projectName: projectName,
          location: GeoPoint(position.latitude, position.longitude),
        ),
        tr('Clocked in at $projectName', 'Entrada registrada en $projectName'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmClockOut() async {
    final siteName = _timeEntries.last['projectName'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Clock Out', 'Registrar Salida')),
        content: Text(
          tr('Clock out of $siteName?', '¿Registrar tu salida de $siteName?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('Clock Out', 'Registrar Salida')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      'clockOut',
      () => _firestoreService.clockOutOfArea(
        userId: widget.user.id,
        description: '',
      ),
      tr('Clocked out', 'Salida registrada'),
    );
  }

  Future<void> _finishDay() => _run('finishDay', () async {
    await _firestoreService.completeDayLog(userId: widget.user.id);
    await NotificationService.cancelClockOutReminder();
  }, tr('Day complete! Great work.', '¡Día terminado! Buen trabajo.'));

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    if (_isLoadingLog) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.black87),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTodaysState,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isDayComplete)
            _buildDayCompleteCard()
          else if (_isOnLunch) ...[
            _buildBanner(
              icon: Icons.restaurant,
              color: Colors.orange,
              title: tr('On lunch break', 'En almuerzo'),
              subtitle: _lunchStartTime == null
                  ? null
                  : tr(
                      'Started at ${_formatTime(_lunchStartTime!)}',
                      'Empezó a las ${_formatTime(_lunchStartTime!)}',
                    ),
            ),
            const SizedBox(height: 16),
            _buildPillButton(
              label: AppStrings.endLunch,
              color: Colors.grey[600]!,
              busyKey: 'endLunch',
              onTap: () => _run(
                'endLunch',
                () => _firestoreService.endLunch(userId: widget.user.id),
                null,
              ),
            ),
          ] else if (_isClockedIn) ...[
            _buildBanner(
              icon: Icons.work,
              color: Colors.grey[700]!,
              title: tr(
                'Working at ${_timeEntries.last['projectName'] ?? ''}',
                'Trabajando en ${_timeEntries.last['projectName'] ?? ''}',
              ),
              subtitle: _clockInLabel(_timeEntries.last),
            ),
            if (!_hasHadLunch) ...[
              const SizedBox(height: 12),
              _buildPillButton(
                label: AppStrings.startLunch,
                color: Colors.grey[500]!,
                busyKey: 'startLunch',
                onTap: () => _run(
                  'startLunch',
                  () => _firestoreService.startLunch(userId: widget.user.id),
                  null,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildPillButton(
              label: AppStrings.clockOut,
              color: Colors.black87,
              busyKey: 'clockOut',
              onTap: _confirmClockOut,
            ),
          ] else ...[
            _buildSiteList(),
            if (_timeEntries.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildPillButton(
                label: AppStrings.finishDay,
                color: Colors.black87,
                busyKey: 'finishDay',
                onTap: _finishDay,
              ),
            ],
          ],
          _buildTodayEntries(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CLOCK IN — pick one of the foreman's job sites
  // ═══════════════════════════════════════════════════════════

  Widget _buildSiteList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('projects')
          .where('assignedForemen', arrayContains: widget.user.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: Colors.black87),
            ),
          );
        }

        final sites = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] != 'completed';
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Clock in at a job site', 'Registra tu entrada en una obra'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (sites.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tr(
                    'You are not assigned to any job sites yet. Ask your supervisor to assign you.',
                    'Aún no tienes obras asignadas. Pide a tu supervisor que te asigne.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              )
            else
              for (final doc in sites)
                _buildSiteCard(doc.id, doc.data() as Map<String, dynamic>),
          ],
        );
      },
    );
  }

  Widget _buildSiteCard(String projectId, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '';
    final location = data['location'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _isBusy ? null : () => _clockIn(projectId, name),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black87.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.black87.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.location_city,
                  color: Colors.black87,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (location.isNotEmpty)
                      Text(
                        location,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _busyKey == 'site:$projectId'
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        AppStrings.clockIn,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // STATUS CARDS + TODAY'S ENTRIES
  // ═══════════════════════════════════════════════════════════

  Widget _buildBanner({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCompleteCard() {
    final totalHours = _timeEntries.fold<double>(
      0,
      (total, e) => total + ((e['hoursWorked'] ?? 0) as num).toDouble(),
    );
    return _buildBanner(
      icon: Icons.check_circle,
      color: Colors.black87,
      title: AppStrings.dayComplete,
      subtitle: tr(
        '${totalHours.toStringAsFixed(1)} hours today',
        '${totalHours.toStringAsFixed(1)} horas hoy',
      ),
    );
  }

  Widget _buildTodayEntries() {
    // Only finished sessions — the open one is shown in the banner above.
    final done = _timeEntries.where((e) => e['clockOut'] != null).toList();
    if (done.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          tr('Today\'s Time', 'Tiempo de Hoy'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final entry in done)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry['projectName'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_formatTime((entry['clockIn'] as Timestamp).toDate())} – '
                        '${_formatTime((entry['clockOut'] as Timestamp).toDate())}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${((entry['hoursWorked'] ?? 0) as num).toStringAsFixed(1)} h',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPillButton({
    required String label,
    required Color color,
    required String busyKey,
    required VoidCallback onTap,
  }) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.85,
        child: GestureDetector(
          onTap: _isBusy ? null : onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: _busyKey == busyKey
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  String? _clockInLabel(Map<String, dynamic> entry) {
    final clockIn = (entry['clockIn'] as Timestamp?)?.toDate();
    if (clockIn == null) return null;
    return tr(
      'Since ${_formatTime(clockIn)}',
      'Desde las ${_formatTime(clockIn)}',
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
