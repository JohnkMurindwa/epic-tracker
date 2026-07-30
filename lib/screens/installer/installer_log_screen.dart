import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';

class InstallerLogScreen extends StatefulWidget {
  final UserModel user;
  const InstallerLogScreen({super.key, required this.user});

  @override
  State<InstallerLogScreen> createState() => _InstallerLogScreenState();
}

class _InstallerLogScreenState extends State<InstallerLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // For week/month navigation
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  static DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        title: const Text('My Work Log'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDailyView(), _buildWeeklyView(), _buildMonthlyView()],
      ),
    );
  }

  // ─── DAILY VIEW ─────────────────────────────────────────────

  Widget _buildDailyView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('daily_logs')
          .where('installer_id', isEqualTo: widget.user.id)
          .orderBy('clock_in', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.deepOrange),
          );
        }

        final logs = snapshot.data?.docs ?? [];

        if (logs.isEmpty) {
          return _buildEmptyState(
            'No daily logs yet',
            'Your work history will appear here after your first shift.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final data = logs[index].data() as Map<String, dynamic>;
            return _buildDayCard(data);
          },
        );
      },
    );
  }

  Widget _buildDayCard(Map<String, dynamic> data) {
    final clockIn = (data['clock_in'] as Timestamp?)?.toDate();
    final clockOut = (data['clock_out'] as Timestamp?)?.toDate();
    final morningSqft = (data['morning_sqft'] ?? 0).toDouble();
    final afternoonSqft = (data['afternoon_sqft'] ?? 0).toDouble();
    final totalSqft = morningSqft + afternoonSqft;
    final morningPhotoUrl = data['morning_photo_url'] as String?;
    final afternoonPhotoUrl = data['afternoon_photo_url'] as String?;

    final dateStr = clockIn != null
        ? DateFormat('EEEE, MMM d').format(clockIn)
        : 'Unknown Date';

    String hoursWorked = '--';
    if (clockIn != null && clockOut != null) {
      final duration = clockOut.difference(clockIn);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      hoursWorked = '${hours}h ${minutes}m';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  clockIn != null ? DateFormat('d').format(clockIn) : '--',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.deepOrange,
                  ),
                ),
                Text(
                  clockIn != null ? DateFormat('MMM').format(clockIn) : '',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            dateStr,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Row(
            children: [
              _buildMiniStat(
                Icons.straighten,
                '${totalSqft.toStringAsFixed(0)} sqft',
              ),
              const SizedBox(width: 12),
              _buildMiniStat(Icons.schedule, hoursWorked),
            ],
          ),
          children: [
            // Time details
            _buildDetailRow(
              'Clock In',
              clockIn != null ? _formatTime(clockIn) : '--',
              Icons.login_rounded,
              Colors.green,
            ),
            _buildDetailRow(
              'Clock Out',
              clockOut != null ? _formatTime(clockOut) : '--',
              Icons.logout_rounded,
              Colors.red,
            ),
            _buildDetailRow(
              'Hours Worked',
              hoursWorked,
              Icons.timer_outlined,
              Colors.blue,
            ),
            const Divider(height: 24),

            // Sqft breakdown
            _buildDetailRow(
              'Morning Sqft',
              '${morningSqft.toStringAsFixed(1)} sqft',
              Icons.wb_sunny_outlined,
              Colors.orange,
            ),
            _buildDetailRow(
              'Afternoon Sqft',
              '${afternoonSqft.toStringAsFixed(1)} sqft',
              Icons.wb_twilight,
              Colors.deepPurple,
            ),
            _buildDetailRow(
              'Total Sqft',
              '${totalSqft.toStringAsFixed(1)} sqft',
              Icons.straighten,
              Colors.deepOrange,
            ),

            // Photos
            if (morningPhotoUrl != null || afternoonPhotoUrl != null) ...[
              const Divider(height: 24),
              const Text(
                'Progress Photos',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (morningPhotoUrl != null)
                    Expanded(
                      child: _buildPhotoThumbnail('Morning', morningPhotoUrl),
                    ),
                  if (morningPhotoUrl != null && afternoonPhotoUrl != null)
                    const SizedBox(width: 10),
                  if (afternoonPhotoUrl != null)
                    Expanded(
                      child: _buildPhotoThumbnail(
                        'Afternoon',
                        afternoonPhotoUrl,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── WEEKLY VIEW ────────────────────────────────────────────

  Widget _buildWeeklyView() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final weekLabel =
        '${DateFormat('MMM d').format(_selectedWeekStart)} – ${DateFormat('MMM d').format(weekEnd)}';

    return Column(
      children: [
        // Week navigator
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _selectedWeekStart = _selectedWeekStart.subtract(
                      const Duration(days: 7),
                    );
                  });
                },
              ),
              Text(
                weekLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed:
                    _selectedWeekStart
                        .add(const Duration(days: 7))
                        .isAfter(DateTime.now())
                    ? null
                    : () {
                        setState(() {
                          _selectedWeekStart = _selectedWeekStart.add(
                            const Duration(days: 7),
                          );
                        });
                      },
              ),
            ],
          ),
        ),

        // Weekly data
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection('daily_logs')
                .where('installer_id', isEqualTo: widget.user.id)
                .where(
                  'clock_in',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(
                    _selectedWeekStart,
                  ),
                )
                .where(
                  'clock_in',
                  isLessThan: Timestamp.fromDate(
                    _selectedWeekStart.add(const Duration(days: 7)),
                  ),
                )
                .orderBy('clock_in', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepOrange),
                );
              }

              final logs = snapshot.data?.docs ?? [];

              if (logs.isEmpty) {
                return _buildEmptyState(
                  'No logs this week',
                  'Nothing recorded for $weekLabel',
                );
              }

              // Calculate weekly totals
              double totalSqft = 0;
              Duration totalHours = Duration.zero;
              int daysWorked = logs.length;

              for (final doc in logs) {
                final data = doc.data() as Map<String, dynamic>;
                totalSqft += (data['morning_sqft'] ?? 0).toDouble();
                totalSqft += (data['afternoon_sqft'] ?? 0).toDouble();
                final clockIn = (data['clock_in'] as Timestamp?)?.toDate();
                final clockOut = (data['clock_out'] as Timestamp?)?.toDate();
                if (clockIn != null && clockOut != null) {
                  totalHours += clockOut.difference(clockIn);
                }
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Weekly summary card
                  _buildWeeklySummaryCard(
                    totalSqft: totalSqft,
                    totalHours: totalHours,
                    daysWorked: daysWorked,
                  ),
                  const SizedBox(height: 16),

                  // Daily breakdown
                  const Text(
                    'Daily Breakdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...logs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return _buildCompactDayRow(data);
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklySummaryCard({
    required double totalSqft,
    required Duration totalHours,
    required int daysWorked,
  }) {
    final hours = totalHours.inHours;
    final minutes = totalHours.inMinutes % 60;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.deepOrange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryStatItem(
            value: totalSqft.toStringAsFixed(0),
            unit: 'sqft',
            icon: Icons.straighten,
          ),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildSummaryStatItem(
            value: '${hours}h ${minutes}m',
            unit: 'hours',
            icon: Icons.schedule,
          ),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildSummaryStatItem(
            value: '$daysWorked',
            unit: 'days',
            icon: Icons.calendar_today,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatItem({
    required String value,
    required String unit,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(unit, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }

  Widget _buildCompactDayRow(Map<String, dynamic> data) {
    final clockIn = (data['clock_in'] as Timestamp?)?.toDate();
    final clockOut = (data['clock_out'] as Timestamp?)?.toDate();
    final morningSqft = (data['morning_sqft'] ?? 0).toDouble();
    final afternoonSqft = (data['afternoon_sqft'] ?? 0).toDouble();
    final totalSqft = morningSqft + afternoonSqft;

    String hoursWorked = '--';
    if (clockIn != null && clockOut != null) {
      final duration = clockOut.difference(clockIn);
      hoursWorked = '${duration.inHours}h ${duration.inMinutes % 60}m';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Day label
          SizedBox(
            width: 40,
            child: Text(
              clockIn != null ? DateFormat('E').format(clockIn) : '--',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          // Time range
          Expanded(
            child: Text(
              clockIn != null && clockOut != null
                  ? '${_formatTime(clockIn)} – ${_formatTime(clockOut)}'
                  : '--',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          // Sqft
          Text(
            '${totalSqft.toStringAsFixed(0)} sqft',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.deepOrange,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          // Hours
          Text(
            hoursWorked,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ─── MONTHLY VIEW ──────────────────────────────────────────

  Widget _buildMonthlyView() {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Column(
      children: [
        // Month navigator
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
              ),
              Text(
                monthLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed:
                    DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    ).isAfter(DateTime.now())
                    ? null
                    : () {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month + 1,
                          );
                        });
                      },
              ),
            ],
          ),
        ),

        // Monthly data
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection('daily_logs')
                .where('installer_id', isEqualTo: widget.user.id)
                .where(
                  'clock_in',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedMonth),
                )
                .where(
                  'clock_in',
                  isLessThan: Timestamp.fromDate(
                    DateTime(_selectedMonth.year, _selectedMonth.month + 1),
                  ),
                )
                .orderBy('clock_in', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.deepOrange),
                );
              }

              final logs = snapshot.data?.docs ?? [];

              if (logs.isEmpty) {
                return _buildEmptyState(
                  'No logs this month',
                  'Nothing recorded for $monthLabel',
                );
              }

              // Monthly totals
              double totalSqft = 0;
              Duration totalHours = Duration.zero;
              int daysWorked = logs.length;

              // Group by week for breakdown
              final Map<int, List<Map<String, dynamic>>> weekGroups = {};

              for (final doc in logs) {
                final data = doc.data() as Map<String, dynamic>;
                final mSqft = (data['morning_sqft'] ?? 0).toDouble();
                final aSqft = (data['afternoon_sqft'] ?? 0).toDouble();
                totalSqft += mSqft + aSqft;

                final clockIn = (data['clock_in'] as Timestamp?)?.toDate();
                final clockOut = (data['clock_out'] as Timestamp?)?.toDate();
                if (clockIn != null && clockOut != null) {
                  totalHours += clockOut.difference(clockIn);
                }

                // Group by week number
                if (clockIn != null) {
                  final weekOfMonth = ((clockIn.day - 1) / 7).floor() + 1;
                  weekGroups.putIfAbsent(weekOfMonth, () => []).add(data);
                }
              }

              final hours = totalHours.inHours;
              final minutes = totalHours.inMinutes % 60;
              final avgSqftPerDay = daysWorked > 0
                  ? totalSqft / daysWorked
                  : 0.0;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Monthly summary
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryStatItem(
                              value: totalSqft.toStringAsFixed(0),
                              unit: 'total sqft',
                              icon: Icons.straighten,
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white30,
                            ),
                            _buildSummaryStatItem(
                              value: '${hours}h ${minutes}m',
                              unit: 'total hours',
                              icon: Icons.schedule,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                '$daysWorked days worked',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '~${avgSqftPerDay.toStringAsFixed(0)} sqft/day avg',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Weekly breakdown
                  const Text(
                    'Week by Week',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),

                  ...weekGroups.entries.map((entry) {
                    final weekNum = entry.key;
                    final weekLogs = entry.value;

                    double weekSqft = 0;
                    Duration weekHours = Duration.zero;
                    for (final log in weekLogs) {
                      weekSqft += (log['morning_sqft'] ?? 0).toDouble();
                      weekSqft += (log['afternoon_sqft'] ?? 0).toDouble();
                      final ci = (log['clock_in'] as Timestamp?)?.toDate();
                      final co = (log['clock_out'] as Timestamp?)?.toDate();
                      if (ci != null && co != null) {
                        weekHours += co.difference(ci);
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                'W$weekNum',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.deepOrange,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${weekLogs.length} days worked',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${weekHours.inHours}h ${weekHours.inMinutes % 60}m total',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${weekSqft.toStringAsFixed(0)} sqft',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.deepOrange,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── SHARED HELPERS ─────────────────────────────────────────

  Widget _buildMiniStat(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumbnail(String label, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            height: 100,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              color: Colors.grey[500],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
        ],
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
