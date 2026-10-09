import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../auth/login_screen.dart';
import '../../widgets/epic_week_header.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/language_toggle.dart';
import '../../services/app_strings.dart';
import 'foreman_time_tab.dart';

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

  /// Foremen also clock in, so they get a "My Time" tab first.
  bool get _isForeman => widget.user.role == 'foreman';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isForeman ? 3 : 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const OfflineBanner(),
          EpicWeekHeader(
            userName: widget.user.name,
            userRole: AppStrings.role(
              widget.user.role == 'foreman' ? 'foreman' : 'supervisor',
            ),
            onDaySelected: (day) {
              setState(() => _selectedDay = day);
            },
            onAvatarTap: _showProfileSheet,
          ),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.black87,
              labelColor: Colors.black87,
              unselectedLabelColor: Colors.grey[500],
              indicatorWeight: 2.5,
              tabs: [
                if (_isForeman) Tab(text: tr('My Time', 'Mi Tiempo')),
                Tab(text: tr('My Crew', 'Mi Equipo')),
                Tab(text: tr('Job Sites', 'Obras')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                if (_isForeman) ForemanTimeTab(user: widget.user),
                _buildCrewTab(),
                _buildJobSitesTab(),
              ],
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
        Text(
          tr('Installer Activity', 'Actividad de Instaladores'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _buildInstallerFeed(),
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
              Text(
                tr('Today\'s Overview', 'Resumen de Hoy'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildOverviewStat(
                    '$activeNow',
                    tr('Working', 'Trabajando'),
                    Icons.engineering,
                  ),
                  _buildOverviewStat(
                    '${logs.length}',
                    tr('Logged In', 'Conectados'),
                    Icons.people,
                  ),
                  _buildOverviewStat(
                    '$doneToday',
                    tr('Done', 'Terminaron'),
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
                      tr(
                        '${totalHours.toStringAsFixed(1)} hours logged today',
                        '${totalHours.toStringAsFixed(1)} horas registradas hoy',
                      ),
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

    // Foremen: wrap with a projects query to get assigned project IDs
    if (widget.user.role == 'foreman') {
      return StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('projects')
            .where('assignedForemen', arrayContains: widget.user.id)
            .snapshots(),
        builder: (context, projectSnapshot) {
          final assignedProjectIds = (projectSnapshot.data?.docs ?? [])
              .map((doc) => doc.id)
              .toSet();
          return _buildInstallerFeedBody(todayStart, assignedProjectIds);
        },
      );
    }

    return _buildInstallerFeedBody(todayStart, null);
  }

  Widget _buildInstallerFeedBody(
    DateTime todayStart,
    Set<String>? foremanProjectIds,
  ) {
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
                  tr(
                    'No installers clocked in yet',
                    'Ningún instalador ha registrado entrada',
                  ),
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
          final name = data['installer_name'] ?? tr('Unknown', 'Desconocido');
          final role = data['installer_role'] ?? '';
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );

          for (final entry in entries) {
            // Foreman filter: skip entries from projects not assigned to this foreman
            if (foremanProjectIds != null) {
              final entryProjectId = entry['projectId'] as String?;
              if (entryProjectId == null ||
                  !foremanProjectIds.contains(entryProjectId)) {
                continue;
              }
            }

            final projectName =
                entry['projectName'] as String? ??
                tr('Unknown Site', 'Obra desconocida');
            final areaName = AppStrings.areaLabel(entry);

            // Look up the level from areas collectio
            String levelName = tr('Unassigned', 'Sin nivel');
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
                  tr(
                    'Installers logged in — no area activity yet',
                    'Instaladores conectados — aún sin actividad en áreas',
                  ),
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
                    '${_count(levels.length, tr('level', 'nivel'), tr('levels', 'niveles'))} \u2022 ${_workersLabel(totalWorkers)}',
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
                              '${_count(areas.length, tr('area', 'área'), tr('areas', 'áreas'))} \u2022 ${_workersLabel(levelWorkers)}',
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
                                        '${_workersLabel(workers.length)}${activeCount > 0 ? ' \u2022 ${tr('$activeCount active', '$activeCount activos')}' : ''}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      children: [
                                        ...workers.map((w) {
                                          final wName = w['name'] as String;
                                          final wRole = _roleLabel(
                                            w['role'] as String,
                                          );
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
                                                        child: Text(
                                                          tr(
                                                            'Active',
                                                            'Activo',
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: Colors
                                                                    .green,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
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
                                                  '${clockIn != null ? _formatTime(clockIn) : '--'} \u2013 ${clockOut != null ? _formatTime(clockOut) : tr('now', 'ahora')}',
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
                                                      AppStrings.workDescription(
                                                        description,
                                                      ),
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
                      tr('No job sites yet', 'Aún no hay obras'),
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
                        tr('Completed', 'Completadas'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      subtitle: Text(
                        _count(
                          completedProjects.length,
                          tr('job site', 'obra'),
                          tr('job sites', 'obras'),
                        ),
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

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildJobSiteCard(String projectId, Map<String, dynamic> data) {
    final name = data['name'] ?? tr('Unknown', 'Desconocido');
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
            location.isNotEmpty ? location : tr('No location', 'Sin ubicación'),
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
                _statusLabel(status),
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
                          tr('No areas yet', 'Aún no hay áreas'),
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
                    label: Text(
                      tr('Assign Workers', 'Asignar Trabajadores'),
                      style: const TextStyle(fontSize: 13),
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
                    label: Text(
                      tr('Assign Foreman', 'Asignar Capataz'),
                      style: const TextStyle(fontSize: 13),
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
      final level =
          data['levelName'] as String? ?? tr('Unassigned', 'Sin nivel');
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
              _count(
                levelAreas.length,
                tr('area', 'área'),
                tr('areas', 'áreas'),
              ),
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
                                    ? tr('No one assigned', 'Nadie asignado')
                                    : tr(
                                        '${people.length} ${people.length == 1 ? 'person' : 'people'} assigned',
                                        '${people.length} ${people.length == 1 ? 'persona asignada' : 'personas asignadas'}',
                                      ),
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
                                ? tr('Done', 'Terminado')
                                : tr(
                                    '${(est - consumed).toStringAsFixed(1)} days',
                                    '${(est - consumed).toStringAsFixed(1)} días',
                                  ),
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
                tr(
                  '${crewDaysLeft.toStringAsFixed(1)} crew days left • ${totalCrewDays.toStringAsFixed(0)} est.',
                  '${crewDaysLeft.toStringAsFixed(1)} días de equipo restantes • ${totalCrewDays.toStringAsFixed(0)} est.',
                ),
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
                tr(
                  '${assignedPeople.length} people',
                  '${assignedPeople.length} personas',
                ),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                tr(
                  '~${crewDaysLeft.ceil()} days to go',
                  '~${crewDaysLeft.ceil()} días restantes',
                ),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_add,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr('Assign', 'Asignar'),
                        style: const TextStyle(
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
                    tr('Edit', 'Editar'),
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
                title: Text(
                  tr(
                    'Assign Workers to $projectName',
                    'Asignar Trabajadores a $projectName',
                  ),
                ),
                content: SizedBox(
                  width: 350,
                  height: 400,
                  child: workers.isEmpty
                      ? Center(
                          child: Text(
                            tr(
                              'No workers registered yet',
                              'Aún no hay trabajadores registrados',
                            ),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView(
                          children: workers.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name =
                                data['name'] ?? tr('Unknown', 'Desconocido');
                            final role = _roleLabel(data['role'] ?? '');
                            final isAssigned = assignedWorkers.contains(doc.id);

                            return Material(
                              // Keeps the tap highlight visible inside the dialog.
                              type: MaterialType.transparency,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isAssigned
                                      ? Colors.black87
                                      : Colors.grey[200],
                                  radius: 16,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
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
                              ),
                            );
                          }).toList(),
                        ),
                ),
                actions: [
                  Text(
                    tr(
                      '${assignedWorkers.length} assigned',
                      '${assignedWorkers.length} asignados',
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(tr('Done', 'Listo')),
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
                title: Text(
                  tr(
                    'Assign Foreman to $projectName',
                    'Asignar Capataz a $projectName',
                  ),
                ),
                content: SizedBox(
                  width: 300,
                  child: foremen.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            tr(
                              'No foremen registered yet',
                              'Aún no hay capataces registrados',
                            ),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: foremen.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name =
                                data['name'] ?? tr('Unknown', 'Desconocido');
                            final isAssigned = assignedForemen.contains(doc.id);

                            return Material(
                              // Keeps the tap highlight visible inside the dialog.
                              type: MaterialType.transparency,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isAssigned
                                      ? Colors.black87
                                      : Colors.grey[200],
                                  radius: 16,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
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
                              ),
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
                    child: Text(tr('Done', 'Listo')),
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
        title: Text(
          tr('Edit Area', 'Editar Área'),
          style: const TextStyle(color: Colors.black87),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: tr('Area Name', 'Nombre del Área'),
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
                  labelText: tr('Total Crew Days', 'Días de Equipo Totales'),
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
                  title: Text(tr('Delete Area?', '¿Eliminar Área?')),
                  content: Text(
                    tr(
                      'This will permanently remove "${data['name']}". '
                          'Past work logs are kept, but assigned people will lose '
                          'this area. This cannot be undone.',
                      'Esto eliminará permanentemente "${data['name']}". '
                          'Los registros de trabajo anteriores se conservan, pero '
                          'las personas asignadas perderán esta área. Esto no se '
                          'puede deshacer.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext),
                      child: Text(AppStrings.cancel),
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
                      child: Text(AppStrings.delete),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
            label: Text(
              AppStrings.delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.cancel),
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
            child: Text(AppStrings.save),
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
                tr('Assign to $areaName', 'Asignar a $areaName'),
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
                              ? tr(
                                  'No workers assigned to this site yet.\nAsk the Supervisor to assign workers.',
                                  'Aún no hay trabajadores asignados a esta obra.\nPídele al Supervisor que asigne trabajadores.',
                                )
                              : tr(
                                  'No installers found',
                                  'No se encontraron instaladores',
                                ),
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
                            final userName =
                                userData['name'] ??
                                tr('Unknown', 'Desconocido');
                            final userRole = userData['role'] ?? '';
                            final isAssigned = currentPeople.contains(userId);

                            return Material(
                              // Keeps the tap highlight visible inside the dialog.
                              type: MaterialType.transparency,
                              child: ListTile(
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
                                  _roleLabel(userRole),
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
                              ),
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
                  child: Text(tr('Done', 'Listo')),
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
          'name': data?['name'] ?? tr('Unknown', 'Desconocido'),
          'role': data?['role'] ?? '',
        });
      } catch (_) {
        people.add({'name': tr('Unknown', 'Desconocido'), 'role': ''});
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

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        AppStrings.watch(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.black87.withValues(alpha: 0.1),
                  child: Text(
                    _getInitials(widget.user.name),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.user.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.role(
                    widget.user.role == 'foreman' ? 'foreman' : 'supervisor',
                  ),
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                const LanguageToggle(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _logout();
                    },
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(AppStrings.signOut),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.black54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _confirmDeleteAccount();
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(AppStrings.deleteAccount),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.deleteAccountConfirmTitle),
        content: Text(AppStrings.deleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppStrings.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final result = await _authService.deleteAccount(widget.user.id);
      if (!mounted) return;

      if (result['success'] == true) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ??
                  tr(
                    'Failed to delete account',
                    'No se pudo eliminar la cuenta',
                  ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// "1 worker" / "3 workers" in the current language.
  String _count(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';

  String _workersLabel(int n) =>
      _count(n, tr('worker', 'trabajador'), tr('workers', 'trabajadores'));

  /// Display label for a stored role value.
  String _roleLabel(String role) => AppStrings.role(role);

  /// Display label for a stored project status (never saved back).
  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return tr('ACTIVE', 'ACTIVA');
      case 'completed':
        return tr('COMPLETED', 'COMPLETADA');
      default:
        return status.toUpperCase();
    }
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
