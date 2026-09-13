import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';
import '../../widgets/epic_week_header.dart';

class SupervisorDashboard extends StatefulWidget {
  final UserModel user;
  const SupervisorDashboard({super.key, required this.user});

  @override
  State<SupervisorDashboard> createState() => _SupervisorDashboardState();
}

class _SupervisorDashboardState extends State<SupervisorDashboard>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;

  DateTime _selectedDay = DateTime.now();

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
      backgroundColor: Colors.white,
      body: Column(
        children: [
          EpicWeekHeader(
            userName: widget.user.name,
            userRole: widget.user.role == 'foreman' ? 'Foreman' : 'Supervisor',
            onDaySelected: (day) {
              setState(() => _selectedDay = day);
            },
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.black87,
              labelColor: Colors.black87,
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
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
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
            color: Colors.black87,
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
            fontWeight: FontWeight.w700,
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
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
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
              child: CircularProgressIndicator(color: Colors.black87),
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
        // projectName → levelName → areaName → list of worker sessions
        final Map<String, Map<String, Map<String, List<Map<String, dynamic>>>>>
        grouped = {};

        for (final doc in logs) {
          final data = doc.data() as Map<String, dynamic>;
          final name = data['installer_name'] ?? 'Unknown';
          final role = data['installer_role'] ?? '';
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );

          for (final entry in entries) {
            final projectName =
                entry['projectName'] as String? ?? 'Unknown Site';
            final areaName = entry['areaName'] as String? ?? 'Unknown Area';

            // Look up the level from areas collectio
            String levelName = 'Unassigned';
            // We'll resolve level from the entry or fallback
            if (entry['levelName'] != null) {
              levelName = entry['levelName'] as String;
            }

            grouped
                .putIfAbsent(projectName, () => {})
                .putIfAbsent(levelName, () => {})
                .putIfAbsent(areaName, () => [])
                .add({
                  'name': name,
                  'role': role,
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
            final levels = siteGroup.value;
            int totalWorkers = 0;
            for (final level in levels.values) {
              for (final area in level.values) {
                totalWorkers += area.length;
              }
            }

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
                    backgroundColor: Colors.black87,
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${levels.length} ${levels.length == 1 ? 'level' : 'levels'} \u2022 $totalWorkers ${totalWorkers == 1 ? 'worker' : 'workers'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  children: [
                    ...levels.entries.map((levelGroup) {
                      final levelName = levelGroup.key;
                      final areas = levelGroup.value;
                      int levelWorkers = 0;
                      for (final a in areas.values) {
                        levelWorkers += a.length;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(10),
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
                              8,
                              0,
                              8,
                              8,
                            ),
                            leading: Icon(
                              Icons.layers,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            title: Text(
                              levelName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            subtitle: Text(
                              '${areas.length} ${areas.length == 1 ? 'area' : 'areas'} \u2022 $levelWorkers ${levelWorkers == 1 ? 'worker' : 'workers'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                            children: [
                              ...areas.entries.map((areaGroup) {
                                final areaName = areaGroup.key;
                                final workers = areaGroup.value;
                                final activeCount = workers
                                    .where((w) => w['clockOut'] == null)
                                    .length;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black87.withValues(
                                      alpha: 0.04,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.black87.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                  ),
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      childrenPadding:
                                          const EdgeInsets.fromLTRB(
                                            10,
                                            0,
                                            10,
                                            8,
                                          ),
                                      title: Text(
                                        areaName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${workers.length} ${workers.length == 1 ? 'worker' : 'workers'}${activeCount > 0 ? ' \u2022 $activeCount active' : ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      children: [
                                        ...workers.map((w) {
                                          final wName = w['name'] as String;
                                          final wRole = (w['role'] as String)
                                              .replaceAll('_', ' ');
                                          final clockIn =
                                              (w['clockIn'] as Timestamp?)
                                                  ?.toDate();
                                          final clockOut =
                                              (w['clockOut'] as Timestamp?)
                                                  ?.toDate();
                                          final hours = (w['hoursWorked'] ?? 0)
                                              .toDouble();
                                          final description =
                                              w['description'] as String?;
                                          final isActive = clockOut == null;

                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                                                          ? Colors.green
                                                                .withValues(
                                                                  alpha: 0.15,
                                                                )
                                                          : Colors.grey[200],
                                                      child: Text(
                                                        wName.isNotEmpty
                                                            ? wName[0]
                                                                  .toUpperCase()
                                                            : '?',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isActive
                                                              ? Colors.green
                                                              : Colors
                                                                    .grey[600],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            wName,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                          Text(
                                                            wRole,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors
                                                                  .grey[500],
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
                                                          color: Colors.green
                                                              .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          'Active',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.green,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      )
                                                    else
                                                      Text(
                                                        '${hours.toStringAsFixed(1)}h',
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${clockIn != null ? _formatTime(clockIn) : '--'} \u2013 ${clockOut != null ? _formatTime(clockOut) : 'now'}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                                if (description != null &&
                                                    description.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
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

  // ═══════════════════════════════════════════════════════════
  // TAB 2: JOB SITES — projects + areas + people assignment
  // ═══════════════════════════════════════════════════════════

  Widget _buildJobSitesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getProjects(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.black87),
          );
        }

        final allProjects = snapshot.data?.docs ?? [];

        // Only show job sites that existed by the end of the selected day.
        // Sites created after the viewed date don't appear in the past.
        final endOfSelectedDay = DateTime(
          _selectedDay.year,
          _selectedDay.month,
          _selectedDay.day,
        ).add(const Duration(days: 1));

        final projects = allProjects
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final createdAt = (data['created_at'] as Timestamp?)?.toDate();
              // Sites without a timestamp (pending server write) show only on today
              if (createdAt == null) {
                final now = DateTime.now();
                return _selectedDay.year == now.year &&
                    _selectedDay.month == now.month &&
                    _selectedDay.day == now.day;
              }
              return createdAt.isBefore(endOfSelectedDay);
            })
            .where((doc) {
              // Foremen only see their assigned sites
              if (widget.user.role == 'foreman') {
                final data = doc.data() as Map<String, dynamic>;
                final assignedForemen = List<String>.from(
                  data['assignedForemen'] ?? [],
                );
                return assignedForemen.contains(widget.user.id);
              }
              return true; // Supervisors see all
            })
            .toList();

        // Split into active and completed
        final activeProjects = projects.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'active') == 'active';
        }).toList();
        final completedProjects = projects.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'active') != 'active';
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            else ...[
              // ─── Active job sites ─────────────────
              ...activeProjects.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _buildJobSiteCard(doc.id, data);
              }),

              // ─── Completed section (collapsed) ────
              if (completedProjects.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
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
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[400],
                        radius: 17,
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        'Completed',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      subtitle: Text(
                        '${completedProjects.length} job ${completedProjects.length == 1 ? 'site' : 'sites'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      children: completedProjects.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return _buildJobSiteCard(doc.id, data);
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ],

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
    final isActive = status == 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: CircleAvatar(
            backgroundColor: isActive ? Colors.black87 : Colors.grey,
            radius: 17,
            child: const Icon(Icons.location_on, color: Colors.white, size: 18),
          ),
          title: Text(
            name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            location.isNotEmpty ? location : 'No location',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          trailing: GestureDetector(
            onTap: () => _firestoreService.updateProjectStatus(
              projectId: projectId,
              status: isActive ? 'completed' : 'active',
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.black87.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: isActive ? Colors.black87 : Colors.grey[600],
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          children: [
            // Areas list
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
                  children: _groupAreasByLevel(areas, projectId, name),
                );
              },
            ),

            const SizedBox(height: 10),
            Wrap(
              children: [
                if (widget.user.role == 'supervisor') ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _showAssignWorkersToSiteDialog(projectId, name),
                    icon: const Icon(Icons.group_add, size: 16),
                    label: const Text(
                      'Assign Workers',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black87),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showAssignForemanDialog(projectId, name),
                    icon: const Icon(Icons.person_pin, size: 16),
                    label: const Text(
                      'Assign Foreman',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black87),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupAreasByLevel(
    List<QueryDocumentSnapshot> areas,
    String projectId,
    String projectName,
  ) {
    // Group areas by level
    final Map<String, List<QueryDocumentSnapshot>> levelGroups = {};
    for (final area in areas) {
      final data = area.data() as Map<String, dynamic>;
      final level = data['levelName'] as String? ?? 'Unassigned';
      levelGroups.putIfAbsent(level, () => []).add(area);
    }

    return levelGroups.entries.map((group) {
      final levelName = group.key;
      final levelAreas = group.value;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            leading: Icon(Icons.layers, size: 18, color: Colors.grey[600]),
            title: Text(
              levelName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            subtitle: Text(
              '${levelAreas.length} ${levelAreas.length == 1 ? 'area' : 'areas'}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            children: levelAreas.map((areaDoc) {
              final areaData = areaDoc.data() as Map<String, dynamic>;
              final areaName = areaData['name'] ?? '';
              final est = (areaData['totalCrewDays'] ?? 0).toDouble();
              final consumed = (areaData['consumedCrewDays'] ?? 0).toDouble();
              final progress = est > 0 ? (consumed / est).clamp(0.0, 1.0) : 0.0;
              final people = List<String>.from(
                areaData['assignedPeople'] ?? [],
              );
              final isDone = progress >= 1.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    _showAreaDetailSheet(
                      areaDoc.id,
                      areaData,
                      projectId,
                      projectName,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // Status icon
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isDone
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.black87.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isDone ? Icons.check : Icons.construction,
                            size: 16,
                            color: isDone ? Colors.green : Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Area name + people
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                areaName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                people.isEmpty
                                    ? 'No one assigned'
                                    : '${people.length} ${people.length == 1 ? 'person' : 'people'} assigned',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Crew days pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDone
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isDone
                                ? 'Done'
                                : '${(est - consumed).toStringAsFixed(1)} days',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDone ? Colors.green : Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }).toList();
  }

  void _showAreaDetailSheet(
    String areaId,
    Map<String, dynamic> data,
    String projectId,
    String projectName,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey[200]),
              // Area card content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildAreaCard(areaId, data, projectId, projectName),
                ),
              ),
            ],
          ),
        );
      },
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
        color: Colors.black87.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black87.withValues(alpha: 0.1)),
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
                    fontWeight: FontWeight.w600,
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
                progress >= 1.0 ? Colors.green : Colors.black87,
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
                onTap: () => _showAssignPeopleDialog(
                  areaId,
                  areaName,
                  assignedPeople,
                  projectId,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
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

  void _showAssignWorkersToSiteDialog(String projectId, String projectName) {
    showDialog(
      context: context,
      builder: (dialogContext) => StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('users')
            .where('role', whereIn: ['installer', 'junior_installer', 'helper'])
            .snapshots(),
        builder: (context, snapshot) {
          final workers = snapshot.data?.docs ?? [];

          return StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('projects').doc(projectId).snapshots(),
            builder: (context, projectSnap) {
              final projectData =
                  projectSnap.data?.data() as Map<String, dynamic>? ?? {};
              final assignedWorkers = List<String>.from(
                projectData['assignedWorkers'] ?? [],
              );

              return AlertDialog(
                title: Text('Assign Workers to $projectName'),
                content: SizedBox(
                  width: 350,
                  height: 400,
                  child: workers.isEmpty
                      ? const Center(
                          child: Text(
                            'No workers registered yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView(
                          children: workers.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = data['name'] ?? 'Unknown';
                            final role = (data['role'] ?? '').replaceAll(
                              '_',
                              ' ',
                            );
                            final isAssigned = assignedWorkers.contains(doc.id);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isAssigned
                                    ? Colors.black87
                                    : Colors.grey[200],
                                radius: 16,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isAssigned
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                role,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                              trailing: Icon(
                                isAssigned
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: isAssigned
                                    ? Colors.black87
                                    : Colors.grey[400],
                                size: 22,
                              ),
                              onTap: () {
                                if (isAssigned) {
                                  _firestoreService.removeWorkerFromProject(
                                    projectId: projectId,
                                    workerId: doc.id,
                                  );
                                } else {
                                  _firestoreService.assignWorkerToProject(
                                    projectId: projectId,
                                    workerId: doc.id,
                                  );
                                }
                              },
                            );
                          }).toList(),
                        ),
                ),
                actions: [
                  Text(
                    '${assignedWorkers.length} assigned',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showAssignForemanDialog(String projectId, String projectName) {
    showDialog(
      context: context,
      builder: (dialogContext) => StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('users')
            .where('role', isEqualTo: 'foreman')
            .snapshots(),
        builder: (context, snapshot) {
          final foremen = snapshot.data?.docs ?? [];

          return StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('projects').doc(projectId).snapshots(),
            builder: (context, projectSnap) {
              final projectData =
                  projectSnap.data?.data() as Map<String, dynamic>? ?? {};
              final assignedForemen = List<String>.from(
                projectData['assignedForemen'] ?? [],
              );

              return AlertDialog(
                title: Text('Assign Foreman to $projectName'),
                content: SizedBox(
                  width: 300,
                  child: foremen.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No foremen registered yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: foremen.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = data['name'] ?? 'Unknown';
                            final isAssigned = assignedForemen.contains(doc.id);

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isAssigned
                                    ? Colors.black87
                                    : Colors.grey[200],
                                radius: 16,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isAssigned
                                        ? Colors.white
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: Icon(
                                isAssigned
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: isAssigned
                                    ? Colors.black87
                                    : Colors.grey[400],
                                size: 22,
                              ),
                              onTap: () {
                                if (isAssigned) {
                                  _firestoreService.removeForemanFromProject(
                                    projectId: projectId,
                                    foremanId: doc.id,
                                  );
                                } else {
                                  _firestoreService.assignForemanToProject(
                                    projectId: projectId,
                                    foremanId: doc.id,
                                  );
                                }
                              },
                            );
                          }).toList(),
                        ),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          );
        },
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
        title: const Text('Edit Area', style: TextStyle(color: Colors.black87)),
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
              backgroundColor: Colors.black87,
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
    String projectId,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('projects').doc(projectId).snapshots(),
          builder: (context, projectSnap) {
            final projectData =
                projectSnap.data?.data() as Map<String, dynamic>? ?? {};
            final siteWorkers = List<String>.from(
              projectData['assignedWorkers'] ?? [],
            );

            return AlertDialog(
              title: Text(
                'Assign to $areaName',
                style: const TextStyle(color: Colors.black87, fontSize: 16),
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
                    var users = snapshot.data?.docs ?? [];

                    // Foremen only see workers assigned to this site
                    if (widget.user.role == 'foreman' &&
                        siteWorkers.isNotEmpty) {
                      users = users
                          .where((doc) => siteWorkers.contains(doc.id))
                          .toList();
                    }

                    if (users.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          widget.user.role == 'foreman'
                              ? 'No workers assigned to this site yet.\nAsk the Supervisor to assign workers.'
                              : 'No installers found',
                          style: TextStyle(color: Colors.grey[500]),
                          textAlign: TextAlign.center,
                        ),
                      );
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
                                    ? Colors.black87
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
                                    fontWeight: FontWeight.w600,
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
                                      color: Colors.black87,
                                      size: 22,
                                    )
                                  : Icon(
                                      Icons.add_circle_outline,
                                      color: Colors.grey[400],
                                      size: 22,
                                    ),
                              onTap: () {
                                if (isAssigned) {
                                  setDialogState(
                                    () => currentPeople.remove(userId),
                                  );
                                  _firestoreService.removePersonFromArea(
                                    areaId: areaId,
                                    userId: userId,
                                  );
                                } else {
                                  setDialogState(
                                    () => currentPeople.add(userId),
                                  );
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
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
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
        final data = doc.data();

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
