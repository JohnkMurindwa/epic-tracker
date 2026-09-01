import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';
import '../../widgets/epic_week_header.dart';
import 'package:intl/intl.dart';

class InstallerDashboard extends StatefulWidget {
  final UserModel user;
  const InstallerDashboard({super.key, required this.user});

  @override
  State<InstallerDashboard> createState() => _InstallerDashboardState();
}

class _InstallerDashboardState extends State<InstallerDashboard> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isClockedIn = false;
  bool _isOnLunch = false;
  bool _hasHadLunch = false;
  bool _isDayComplete = false;
  String? _currentAreaId;
  String? _currentAreaName;
  String? _currentProjectName;
  List<Map<String, dynamic>> _timeEntries = [];
  DateTime? _lunchStartTime;
  DateTime _selectedDay = DateTime.now();

  bool get _isViewingToday {
    final now = DateTime.now();
    return _selectedDay.year == now.year &&
        _selectedDay.month == now.month &&
        _selectedDay.day == now.day;
  }

  // Area crew day info
  double _areaCrewDaysTotal = 0;
  double _areaCrewDaysConsumed = 0;
  int _areaPeopleCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTodaysState();
  }

  Future<void> _loadTodaysState() async {
    try {
      final log = await _firestoreService.getTodaysLog(widget.user.id);
      if (log == null || !mounted) return;

      final entries = List<Map<String, dynamic>>.from(
        log['time_entries'] ?? [],
      );
      final hasOpenEntry =
          entries.isNotEmpty && entries.last['clockOut'] == null;

      setState(() {
        _timeEntries = entries;
        _isDayComplete = log['is_day_complete'] ?? false;
        _isOnLunch = log['is_on_lunch'] ?? false;
        _hasHadLunch = log['lunch_end'] != null;
        final lunchStart = (log['lunch_start'] as Timestamp?)?.toDate();
        if (lunchStart != null && _isOnLunch) {
          _lunchStartTime = lunchStart;
        }

        if (hasOpenEntry) {
          _isClockedIn = true;
          _currentAreaId = entries.last['areaId'] as String?;
          _currentAreaName = entries.last['areaName'] as String?;
          _currentProjectName = entries.last['projectName'] as String?;
        }
      });

      if (_currentAreaId != null) {
        _loadAreaInfo(_currentAreaId!);
      }
    } catch (e) {
      debugPrint('Failed to load today\'s state: $e');
    }
  }

  Future<void> _loadAreaInfo(String areaId) async {
    try {
      final doc = await _db.collection('areas').doc(areaId).get();
      if (!doc.exists || !mounted) return;
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _areaCrewDaysTotal = (data['totalCrewDays'] ?? 0).toDouble();
        _areaCrewDaysConsumed = (data['consumedCrewDays'] ?? 0).toDouble();
        _areaPeopleCount = (data['assignedPeople'] as List?)?.length ?? 0;
      });
    } catch (e) {
      debugPrint('Failed to load area info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          EpicWeekHeader(
            userName: widget.user.name,
            userRole: widget.user.role,
            onDaySelected: (day) {
              setState(() => _selectedDay = day);
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Past day view (tapped a previous day) ──
                  if (!_isViewingToday) ...[
                    _buildPastDayView(),
                  ]
                  // ─── Day complete: same card style as history ──
                  else if (_isDayComplete) ...[
                    Builder(
                      builder: (context) {
                        // Pull the last snapshot of crew days from today's entries
                        double? crewDaysLeft;
                        for (final e in _timeEntries.reversed) {
                          if (e['crewDaysLeftAfter'] != null) {
                            crewDaysLeft = (e['crewDaysLeftAfter'] as num)
                                .toDouble();
                            break;
                          }
                        }

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.black87,
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Day Complete',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              if (crewDaysLeft != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '${crewDaysLeft.toStringAsFixed(1)} crew days to go',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_timeEntries.isNotEmpty) _buildTodayEntries(),
                  ]
                  // ─── Active work flow ───────────────────
                  else ...[
                    // Today's time entries
                    if (_timeEntries.isNotEmpty) _buildTodayEntries(),

                    // Crew days info when clocked in
                    if (_isClockedIn && _currentAreaId != null) ...[
                      const SizedBox(height: 16),
                      _buildCrewDaysCard(),
                    ],

                    const SizedBox(height: 16),

                    // Currently on lunch (still clocked in — just paused)
                    if (_isOnLunch) ...[
                      _buildClockOutSection(),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey[500],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lunch_dining,
                              color: Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'On Lunch Break',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_lunchStartTime != null)
                                  Text(
                                    'Started at ${_formatTime(_lunchStartTime!)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPillButton(
                        label: 'end lunch',
                        color: Colors.grey[600]!,
                        onTap: _endLunch,
                      ),
                    ]
                    // Clock in (select area) — when not clocked in and not on lunch
                    else if (!_isClockedIn && !_isOnLunch)
                      _buildClockInSection()
                    // Clocked in — show working banner + start lunch + clock out
                    else if (_isClockedIn) ...[
                      _buildClockOutSection(),
                      if (!_hasHadLunch) ...[
                        const SizedBox(height: 12),
                        _buildPillButton(
                          label: 'start lunch',
                          color: Colors.grey[500]!,
                          onTap: _startLunchFromArea,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildPillButton(
                        label: 'clock out',
                        color: Colors.black87,
                        onTap: _showClockOutDialog,
                      ),
                    ],

                    // Finish day (after last clock out — no photo needed)
                    if (!_isClockedIn &&
                        !_isOnLunch &&
                        _timeEntries.isNotEmpty &&
                        !_isDayComplete) ...[
                      const SizedBox(height: 20),
                      _buildPillButton(
                        label: 'finish day',
                        color: Colors.black87,
                        onTap: _finishDay,
                      ),
                    ],
                  ],

                  // Sign out
                  const SizedBox(height: 40),
                  _buildSignOutButton(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CREW DAYS CARD
  // ═══════════════════════════════════════════════════════════

  Widget _buildCrewDaysCard() {
    if (_currentAreaId == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('areas').doc(_currentAreaId).snapshots(),
      builder: (context, snapshot) {
        // Fall back to last loaded values while waiting
        double total = _areaCrewDaysTotal;
        double consumed = _areaCrewDaysConsumed;
        int peopleCount = _areaPeopleCount;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          total = (data['totalCrewDays'] ?? 0).toDouble();
          consumed = (data['consumedCrewDays'] ?? 0).toDouble();
          peopleCount = (data['assignedPeople'] as List?)?.length ?? 0;
        }

        final remaining = total - consumed;
        final progress = total > 0 ? (consumed / total).clamp(0.0, 1.0) : 0.0;
        // Crew days left reduces as more pairs are assigned:
        // remaining labor ÷ number of pairs working it
        final pairs = peopleCount / 2;
        final crewDaysLeft = pairs > 0 ? remaining / pairs : remaining;

        // Urgency colors: purple → orange → red as time runs out
        Color cardColor;
        String urgencyLabel;
        if (progress >= 0.75) {
          cardColor = const Color(0xFFD32F2F); // red — crunch time
          urgencyLabel = 'CRUNCH TIME';
        } else if (progress >= 0.5) {
          cardColor = const Color(0xFFEF6C00); // orange — halfway warning
          urgencyLabel = 'PUSH HARD';
        } else {
          cardColor = Colors.black87;
          urgencyLabel = 'ON TRACK';
        }

        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: cardColor.withValues(alpha: 0.4),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentAreaName ?? 'Current Area',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _currentProjectName ?? '',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          urgencyLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ─── THE BIG COUNTDOWN ───
                  Center(
                    child: Column(
                      children: [
                        Text(
                          crewDaysLeft.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -2,
                          ),
                        ),
                        Text(
                          'CREW DAYS LEFT',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Bottom row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.people,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$peopleCount working',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}% done',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CLOCK IN — SELECT AREA
  // ═══════════════════════════════════════════════════════════

  Widget _buildClockInSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('areas')
          .where('assignedPeople', arrayContains: widget.user.id)
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Colors.black87),
            ),
          );
        }

        final allAreas =
            snapshot.data?.docs
                .map(
                  (doc) => {
                    'id': doc.id,
                    ...doc.data() as Map<String, dynamic>,
                  },
                )
                .toList() ??
            [];

        // Filter out areas already clocked out of today (one session per area per day)
        final completedAreaIds = _timeEntries
            .where((e) => e['clockOut'] != null)
            .map((e) => e['areaId'] as String?)
            .whereType<String>()
            .toSet();

        final areas = allAreas
            .where((a) => !completedAreaIds.contains(a['id']))
            .toList();

        if (areas.isEmpty) {
          final allDone = allAreas.isNotEmpty;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(
                  allDone ? Icons.task_alt : Icons.location_off,
                  size: 48,
                  color: allDone ? Colors.black54 : Colors.grey[300],
                ),
                const SizedBox(height: 12),
                Text(
                  allDone ? 'All areas done for today' : 'No areas assigned',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allDone
                      ? 'Tap finish day below when you\'re done'
                      : 'Ask your Supervisor to assign you to an area',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _timeEntries.isEmpty
                  ? 'Clock in to start your day'
                  : 'Clock in to another area',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            ...areas.map((area) => _buildAreaClockInCard(area)),
          ],
        );
      },
    );
  }

  Widget _buildAreaClockInCard(Map<String, dynamic> area) {
    final areaName = area['name'] ?? '';
    final projectName = area['projectName'] ?? '';
    final totalCrewDays = (area['totalCrewDays'] ?? 0).toDouble();
    final consumed = (area['consumedCrewDays'] ?? 0).toDouble();
    final peopleCount = (area['assignedPeople'] as List?)?.length ?? 0;
    final pairs = peopleCount / 2;
    final remaining = totalCrewDays - consumed;
    final crewDaysLeft = pairs > 0 ? remaining / pairs : remaining;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _isLoading ? null : () => _clockIn(area),
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
                  Icons.location_on,
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
                      areaName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$projectName • ${crewDaysLeft.toStringAsFixed(1)} crew days left',
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
                child: const Text(
                  'clock in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
  // CLOCK OUT — WITH DESCRIPTION
  // ═══════════════════════════════════════════════════════════

  Widget _buildClockOutSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.work, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Working at $_currentAreaName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _currentProjectName ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TODAY'S TIME ENTRIES
  // ═══════════════════════════════════════════════════════════

  Widget _buildTodayEntries() {
    // Only show COMPLETED sessions — the active area is already shown
    // in the crew days card + working banner below.
    final completedEntries = _timeEntries
        .where((e) => e['clockOut'] != null)
        .toList();

    if (completedEntries.isEmpty) return const SizedBox.shrink();

    // Group entries by area
    final Map<String, List<Map<String, dynamic>>> areaGroups = {};
    for (final entry in completedEntries) {
      final areaName = entry['areaName'] as String? ?? 'Unknown';
      areaGroups.putIfAbsent(areaName, () => []).add(entry);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Work',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 10),
          ...areaGroups.entries.map((group) {
            final areaName = group.key;
            final sessions = group.value;

            // Aggregate data for this area
            double totalHours = 0;
            bool isActive = false;
            final timeRanges = <String>[];
            final descriptions = <String>[];

            for (final session in sessions) {
              final clockIn = (session['clockIn'] as Timestamp?)?.toDate();
              final clockOut = (session['clockOut'] as Timestamp?)?.toDate();
              final description = session['description'] as String?;
              totalHours += (session['hoursWorked'] ?? 0).toDouble();

              if (clockOut == null) {
                isActive = true;
                timeRanges.add(
                  '${clockIn != null ? _formatTime(clockIn) : '--'} – now',
                );
              } else {
                timeRanges.add(
                  '${clockIn != null ? _formatTime(clockIn) : '--'} – ${_formatTime(clockOut)}',
                );
              }

              // Skip auto lunch descriptions from the summary
              if (description != null &&
                  description.isNotEmpty &&
                  description != 'Went on lunch break') {
                descriptions.add(description);
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isActive ? Colors.black87 : Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isActive ? Icons.play_arrow : Icons.check,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          areaName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        Text(
                          '${totalHours.toStringAsFixed(1)}h',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // All time ranges for this area
                  Text(
                    timeRanges.join(', '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  // Combined descriptions
                  if (descriptions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      descriptions.join(' '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // END OF DAY PHOTO
  // ═══════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // DAY SUMMARY (after finishing day)
  // ═══════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // PAST DAY VIEW — history for any previous day
  // ═══════════════════════════════════════════════════════════

  Widget _buildPastDayView() {
    final dayStart = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final dateLabel = DateFormat('EEEE, MMM d, yyyy').format(_selectedDay);

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('daily_logs')
          .where('installer_id', isEqualTo: widget.user.id)
          .where('log_date', isEqualTo: Timestamp.fromDate(dayStart))
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Colors.black87),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Icon(Icons.event_busy, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'No work logged',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You didn\'t clock in on this day',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }

        final data = docs.first.data() as Map<String, dynamic>;
        final entries = List<Map<String, dynamic>>.from(
          data['time_entries'] ?? [],
        );

        // Group by area
        final Map<String, List<Map<String, dynamic>>> areaGroups = {};
        for (final entry in entries) {
          final areaName = entry['areaName'] as String? ?? 'Unknown';
          areaGroups.putIfAbsent(areaName, () => []).add(entry);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            // Area cards (same style as Today's Work)
            ...areaGroups.entries.map((group) {
              final areaName = group.key;
              final sessions = group.value;

              double areaHours = 0;
              double? crewDaysLeftAfter;
              final timeRanges = <String>[];
              final descriptions = <String>[];

              for (final session in sessions) {
                final clockIn = (session['clockIn'] as Timestamp?)?.toDate();
                final clockOut = (session['clockOut'] as Timestamp?)?.toDate();
                final description = session['description'] as String?;
                areaHours += (session['hoursWorked'] ?? 0).toDouble();
                if (session['crewDaysLeftAfter'] != null) {
                  crewDaysLeftAfter = (session['crewDaysLeftAfter'] as num)
                      .toDouble();
                }

                timeRanges.add(
                  '${clockIn != null ? _formatTime(clockIn) : '--'} – ${clockOut != null ? _formatTime(clockOut) : '--'}',
                );

                if (description != null && description.isNotEmpty) {
                  descriptions.add(description);
                }
              }

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            areaName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${areaHours.toStringAsFixed(1)}h',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeRanges.join(', '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    if (descriptions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        descriptions.join(' '),
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                    if (crewDaysLeftAfter != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${crewDaysLeftAfter.toStringAsFixed(1)} crew days to go',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════

  Future<void> _clockIn(Map<String, dynamic> area) async {
    setState(() => _isLoading = true);
    try {
      Position? position = await _getCurrentLocation();
      if (position == null) {
        // User cancelled the location dialog — just abort silently
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await _firestoreService.clockInToArea(
        userId: widget.user.id,
        userName: widget.user.name,
        userRole: widget.user.role,
        areaId: area['id'],
        areaName: area['name'],
        projectId: area['projectId'],
        projectName: area['projectName'],
        levelName: area['levelName'],
        location: GeoPoint(position.latitude, position.longitude),
      );

      setState(() {
        _isClockedIn = true;
        _currentAreaId = area['id'];
        _currentAreaName = area['name'];
        _currentProjectName = area['projectName'];
      });

      _loadAreaInfo(area['id']);
      _loadTodaysState();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Clocked in at ${area['name']}'),
          backgroundColor: Colors.black87,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showClockOutDialog() {
    final List<String> descriptionOptions = [
      'Waterproofing at shower pan',
      'Drain installation at shower pan',
      'Paper & lath',
      'Scratch',
      'Float walls',
      'Hydroban paint',
      'Layout tile',
      'Install tile',
      'Grout',
      'Float shower pan',
      'Float bath floor',
      'Apply grout',
      'Seal the tile',
    ];

    final Set<int> selected = {};

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Clock out of $_currentAreaName',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What did you do?',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: descriptionOptions.length,
                    itemBuilder: (context, index) {
                      final isSelected = selected.contains(index);
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            if (isSelected) {
                              selected.remove(index);
                            } else {
                              selected.add(index);
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.black87
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 20,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[400],
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  descriptionOptions[index],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selected.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select what you did'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                final sortedSelection = selected.toList()..sort();
                final description = sortedSelection
                    .map((i) => descriptionOptions[i])
                    .join(', ');

                Navigator.pop(dialogContext);

                _firestoreService
                    .clockOutOfArea(
                      userId: widget.user.id,
                      description: description,
                    )
                    .then((_) {
                      if (!mounted) return;
                      setState(() {
                        _isClockedIn = false;
                        _currentAreaId = null;
                        _currentAreaName = null;
                        _currentProjectName = null;
                      });
                      _loadTodaysState();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Clocked out'),
                          backgroundColor: Colors.black87,
                        ),
                      );
                    });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
              ),
              child: const Text('Clock Out'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finishDay() async {
    await _firestoreService.completeDayLog(userId: widget.user.id);
    setState(() => _isDayComplete = true);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Day complete! Great work.'),
        backgroundColor: Colors.black87,
      ),
    );
  }

  /// Start lunch while clocked in at an area.
  /// This is a PAUSE — the time entry stays open, lunch time is
  /// subtracted from hours when they eventually clock out.
  Future<void> _startLunchFromArea() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await _db
        .collection('daily_logs')
        .where('installer_id', isEqualTo: widget.user.id)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await snapshot.docs.first.reference.update({
        'is_on_lunch': true,
        'lunch_start': Timestamp.now(),
      });
    }

    setState(() {
      _isOnLunch = true;
      _lunchStartTime = DateTime.now();
      // NOTE: stays clocked in — lunch is just a pause
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Lunch started at ${_formatTime(_lunchStartTime!)}'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _endLunch() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final snapshot = await _db
        .collection('daily_logs')
        .where('installer_id', isEqualTo: widget.user.id)
        .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      await snapshot.docs.first.reference.update({
        'is_on_lunch': false,
        'lunch_end': Timestamp.now(),
      });
    }

    setState(() {
      _isOnLunch = false;
      _hasHadLunch = true;
      _lunchStartTime = null;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Back to work at ${_currentAreaName ?? "your area"}'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  /// Returns null if permission denied (caller handles gracefully).
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled. Please enable them in Settings.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission denied. Please allow location access to clock in.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Location Access Required'),
            content: const Text(
              'You previously denied location access. Epic Installation needs your location to verify you\'re on the job site.\n\nPlease open Settings and enable location for this app.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Geolocator.openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return null; // Silently abort — no error message
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await _authService.signOut();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _buildPillButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.85,
        child: GestureDetector(
          onTap: _isLoading ? null : onTap,
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
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Center(
                    child: Text(
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

  Widget _buildSignOutButton() {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.85,
        child: GestureDetector(
          onTap: _logout,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'sign out',
                style: TextStyle(
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

  String _formatTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
}
