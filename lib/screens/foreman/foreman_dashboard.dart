import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';
import '../../widgets/epic_week_header.dart';

class ForemanDashboard extends StatefulWidget {
  final UserModel user;
  const ForemanDashboard({super.key, required this.user});

  @override
  State<ForemanDashboard> createState() => _ForemanDashboardState();
}

class _ForemanDashboardState extends State<ForemanDashboard>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;

  static const Color _purple = Color(0xFF7440D8);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      body: Column(
        children: [
          EpicWeekHeader(userName: widget.user.name, userRole: 'Supervisor'),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _purple,
              labelColor: _purple,
              unselectedLabelColor: Colors.grey[500],
              indicatorWeight: 2.5,
              tabs: const [
                Tab(text: 'My Crew'),
                Tab(text: 'Job Sites'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildCrewTab(), _buildJobSitesTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 1: MY CREW — today's overview + live activity
  // ═══════════════════════════════════════════════════════════

  Widget _buildCrewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTodayStats(),
        const SizedBox(height: 20),
        const Text(
          'Installer Activity',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _buildInstallerFeed(),
        const SizedBox(height: 40),
        _buildSignOutButton(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTodayStats() {
    final todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('daily_logs')
          .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
          .snapshots(),
      builder: (context, snapshot) {
        final logs = snapshot.data?.docs ?? [];

        int activeNow = 0;
        int doneToday = 0;
        double totalHours = 0;

        for (final doc in logs) {
          final data = doc.data() as Map<String, dynamic>;
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );
          final isDayComplete = data['is_day_complete'] ?? false;
          final hasOpenEntry =
              entries.isNotEmpty && entries.last['clockOut'] == null;

          if (hasOpenEntry) {
            activeNow++;
          }
          if (isDayComplete) {
            doneToday++;
          }

          for (final entry in entries) {
            totalHours += (entry['hoursWorked'] ?? 0).toDouble();
          }
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _purple,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Today\'s Overview',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildOverviewStat(
                    '$activeNow',
                    'Working',
                    Icons.engineering,
                  ),
                  _buildOverviewStat(
                    '${logs.length}',
                    'Logged In',
                    Icons.people,
                  ),
                  _buildOverviewStat(
                    '$doneToday',
                    'Done',
                    Icons.check_circle_outline,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.schedule, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${totalHours.toStringAsFixed(1)} hours logged today',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildInstallerFeed() {
    final todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('daily_logs')
          .where('log_date', isEqualTo: Timestamp.fromDate(todayStart))
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _purple),
            ),
          );
        }

        final logs = snapshot.data?.docs ?? [];

        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'No installers clocked in yet',
                  style: TextStyle(color: Colors.grey[500], fontSize: 15),
                ),
              ],
            ),
          );
        }

        // Flatten every time entry into a record, then group:
        // projectName → areaName → list of worker sessions
        final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

        for (final doc in logs) {
          final data = doc.data() as Map<String, dynamic>;
          final name = data['installer_name'] ?? 'Unknown';
          final role = data['installer_role'] ?? '';
          final photoUrl = data['photo_url'] as String?;
          final isDayComplete = data['is_day_complete'] ?? false;
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );

          for (final entry in entries) {
            final projectName =
                entry['projectName'] as String? ?? 'Unknown Site';
            final areaName = entry['areaName'] as String? ?? 'Unknown Area';

            grouped
                .putIfAbsent(projectName, () => {})
                .putIfAbsent(areaName, () => [])
                .add({
                  'name': name,
                  'role': role,
                  'photoUrl': photoUrl,
                  'isDayComplete': isDayComplete,
                  'clockIn': entry['clockIn'],
                  'clockOut': entry['clockOut'],
                  'hoursWorked': entry['hoursWorked'],
                  'description': entry['description'],
                });
          }
        }

        if (grouped.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 56, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'Installers logged in — no area activity yet',
                  style: TextStyle(color: Colors.grey[500], fontSize: 15),
                ),
              ],
            ),
          );
        }

        return Column(
          children: grouped.entries.map((siteGroup) {
            final siteName = siteGroup.key;
            final areas = siteGroup.value;
            final totalWorkers = areas.values.fold<int>(
              0,
              (sum, w) => sum + w.length,
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  leading: const CircleAvatar(
                    backgroundColor: _purple,
                    radius: 17,
                    child: Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    siteName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${areas.length} ${areas.length == 1 ? 'area' : 'areas'} • $totalWorkers ${totalWorkers == 1 ? 'worker' : 'workers'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  children: [
                    // ─── Areas: tap to expand workers ────
                    ...areas.entries.map((areaGroup) {
                      final areaName = areaGroup.key;
                      final workers = areaGroup.value;
                      final activeCount = workers
                          .where((w) => w['clockOut'] == null)
                          .length;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _purple.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              10,
                              0,
                              10,
                              8,
                            ),
                            title: Text(
                              areaName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _purple,
                              ),
                            ),
                            subtitle: Text(
                              '${workers.length} ${workers.length == 1 ? 'worker' : 'workers'}${activeCount > 0 ? ' • $activeCount active' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                            children: [
                              // ─── Workers at this area ────
                              ...workers.map((w) {
                                final wName = w['name'] as String;
                                final wRole = (w['role'] as String).replaceAll(
                                  '_',
                                  ' ',
                                );
                                final clockIn = (w['clockIn'] as Timestamp?)
                                    ?.toDate();
                                final clockOut = (w['clockOut'] as Timestamp?)
                                    ?.toDate();
                                final hours = (w['hoursWorked'] ?? 0)
                                    .toDouble();
                                final description = w['description'] as String?;
                                final photoUrl = w['photoUrl'] as String?;
                                final isActive = clockOut == null;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 13,
                                            backgroundColor: isActive
                                                ? Colors.green.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : Colors.grey[200],
                                            child: Text(
                                              wName.isNotEmpty
                                                  ? wName[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: isActive
                                                    ? Colors.green
                                                    : Colors.grey[600],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  wName,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  wRole,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isActive)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
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
                                              '${hours.toStringAsFixed(1)}h',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _purple,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${clockIn != null ? _formatTime(clockIn) : '--'} – ${clockOut != null ? _formatTime(clockOut) : 'now'}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      if (description != null &&
                                          description.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 3,
                                          ),
                                          child: Text(
                                            description,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      if (photoUrl != null && !isActive)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: GestureDetector(
                                            onTap: () =>
                                                _showFullPhoto(photoUrl),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.photo_camera,
                                                  size: 14,
                                                  color: _purple.withValues(
                                                    alpha: 0.7,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Text(
                                                  'View day photo',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: _purple,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showFullPhoto(String url) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Progress Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(dialogContext),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: Image.network(
                url,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TAB 2: JOB SITES — projects + areas + people assignment
  // ═══════════════════════════════════════════════════════════

  Widget _buildJobSitesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getProjects(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }

        final projects = snapshot.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Add Job Site
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _showAddJobSiteDialog,
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add Job Site',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (projects.isEmpty)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.construction, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      'No job sites yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
            else
              ...projects.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _buildJobSiteCard(doc.id, data);
              }),

            const SizedBox(height: 40),
            _buildSignOutButton(),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildJobSiteCard(String projectId, Map<String, dynamic> data) {
    final name = data['name'] ?? 'Unknown';
    final location = data['location'] ?? '';
    final status = data['status'] ?? 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: status == 'active' ? _purple : Colors.grey,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _firestoreService.updateProjectStatus(
                    projectId: projectId,
                    status: status == 'active' ? 'completed' : 'active',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Areas list
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: _firestoreService.getAreasForProject(projectId),
                  builder: (context, areaSnap) {
                    final areas = areaSnap.data?.docs ?? [];

                    if (areas.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.grid_view,
                              size: 32,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No areas yet',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: areas.map((areaDoc) {
                        final areaData = areaDoc.data() as Map<String, dynamic>;
                        return _buildAreaCard(
                          areaDoc.id,
                          areaData,
                          projectId,
                          name,
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _showAddAreaDialog(projectId, name),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Area', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _purple),
                    foregroundColor: _purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaCard(
    String areaId,
    Map<String, dynamic> data,
    String projectId,
    String projectName,
  ) {
    final areaName = data['name'] ?? '';
    final totalCrewDays = (data['totalCrewDays'] ?? 0).toDouble();
    final consumed = (data['consumedCrewDays'] ?? 0).toDouble();
    final remaining = totalCrewDays - consumed;
    final assignedPeople = List<String>.from(data['assignedPeople'] ?? []);
    final progress = totalCrewDays > 0
        ? (consumed / totalCrewDays).clamp(0.0, 1.0)
        : 0.0;
    // Crew days left at current crew size: remaining labor ÷ pairs
    final pairs = assignedPeople.length / 2;
    final crewDaysLeft = pairs > 0 ? remaining / pairs : remaining;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _purple.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Area name + crew days
          Row(
            children: [
              Expanded(
                child: Text(
                  areaName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${crewDaysLeft.toStringAsFixed(1)} crew days left • ${totalCrewDays.toStringAsFixed(0)} est.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0 ? Colors.green : _purple,
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),

          // People + estimated days
          Row(
            children: [
              Icon(Icons.person, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                '${assignedPeople.length} people',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                '~${crewDaysLeft.ceil()} days to go',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),

          // Assigned people names
          if (assignedPeople.isNotEmpty) ...[
            const SizedBox(height: 6),
            FutureBuilder<List<Map<String, String>>>(
              future: _getPeopleInfo(assignedPeople),
              builder: (context, snap) {
                final people = snap.data ?? [];
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: people.map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(
                        '${p['name']}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],

          const SizedBox(height: 8),

          // Action buttons
          Row(
            children: [
              GestureDetector(
                onTap: () =>
                    _showAssignPeopleDialog(areaId, areaName, assignedPeople),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _purple,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Assign',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showEditAreaDialog(areaId, data),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Edit',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════

  void _showAddJobSiteDialog() {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Job Site', style: TextStyle(color: _purple)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Job Site Name',
                  hintText: 'e.g. Hilton Lobby',
                  prefixIcon: const Icon(Icons.business),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                decoration: InputDecoration(
                  labelText: 'Location',
                  hintText: 'e.g. Las Vegas, NV',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              final navigator = Navigator.of(dialogContext);
              await _firestoreService.addProject(
                name: nameCtrl.text.trim(),
                location: locationCtrl.text.trim(),
              );
              navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddAreaDialog(String projectId, String projectName) {
    final nameCtrl = TextEditingController();
    final crewDaysCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Area', style: TextStyle(color: _purple)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Area Name',
                  hintText: 'e.g. Master Bathroom',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: crewDaysCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Estimated Crew Days',
                  hintText: 'e.g. 6',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
            onPressed: () async {
              if (nameCtrl.text.isEmpty || crewDaysCtrl.text.isEmpty) return;
              final navigator = Navigator.of(dialogContext);
              await _firestoreService.addArea(
                projectId: projectId,
                projectName: projectName,
                areaName: nameCtrl.text.trim(),
                totalCrewDays: double.tryParse(crewDaysCtrl.text) ?? 0,
              );
              navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditAreaDialog(String areaId, Map<String, dynamic> data) {
    final nameCtrl = TextEditingController(text: data['name']);
    final crewDaysCtrl = TextEditingController(
      text: (data['totalCrewDays'] ?? 0).toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Area', style: TextStyle(color: _purple)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Area Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: crewDaysCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Total Crew Days',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Delete area (with confirmation)
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Delete Area?'),
                  content: Text(
                    'This will permanently remove "${data['name']}". '
                    'Past work logs are kept, but assigned people will lose '
                    'this area. This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final confirmNav = Navigator.of(confirmContext);
                        final editNav = Navigator.of(dialogContext);
                        await _firestoreService.deleteArea(areaId);
                        confirmNav.pop();
                        editNav.pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
            label: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              await _firestoreService.updateArea(
                areaId: areaId,
                name: nameCtrl.text.trim(),
                totalCrewDays: double.tryParse(crewDaysCtrl.text) ?? 0,
              );
              navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAssignPeopleDialog(
    String areaId,
    String areaName,
    List<String> currentPeople,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Assign to $areaName',
          style: const TextStyle(color: _purple, fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: _db
                .collection('users')
                .where(
                  'role',
                  whereIn: ['installer', 'junior_installer', 'helper'],
                )
                .snapshots(),
            builder: (context, snapshot) {
              final users = snapshot.data?.docs ?? [];

              if (users.isEmpty) {
                return const Text('No installers found');
              }

              return StatefulBuilder(
                builder: (context, setDialogState) {
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final userData =
                          users[index].data() as Map<String, dynamic>;
                      final userId = users[index].id;
                      final userName = userData['name'] ?? 'Unknown';
                      final userRole = userData['role'] ?? '';
                      final isAssigned = currentPeople.contains(userId);

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isAssigned
                              ? _purple
                              : Colors.grey[200],
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: isAssigned
                                  ? Colors.white
                                  : Colors.grey[600],
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          userName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          userRole.replaceAll('_', ' '),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                        trailing: isAssigned
                            ? const Icon(
                                Icons.check_circle,
                                color: _purple,
                                size: 22,
                              )
                            : Icon(
                                Icons.add_circle_outline,
                                color: Colors.grey[400],
                                size: 22,
                              ),
                        onTap: () {
                          // Update UI immediately, then write to Firestore.
                          // This avoids setState-after-dispose if the dialog
                          // closes while the writes are in flight.
                          if (isAssigned) {
                            setDialogState(() => currentPeople.remove(userId));
                            _firestoreService.removePersonFromArea(
                              areaId: areaId,
                              userId: userId,
                            );
                          } else {
                            setDialogState(() => currentPeople.add(userId));
                            _firestoreService.addPersonToArea(
                              areaId: areaId,
                              userId: userId,
                            );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════

  Future<List<Map<String, String>>> _getPeopleInfo(List<String> ids) async {
    final people = <Map<String, String>>[];
    for (final id in ids) {
      try {
        final doc = await _db.collection('users').doc(id).get();
        final data = doc.data() as Map<String, dynamic>?;
        people.add({
          'name': data?['name'] ?? 'Unknown',
          'role': data?['role'] ?? '',
        });
      } catch (_) {
        people.add({'name': 'Unknown', 'role': ''});
      }
    }
    return people;
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await _authService.signOut();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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
