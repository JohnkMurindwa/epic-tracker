import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../services/app_strings.dart';
import '../../services/auth_service.dart';
import '../../widgets/language_toggle.dart';
import '../auth/login_screen.dart';
import 'excel_import_widget.dart';
import 'timesheets_screen.dart';

class AdminDashboard extends StatefulWidget {
  final UserModel user;
  const AdminDashboard({super.key, required this.user});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Crew day rate — stored in Firestore settings, default $800
  double _crewDayRate = 800.0;

  // Navigation state: null = overview, string = drilled into site/area
  String? _selectedSiteId;
  String? _selectedSiteName;
  String? _selectedLevel;
  String? _selectedAreaId;
  String? _selectedAreaName;
  bool _isGridView = true; // Toggle between grid cards and list table

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _db.collection('settings').doc('global').get();
      if (doc.exists) {
        setState(() {
          _crewDayRate = (doc.data()?['crewDayRate'] ?? 800).toDouble();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _selectedAreaId != null
                  ? _buildAreaDetail()
                  : _selectedLevel != null
                  ? _buildLevelDetail()
                  : _selectedSiteId != null
                  ? _buildSiteDetail()
                  : _buildOverview(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const Text(
            'EPIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFFB22222),
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(width: 8),
          Text(
            AppStrings.role('admin'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
          const Spacer(),
          Text(
            DateFormat(
              'EEEE, MMM d, yyyy',
              AppStrings.dateLocale,
            ).format(DateTime.now()),
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(width: 16),
          Text(
            widget.user.name,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.grey[200],
            child: Text(
              widget.user.name.isNotEmpty
                  ? widget.user.name[0].toUpperCase()
                  : 'A',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 8),
          LanguageToggle(color: Colors.grey[700]),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TimesheetsScreen()),
              );
            },
            icon: Icon(Icons.assignment, size: 20, color: Colors.grey[500]),
            tooltip: tr('Timesheets', 'Hojas de horas'),
          ),
          IconButton(
            onPressed: _logout,
            icon: Icon(Icons.logout, size: 20, color: Colors.grey[500]),
            tooltip: AppStrings.signOut,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LEVEL 1: OVERVIEW — KPIs + Job Sites Table + Activity
  // ═══════════════════════════════════════════════════════════

  Widget _buildOverview() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('projects').snapshots(),
      builder: (context, projectSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: _db.collection('areas').snapshots(),
          builder: (context, areaSnap) {
            final projects = projectSnap.data?.docs ?? [];
            final areas = areaSnap.data?.docs ?? [];

            // Calculate totals
            double totalConsumed = 0;
            double totalEstimated = 0;
            for (final area in areas) {
              final data = area.data() as Map<String, dynamic>;
              totalConsumed += (data['consumedCrewDays'] ?? 0).toDouble();
              totalEstimated += (data['totalCrewDays'] ?? 0).toDouble();
            }

            double totalSpent = totalConsumed * _crewDayRate;
            double totalBudget = totalEstimated * _crewDayRate;
            double totalRemaining = totalBudget - totalSpent;
            int activeCount = projects.where((p) {
              final d = p.data() as Map<String, dynamic>;
              return d['status'] == 'active';
            }).length;

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // KPI Row
                Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        tr('Total budget', 'Presupuesto total'),
                        '\$${_fmt(totalBudget)}',
                        tr(
                          'across $activeCount active jobs',
                          'en $activeCount obras activas',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        tr('Total spent', 'Total gastado'),
                        '\$${_fmt(totalSpent)}',
                        tr(
                          '${totalConsumed.toStringAsFixed(1)} crew days consumed',
                          '${totalConsumed.toStringAsFixed(1)} días de equipo usados',
                        ),
                        isRed: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        tr('Remaining', 'Restante'),
                        '\$${_fmt(totalRemaining)}',
                        '${(totalEstimated - totalConsumed).toStringAsFixed(1)} ${AppStrings.crewDaysLeft}',
                        isGreen: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        tr('Crew day rate', 'Tarifa por día de equipo'),
                        '\$${_crewDayRate.toStringAsFixed(0)}',
                        tr('per crew day', 'por día de equipo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Job Sites Table
                Row(
                  children: [
                    Text(
                      tr('Job sites', 'Obras'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _showAddJobSiteDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Add Job Site', 'Agregar Obra')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildJobSitesTable(projects, areas),

                const SizedBox(height: 24),

                // Today's Activity
                Text(
                  tr('Today\'s activity', 'Actividad de hoy'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _buildTodayActivity(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildJobSitesTable(
    List<QueryDocumentSnapshot> projects,
    List<QueryDocumentSnapshot> areas,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1.2),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
            5: FlexColumnWidth(1.5),
            6: FlexColumnWidth(1.5),
            7: FlexColumnWidth(0.8),
          },
          children: [
            // Header
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[50]),
              children: [
                _th(tr('Site', 'Obra')),
                _th(tr('Location', 'Ubicación')),
                _th(tr('Budget', 'Presupuesto')),
                _th(tr('Spent', 'Gastado')),
                _th(tr('Remaining', 'Restante')),
                _th(tr('Crew days', 'Días de equipo')),
                _th(tr('Progress', 'Progreso')),
                _th(tr('Status', 'Estado')),
              ],
            ),
            // Rows
            ...projects.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] ?? 'Unknown';
              final location = data['location'] ?? '';
              final status = data['status'] ?? 'active';

              // Sum areas for this project
              double consumed = 0;
              double estimated = 0;
              for (final area in areas) {
                final aData = area.data() as Map<String, dynamic>;
                if (aData['projectId'] == doc.id) {
                  consumed += (aData['consumedCrewDays'] ?? 0).toDouble();
                  estimated += (aData['totalCrewDays'] ?? 0).toDouble();
                }
              }

              double spent = consumed * _crewDayRate;
              double budget = estimated * _crewDayRate;
              double remaining = budget - spent;
              double progress = estimated > 0
                  ? (consumed / estimated).clamp(0, 1)
                  : 0;

              return TableRow(
                children: [
                  _td(
                    name,
                    bold: true,
                    onTap: () {
                      setState(() {
                        _selectedSiteId = doc.id;
                        _selectedSiteName = name;
                      });
                    },
                  ),
                  _td(location, muted: true),
                  _td('\$${_fmt(budget)}'),
                  _td('\$${_fmt(spent)}', color: const Color(0xFFA32D2D)),
                  _td('\$${_fmt(remaining)}', color: const Color(0xFF0F6E56)),
                  _td(
                    '${consumed.toStringAsFixed(1)} / ${estimated.toStringAsFixed(0)}',
                  ),
                  _tdProgress(progress),
                  _tdBadge(status),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayActivity() {
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

        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                tr('No activity yet today', 'Aún no hay actividad hoy'),
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          );
        }

        // Group by project → area → workers
        final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};
        for (final doc in logs) {
          final data = doc.data() as Map<String, dynamic>;
          final name = data['installer_name'] ?? tr('Unknown', 'Desconocido');
          final role = data['installer_role'] ?? '';
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );

          for (final entry in entries) {
            final projectName =
                entry['projectName'] as String? ?? tr('Unknown', 'Desconocido');
            final areaName =
                entry['areaName'] as String? ?? tr('Unknown', 'Desconocido');

            grouped
                .putIfAbsent(projectName, () => {})
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

        return Column(
          children: grouped.entries.map((siteGroup) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Site header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      siteGroup.key,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Areas + workers
                  ...siteGroup.value.entries.map((areaGroup) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            areaGroup.key,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...areaGroup.value.map((w) {
                            final clockIn = (w['clockIn'] as Timestamp?)
                                ?.toDate();
                            final clockOut = (w['clockOut'] as Timestamp?)
                                ?.toDate();
                            final hours = (w['hoursWorked'] ?? 0).toDouble();
                            final desc = w['description'] as String? ?? '';
                            final isActive = clockOut == null;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      '${w['name']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      AppStrings.role(
                                        '${w['role']}',
                                      ).replaceAll('_', ' '),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: Text(
                                      '${clockIn != null ? _fmtTime(clockIn) : '--'} – ${clockOut != null ? _fmtTime(clockOut) : tr('now', 'ahora')}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      isActive
                                          ? tr('Active', 'Activo')
                                          : '${hours.toStringAsFixed(1)}h',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isActive
                                            ? Colors.green
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      AppStrings.workDescription(desc),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LEVEL 2: SITE DETAIL — Areas + Cost + Activity
  // ═══════════════════════════════════════════════════════════

  Widget _buildSiteDetail() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('areas')
          .where('projectId', isEqualTo: _selectedSiteId)
          .snapshots(),
      builder: (context, areaSnap) {
        final areas = areaSnap.data?.docs ?? [];

        double totalConsumed = 0;
        double totalEstimated = 0;
        for (final area in areas) {
          final d = area.data() as Map<String, dynamic>;
          totalConsumed += (d['consumedCrewDays'] ?? 0).toDouble();
          totalEstimated += (d['totalCrewDays'] ?? 0).toDouble();
        }

        double spent = totalConsumed * _crewDayRate;
        double budget = totalEstimated * _crewDayRate;
        double remaining = budget - spent;
        // int inProgress = areas.where((a) {
        //   final d = a.data() as Map<String, dynamic>;
        //   final consumed = (d['consumedCrewDays'] ?? 0).toDouble();
        //   final total = (d['totalCrewDays'] ?? 0).toDouble();
        //   return consumed < total;
        // }).length;

        // Group areas by level
        final Map<String, List<QueryDocumentSnapshot>> levelGroups = {};
        for (final area in areas) {
          final d = area.data() as Map<String, dynamic>;
          final level = d['levelName'] as String? ?? 'Unassigned';
          levelGroups.putIfAbsent(level, () => []).add(area);
        }

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Back + breadcrumb
            GestureDetector(
              onTap: () => setState(() {
                _selectedSiteId = null;
                _selectedSiteName = null;
              }),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text(
                    tr('All sites', 'Todas las obras'),
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
                  Text(
                    _selectedSiteName ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Site name
            Text(
              _selectedSiteName ?? '',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // KPIs
            Row(
              children: [
                Expanded(
                  child: _kpiCard(
                    tr('Site budget', 'Presupuesto de la obra'),
                    '\$${_fmt(budget)}',
                    '',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Spent', 'Gastado'),
                    '\$${_fmt(spent)}',
                    tr(
                      '${totalConsumed.toStringAsFixed(1)} crew days',
                      '${totalConsumed.toStringAsFixed(1)} días de equipo',
                    ),
                    isRed: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Remaining', 'Restante'),
                    '\$${_fmt(remaining)}',
                    tr(
                      '${(totalEstimated - totalConsumed).toStringAsFixed(1)} crew days',
                      '${(totalEstimated - totalConsumed).toStringAsFixed(1)} días de equipo',
                    ),
                    isGreen: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Levels', 'Niveles'),
                    '${levelGroups.length}',
                    tr(
                      '${areas.length} areas total',
                      '${areas.length} áreas en total',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Import button
            Row(
              children: [
                Text(
                  tr('Levels', 'Niveles'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ExcelImportDialog(
                        projectId: _selectedSiteId!,
                        projectName: _selectedSiteName ?? '',
                      ),
                    );
                  },
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(
                    tr('Import Spreadsheet', 'Importar Hoja de Cálculo'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Levels list
            ...levelGroups.entries.map((levelEntry) {
              final levelName = levelEntry.key;
              final levelAreas = levelEntry.value;

              double levelConsumed = 0;
              double levelEstimated = 0;
              int levelPeople = 0;
              for (final a in levelAreas) {
                final d = a.data() as Map<String, dynamic>;
                levelConsumed += (d['consumedCrewDays'] ?? 0).toDouble();
                levelEstimated += (d['totalCrewDays'] ?? 0).toDouble();
                levelPeople += (List<String>.from(
                  d['assignedPeople'] ?? [],
                )).length;
              }
              final levelProgress = levelEstimated > 0
                  ? (levelConsumed / levelEstimated).clamp(0.0, 1.0)
                  : 0.0;
              final levelSpent = levelConsumed * _crewDayRate;

              return GestureDetector(
                onTap: () => setState(() {
                  _selectedLevel = levelName;
                }),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.layers,
                          color: Colors.grey[600],
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              levelName == 'Unassigned'
                                  ? tr('Unassigned', 'Sin asignar')
                                  : levelName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr(
                                '${levelAreas.length} areas • $levelPeople people • \$${_fmt(levelSpent)} spent',
                                '${levelAreas.length} áreas • $levelPeople personas • \$${_fmt(levelSpent)} gastado',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Progress
                      SizedBox(
                        width: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${(levelProgress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: levelProgress,
                                minHeight: 4,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation(
                                  levelProgress >= 1.0
                                      ? Colors.green
                                      : Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            }),

            if (levelGroups.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.layers, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text(
                        tr('No areas yet', 'Aún no hay áreas'),
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          'Import a spreadsheet to get started',
                          'Importa una hoja de cálculo para empezar',
                        ),
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LEVEL 2.5: LEVEL DETAIL — Areas + KPIs + Activity
  // ═══════════════════════════════════════════════════════════

  Widget _buildLevelDetail() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('areas')
          .where('projectId', isEqualTo: _selectedSiteId)
          .where('levelName', isEqualTo: _selectedLevel)
          .snapshots(),
      builder: (context, areaSnap) {
        final areas = areaSnap.data?.docs ?? [];

        double totalConsumed = 0;
        double totalEstimated = 0;
        for (final area in areas) {
          final d = area.data() as Map<String, dynamic>;
          totalConsumed += (d['consumedCrewDays'] ?? 0).toDouble();
          totalEstimated += (d['totalCrewDays'] ?? 0).toDouble();
        }

        double spent = totalConsumed * _crewDayRate;
        double budget = totalEstimated * _crewDayRate;
        double remaining = budget - spent;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Breadcrumb
            GestureDetector(
              onTap: () => setState(() {
                _selectedLevel = null;
              }),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedSiteId = null;
                      _selectedSiteName = null;
                      _selectedLevel = null;
                    }),
                    child: Text(
                      tr('All sites', 'Todas las obras'),
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedLevel = null;
                    }),
                    child: Text(
                      _selectedSiteName ?? '',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
                  Text(
                    _selectedLevel ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Level name
            Row(
              children: [
                Icon(Icons.layers, size: 24, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  _selectedLevel ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Text(
              _selectedSiteName ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),

            // KPIs
            Row(
              children: [
                Expanded(
                  child: _kpiCard(
                    tr('Budget', 'Presupuesto'),
                    '\$${_fmt(budget)}',
                    tr(
                      '${totalEstimated.toStringAsFixed(0)} crew days',
                      '${totalEstimated.toStringAsFixed(0)} días de equipo',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Spent', 'Gastado'),
                    '\$${_fmt(spent)}',
                    tr(
                      '${totalConsumed.toStringAsFixed(1)} crew days',
                      '${totalConsumed.toStringAsFixed(1)} días de equipo',
                    ),
                    isRed: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Remaining', 'Restante'),
                    '\$${_fmt(remaining)}',
                    tr(
                      '${(totalEstimated - totalConsumed).toStringAsFixed(1)} crew days',
                      '${(totalEstimated - totalConsumed).toStringAsFixed(1)} días de equipo',
                    ),
                    isGreen: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(tr('Areas', 'Áreas'), '${areas.length}', ''),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Areas header with view toggle
            Row(
              children: [
                Text(
                  tr('Areas', 'Áreas'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _isGridView = true),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isGridView
                                ? Colors.black87
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.grid_view,
                            size: 18,
                            color: _isGridView
                                ? Colors.white
                                : Colors.grey[500],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isGridView = false),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: !_isGridView
                                ? Colors.black87
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.view_list,
                            size: 18,
                            color: !_isGridView
                                ? Colors.white
                                : Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Grid view
            if (_isGridView)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: areas.map((areaDoc) {
                  final aData = areaDoc.data() as Map<String, dynamic>;
                  final areaName = aData['name'] ?? '';
                  final est = (aData['totalCrewDays'] ?? 0).toDouble();
                  final consumed = (aData['consumedCrewDays'] ?? 0).toDouble();
                  final rem = est - consumed;
                  final progress = est > 0
                      ? (consumed / est).clamp(0.0, 1.0)
                      : 0.0;
                  final costSpent = consumed * _crewDayRate;
                  final costRemaining = rem * _crewDayRate;
                  final people = List<String>.from(
                    aData['assignedPeople'] ?? [],
                  );
                  final isDone = consumed >= est;

                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedAreaId = areaDoc.id;
                      _selectedAreaName = areaName;
                    }),
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[200]!),
                        borderRadius: BorderRadius.circular(10),
                        color: isDone ? Colors.grey[50] : Colors.white,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
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
                                tr(
                                  'Est. ${est.toStringAsFixed(0)}',
                                  'Est. ${est.toStringAsFixed(0)}',
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation(
                                isDone ? Colors.green : Colors.blue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _costRow(
                            tr('Consumed', 'Usado'),
                            tr(
                              '${consumed.toStringAsFixed(1)} crew days',
                              '${consumed.toStringAsFixed(1)} días de equipo',
                            ),
                          ),
                          _costRow(
                            tr('Labor cost', 'Costo de mano de obra'),
                            '\$${_fmt(costSpent)}',
                            color: const Color(0xFFA32D2D),
                          ),
                          _costRow(
                            tr('Remaining', 'Restante'),
                            '\$${_fmt(costRemaining)}',
                            color: const Color(0xFF0F6E56),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(
                              '${people.length} people assigned',
                              '${people.length} personas asignadas',
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              )
            // List view
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1.2),
                      2: FlexColumnWidth(1.2),
                      3: FlexColumnWidth(1.2),
                      4: FlexColumnWidth(1.5),
                      5: FlexColumnWidth(0.8),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey[50]),
                        children: [
                          _th(tr('Area', 'Área')),
                          _th(tr('Crew Days', 'Días de equipo')),
                          _th(tr('Spent', 'Gastado')),
                          _th(tr('Remaining', 'Restante')),
                          _th(tr('Progress', 'Progreso')),
                          _th(tr('People', 'Personas')),
                        ],
                      ),
                      ...areas.map((areaDoc) {
                        final aData = areaDoc.data() as Map<String, dynamic>;
                        final areaName = aData['name'] ?? '';
                        final est = (aData['totalCrewDays'] ?? 0).toDouble();
                        final consumed = (aData['consumedCrewDays'] ?? 0)
                            .toDouble();
                        final rem = est - consumed;
                        final progress = est > 0
                            ? (consumed / est).clamp(0.0, 1.0)
                            : 0.0;
                        final costSpent = consumed * _crewDayRate;
                        final costRemaining = rem * _crewDayRate;
                        final people = List<String>.from(
                          aData['assignedPeople'] ?? [],
                        );

                        return TableRow(
                          children: [
                            _td(
                              areaName,
                              bold: true,
                              onTap: () {
                                setState(() {
                                  _selectedAreaId = areaDoc.id;
                                  _selectedAreaName = areaName;
                                });
                              },
                            ),
                            _td(
                              '${consumed.toStringAsFixed(1)} / ${est.toStringAsFixed(0)}',
                            ),
                            _td(
                              '\$${_fmt(costSpent)}',
                              color: const Color(0xFFA32D2D),
                            ),
                            _td(
                              '\$${_fmt(costRemaining)}',
                              color: const Color(0xFF0F6E56),
                            ),
                            _tdProgress(progress),
                            _td('${people.length}'),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Today's activity for this level
            Text(
              tr('Today\'s activity', 'Actividad de hoy'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _buildSiteTodayActivity(),
          ],
        );
      },
    );
  }

  Widget _buildSiteTodayActivity() {
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

        // Filter entries for this site
        final rows = <Map<String, dynamic>>[];
        for (final doc in logs) {
          final data = doc.data() as Map<String, dynamic>;
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );
          for (final entry in entries) {
            if (entry['projectId'] == _selectedSiteId ||
                entry['projectName'] == _selectedSiteName) {
              rows.add({
                'name': data['installer_name'],
                'role': data['installer_role'],
                ...entry,
              });
            }
          }
        }

        if (rows.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                tr('No activity today', 'No hay actividad hoy'),
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(0.8),
                5: FlexColumnWidth(3),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[50]),
                  children: [
                    _th(tr('Name', 'Nombre')),
                    _th(tr('Role', 'Rol')),
                    _th(tr('Area', 'Área')),
                    _th(tr('Time', 'Hora')),
                    _th(tr('Hours', 'Horas')),
                    _th(tr('Work done', 'Trabajo hecho')),
                  ],
                ),
                ...rows.map((r) {
                  final clockIn = (r['clockIn'] as Timestamp?)?.toDate();
                  final clockOut = (r['clockOut'] as Timestamp?)?.toDate();
                  final hours = (r['hoursWorked'] ?? 0).toDouble();
                  final isActive = clockOut == null;

                  return TableRow(
                    children: [
                      _td('${r['name']}', bold: true),
                      _td(
                        AppStrings.role('${r['role']}').replaceAll('_', ' '),
                        muted: true,
                      ),
                      _td('${r['areaName'] ?? ''}'),
                      _td(
                        '${clockIn != null ? _fmtTime(clockIn) : '--'} – ${clockOut != null ? _fmtTime(clockOut) : tr('now', 'ahora')}',
                        muted: true,
                      ),
                      _td(
                        isActive
                            ? tr('Active', 'Activo')
                            : '${hours.toStringAsFixed(1)}h',
                        bold: true,
                        color: isActive ? Colors.green : null,
                      ),
                      _td(
                        AppStrings.workDescription(r['description'] as String?),
                        muted: true,
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // LEVEL 3: AREA DETAIL — History + Cost + Crew
  // ═══════════════════════════════════════════════════════════

  Widget _buildAreaDetail() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('areas').doc(_selectedAreaId).snapshots(),
      builder: (context, areaSnap) {
        if (!areaSnap.hasData || !areaSnap.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }

        final aData = areaSnap.data!.data() as Map<String, dynamic>;
        final est = (aData['totalCrewDays'] ?? 0).toDouble();
        final consumed = (aData['consumedCrewDays'] ?? 0).toDouble();
        final remaining = est - consumed;
        final progress = est > 0 ? (consumed / est).clamp(0.0, 1.0) : 0.0;
        final costSpent = consumed * _crewDayRate;
        final costRemaining = remaining * _crewDayRate;
        final people = List<String>.from(aData['assignedPeople'] ?? []);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Breadcrumb
            GestureDetector(
              onTap: () => setState(() {
                _selectedAreaId = null;
                _selectedAreaName = null;
              }),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedSiteId = null;
                      _selectedSiteName = null;
                      _selectedLevel = null;
                      _selectedAreaId = null;
                      _selectedAreaName = null;
                    }),
                    child: Text(
                      tr('All sites', 'Todas las obras'),
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedLevel = null;
                      _selectedAreaId = null;
                      _selectedAreaName = null;
                    }),
                    child: Text(
                      _selectedSiteName ?? '',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ),
                  if (_selectedLevel != null) ...[
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedAreaId = null;
                        _selectedAreaName = null;
                      }),
                      child: Text(
                        _selectedLevel!,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ),
                  ],
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
                  Text(
                    _selectedAreaName ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Area name + status
            Row(
              children: [
                Text(
                  _selectedAreaName ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: progress >= 1.0
                        ? const Color(0xFFE1F5EE)
                        : Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    progress >= 1.0
                        ? tr('Complete', 'Completo')
                        : tr('In progress', 'En progreso'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: progress >= 1.0
                          ? const Color(0xFF0F6E56)
                          : Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _selectedSiteName ?? '',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),

            // KPIs
            Row(
              children: [
                Expanded(
                  child: _kpiCard(
                    tr('Estimated', 'Estimado'),
                    '${est.toStringAsFixed(0)}',
                    tr('crew days', 'días de equipo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Consumed', 'Usado'),
                    '${consumed.toStringAsFixed(1)}',
                    tr(
                      '\$${_fmt(costSpent)} labor',
                      '\$${_fmt(costSpent)} mano de obra',
                    ),
                    isRed: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('Remaining', 'Restante'),
                    '${remaining.toStringAsFixed(1)}',
                    tr(
                      '\$${_fmt(costRemaining)} left',
                      '\$${_fmt(costRemaining)} restante',
                    ),
                    isGreen: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    tr('People', 'Personas'),
                    '${people.length}',
                    tr('currently assigned', 'asignadas ahora'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                  progress >= 1.0 ? Colors.green : Colors.blue,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '0',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                  Text(
                    tr(
                      '${(progress * 100).toStringAsFixed(0)}% complete',
                      '${(progress * 100).toStringAsFixed(0)}% completo',
                    ),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  Text(
                    '${est.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Current crew
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Crew list
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          'Current crew (${people.length})',
                          'Equipo actual (${people.length})',
                        ),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...people.map((uid) {
                        return FutureBuilder<DocumentSnapshot>(
                          future: _db.collection('users').doc(uid).get(),
                          builder: (context, snap) {
                            final uData =
                                snap.data?.data() as Map<String, dynamic>?;
                            final name = uData?['name'] ?? AppStrings.loading;
                            final role = AppStrings.role(
                              uData?['role'] ?? '',
                            ).replaceAll('_', ' ');
                            return Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey[100]!),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.grey[200],
                                    child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        role,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Work history
            Text(
              tr('Work history', 'Historial de trabajo'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _buildAreaWorkHistory(),
          ],
        );
      },
    );
  }

  Widget _buildAreaWorkHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('daily_logs')
          .orderBy('log_date', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        final logs = snapshot.data?.docs ?? [];

        // Filter to entries that reference this area
        final Map<String, List<Map<String, dynamic>>> dayGroups = {};
        for (final doc in logs) {
          final data = doc.data() as Map<String, dynamic>;
          final entries = List<Map<String, dynamic>>.from(
            data['time_entries'] ?? [],
          );

          for (final entry in entries) {
            if (entry['areaId'] == _selectedAreaId) {
              final logDate = (data['log_date'] as Timestamp?)?.toDate();
              final dateKey = logDate != null
                  ? DateFormat(
                      'EEE, MMM d',
                      AppStrings.dateLocale,
                    ).format(logDate)
                  : tr('Unknown', 'Desconocido');

              dayGroups.putIfAbsent(dateKey, () => []).add({
                'name': data['installer_name'],
                'role': data['installer_role'],
                'clockIn': entry['clockIn'],
                'clockOut': entry['clockOut'],
                'hoursWorked': entry['hoursWorked'],
                'description': entry['description'],
                'crewDaysLeftAfter': entry['crewDaysLeftAfter'],
                'lunchStart': data['lunch_start'],
                'lunchEnd': data['lunch_end'],
              });
            }
          }
        }

        if (dayGroups.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                tr('No work logged yet', 'Aún no hay trabajo registrado'),
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          );
        }

        return Column(
          children: dayGroups.entries.map((dayGroup) {
            final dateLabel = dayGroup.key;
            final workers = dayGroup.value;
            double totalHours = 0;
            // double? crewDaysBefore;
            double? crewDaysAfter;

            for (final w in workers) {
              totalHours += (w['hoursWorked'] ?? 0).toDouble();
              if (w['crewDaysLeftAfter'] != null) {
                crewDaysAfter = (w['crewDaysLeftAfter'] as num).toDouble();
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  title: Text(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        tr(
                          '${workers.length} workers · ${totalHours.toStringAsFixed(1)}h',
                          '${workers.length} trabajadores · ${totalHours.toStringAsFixed(1)}h',
                        ),
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      if (crewDaysAfter != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tr(
                              '${crewDaysAfter.toStringAsFixed(1)} crew days after',
                              '${crewDaysAfter.toStringAsFixed(1)} días de equipo después',
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  children: workers.map((w) {
                    final clockIn = (w['clockIn'] as Timestamp?)?.toDate();
                    final clockOut = (w['clockOut'] as Timestamp?)?.toDate();
                    final hours = (w['hoursWorked'] ?? 0).toDouble();
                    final desc = w['description'] as String? ?? '';
                    final lunchStart = (w['lunchStart'] as Timestamp?)
                        ?.toDate();
                    final lunchEnd = (w['lunchEnd'] as Timestamp?)?.toDate();

                    String lunchText = '';
                    if (lunchStart != null && lunchEnd != null) {
                      lunchText =
                          ', ${tr('lunch', 'almuerzo')} ${_fmtTime(lunchStart)}–${_fmtTime(lunchEnd)}';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey[100]!),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: Colors.grey[200],
                            child: Text(
                              '${w['name']}'.isNotEmpty
                                  ? '${w['name']}'[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${w['name']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${clockIn != null ? _fmtTime(clockIn) : '--'} – ${clockOut != null ? _fmtTime(clockOut) : tr('now', 'ahora')} (${hours.toStringAsFixed(1)}h$lunchText)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                if (desc.isNotEmpty)
                                  Text(
                                    AppStrings.workDescription(desc),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${hours.toStringAsFixed(1)}h',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════

  Widget _kpiCard(
    String label,
    String value,
    String sub, {
    bool isRed = false,
    bool isGreen = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isRed
                  ? const Color(0xFFA32D2D)
                  : isGreen
                  ? const Color(0xFF0F6E56)
                  : Colors.black87,
            ),
          ),
          if (sub.isNotEmpty)
            Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _costRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: Colors.grey[500],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _td(
    String text, {
    bool bold = false,
    bool muted = false,
    Color? color,
    VoidCallback? onTap,
  }) {
    final widget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color ?? (muted ? Colors.grey[500] : Colors.black87),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: widget),
      );
    }
    return widget;
  }

  Widget _tdProgress(double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                  value >= 1.0 ? Colors.green : Colors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _tdBadge(String status) {
    final isActive = status == 'active';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE1F5EE) : Colors.grey[100],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isActive ? tr('Active', 'Activo') : tr('Done', 'Terminado'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? const Color(0xFF0F6E56) : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  String _fmt(double val) {
    if (val >= 1000) {
      return NumberFormat('#,##0', 'en_US').format(val.round());
    }
    return val.toStringAsFixed(0);
  }

  String _fmtTime(DateTime time) {
    final hour = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  void _showAddJobSiteDialog() {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Add Job Site', 'Agregar Obra')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: tr('Job Site Name', 'Nombre de la obra'),
                  hintText: tr('e.g. Hilton Lobby', 'ej. Hilton Lobby'),
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
                  labelText: tr('Location', 'Ubicación'),
                  hintText: tr('e.g. Las Vegas, NV', 'ej. Las Vegas, NV'),
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
            child: Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isEmpty) return;
              final name = nameCtrl.text.trim();
              final location = locationCtrl.text.trim();

              // Close dialog immediately
              Navigator.pop(dialogContext);

              // Write to Firestore in background
              _db.collection('projects').add({
                'name': name,
                'location': location,
                'status': 'active',
                'created_at': FieldValue.serverTimestamp(),
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('Create', 'Crear')),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await _authService.signOut();
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }
}
