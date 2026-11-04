import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/app_strings.dart';
import '../../widgets/off_site_badge.dart';

/// The foreman's "My Crew" list: the foreman plus everyone assigned to their
/// job sites (by the supervisor) or to an area on those sites (by the
/// foreman), with each person's assigned area and where they are right now.
///
/// Built from assignments, not only clock-ins, so people show up as soon as
/// they are assigned — before they clock in.
class ForemanCrewRoster extends StatelessWidget {
  final UserModel foreman;

  /// Day shown (the dashboard's selected day).
  final DateTime day;

  const ForemanCrewRoster({
    super.key,
    required this.foreman,
    required this.day,
  });

  static const _workerRoles = [
    'installer',
    'junior_installer',
    'helper',
    'foreman',
  ];

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    final db = FirebaseFirestore.instance;
    final dayStart = DateTime(day.year, day.month, day.day);

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('projects')
          .where('assignedForemen', arrayContains: foreman.id)
          .snapshots(),
      builder: (context, projectSnap) {
        final projects = projectSnap.data?.docs ?? [];
        final projectIds = projects.map((d) => d.id).toList();

        return StreamBuilder<QuerySnapshot>(
          // whereIn allows up to 30 values; a foreman has far fewer sites.
          stream: projectIds.isEmpty
              ? const Stream.empty()
              : db
                    .collection('areas')
                    .where('projectId', whereIn: projectIds.take(30).toList())
                    .snapshots(),
          builder: (context, areaSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('users')
                  .where('role', whereIn: _workerRoles)
                  .snapshots(),
              builder: (context, userSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: db
                      .collection('daily_logs')
                      .where(
                        'log_date',
                        isEqualTo: Timestamp.fromDate(dayStart),
                      )
                      .snapshots(),
                  builder: (context, logSnap) {
                    if (!projectSnap.hasData ||
                        !userSnap.hasData ||
                        !logSnap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.black87,
                          ),
                        ),
                      );
                    }
                    final crew = _buildCrew(
                      projects: projects,
                      areas: areaSnap.data?.docs ?? [],
                      users: userSnap.data!.docs,
                      logs: logSnap.data!.docs,
                    );
                    return _buildList(context, crew, projects.isEmpty);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── Data ──────────────────────────────────────────────────

  List<_Member> _buildCrew({
    required List<QueryDocumentSnapshot> projects,
    required List<QueryDocumentSnapshot> areas,
    required List<QueryDocumentSnapshot> users,
    required List<QueryDocumentSnapshot> logs,
  }) {
    final projectNames = {
      for (final p in projects)
        p.id: ((p.data() as Map<String, dynamic>)['name'] as String?) ?? '',
    };
    final userData = {
      for (final u in users) u.id: u.data() as Map<String, dynamic>,
    };
    final logsByUser = <String, Map<String, dynamic>>{};
    for (final l in logs) {
      final data = l.data() as Map<String, dynamic>;
      final id = data['installer_id'] as String?;
      if (id != null) logsByUser[id] = data;
    }

    // Person id → site id, and person id → assigned area name.
    final siteOf = <String, String>{};
    final areaOf = <String, String>{};

    // Area assignments (made by the foreman) are the most specific.
    for (final a in areas) {
      final data = a.data() as Map<String, dynamic>;
      for (final id in List<String>.from(data['assignedPeople'] ?? [])) {
        siteOf[id] = data['projectId'] as String? ?? '';
        areaOf[id] = data['name'] as String? ?? '';
      }
    }
    // Site pool (made by the supervisor).
    for (final p in projects) {
      final data = p.data() as Map<String, dynamic>;
      for (final id in List<String>.from(data['assignedWorkers'] ?? [])) {
        siteOf.putIfAbsent(id, () => p.id);
      }
    }
    // Anyone who clocked in on these sites today, even if since reassigned.
    logsByUser.forEach((id, log) {
      for (final e in List<Map<String, dynamic>>.from(
        log['time_entries'] ?? [],
      )) {
        final projectId = e['projectId'] as String?;
        if (projectId != null && projectNames.containsKey(projectId)) {
          siteOf.putIfAbsent(id, () => projectId);
        }
      }
    });

    final crew = <_Member>[];
    void add(String id, {required bool isMe}) {
      final data = userData[id];
      if (data == null && !isMe) return; // deleted account
      crew.add(
        _Member(
          name: isMe ? foreman.name : (data!['name'] as String? ?? ''),
          role: isMe ? foreman.role : (data!['role'] as String? ?? ''),
          isMe: isMe,
          siteName: projectNames[siteOf[id]] ?? '',
          assignedArea: areaOf[id],
          log: logsByUser[id],
        ),
      );
    }

    add(foreman.id, isMe: true);
    for (final id in siteOf.keys) {
      if (id != foreman.id) add(id, isMe: false);
    }
    return crew;
  }

  // ─── UI ────────────────────────────────────────────────────

  Widget _buildList(BuildContext context, List<_Member> crew, bool noSites) {
    final me = crew.firstWhere((m) => m.isMe);
    final others = crew.where((m) => !m.isMe).toList();

    // Group by site, people sorted by status (working first) then name.
    final bySite = <String, List<_Member>>{};
    for (final m in others) {
      bySite.putIfAbsent(m.siteName, () => []).add(m);
    }
    for (final members in bySite.values) {
      members.sort((a, b) {
        final byStatus = a.status.index.compareTo(b.status.index);
        return byStatus != 0
            ? byStatus
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMemberCard(me),
        const SizedBox(height: 16),
        if (noSites)
          _buildEmpty(
            tr(
              'You are not assigned to any job sites yet. Ask your supervisor to assign you.',
              'Aún no tienes obras asignadas. Pide a tu supervisor que te asigne.',
            ),
          )
        else if (others.isEmpty)
          _buildEmpty(
            tr(
              'No one is assigned to your job sites yet. Assign people to areas on the Job Sites tab.',
              'Aún no hay nadie asignado a tus obras. Asigna personas a áreas en la pestaña Obras.',
            ),
          )
        else
          for (final site in bySite.entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_city,
                    size: 16,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      site.key,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    tr(
                      '${site.value.where((m) => m.status == _Status.working).length} of ${site.value.length} working',
                      '${site.value.where((m) => m.status == _Status.working).length} de ${site.value.length} trabajando',
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            for (final m in site.value) _buildMemberCard(m),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildEmpty(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildMemberCard(_Member m) {
    final (icon, color, statusText) = _statusDisplay(m);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: m.isMe ? Colors.black87 : Colors.grey[200]!,
          width: m.isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.isMe ? '${m.name} ${tr('(You)', '(Tú)')}' : m.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppStrings.role(m.role),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: m.status == _Status.notIn
                        ? Colors.grey[600]
                        : Colors.black87,
                  ),
                ),
                if (m.flaggedEntry != null)
                  OffSiteBadge(
                    m.flaggedEntry!,
                    margin: const EdgeInsets.only(top: 4),
                  ),
                if (!m.isMe)
                  Text(
                    m.assignedArea == null
                        ? tr('No area assigned yet', 'Aún sin área asignada')
                        : tr(
                            'Assigned: ${m.assignedArea}',
                            'Asignado: ${m.assignedArea}',
                          ),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _statusDisplay(_Member m) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    switch (m.status) {
      case _Status.working:
        final entry = m.openEntry!;
        final since = (entry['clockIn'] as Timestamp?)?.toDate();
        final where = _place(entry);
        return (
          Icons.play_arrow,
          Colors.black87,
          since == null
              ? tr('Working at $where', 'Trabajando en $where')
              : tr(
                  'Working at $where · since ${_formatTime(since)}',
                  'Trabajando en $where · desde las ${_formatTime(since)}',
                ),
        );
      case _Status.lunch:
        return (
          Icons.restaurant,
          Colors.orange,
          tr(
            'On lunch · ${_place(m.openEntry!)}',
            'En almuerzo · ${_place(m.openEntry!)}',
          ),
        );
      case _Status.clockedOut:
        return (
          Icons.logout,
          Colors.grey[600]!,
          tr(
            'Clocked out · ${m.hours.toStringAsFixed(1)} h',
            'Salida registrada · ${m.hours.toStringAsFixed(1)} h',
          ),
        );
      case _Status.dayComplete:
        return (
          Icons.check,
          Colors.grey[800]!,
          tr(
            'Day complete · ${m.hours.toStringAsFixed(1)} h',
            'Día terminado · ${m.hours.toStringAsFixed(1)} h',
          ),
        );
      case _Status.notIn:
        return (
          Icons.schedule,
          Colors.grey[400]!,
          isToday
              ? tr('Not clocked in yet', 'Aún no registra entrada')
              : tr('No time recorded', 'Sin horas registradas'),
        );
    }
  }

  /// "A12 — Sliding door · 19 del Mar", or the site for whole-site entries.
  String _place(Map<String, dynamic> entry) {
    final project = entry['projectName'] as String? ?? '';
    final area = entry['areaName'] as String?;
    return area == null ? project : '$area · $project';
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

/// Sort order: who's working first.
enum _Status { working, lunch, clockedOut, dayComplete, notIn }

class _Member {
  final String name;
  final String role;
  final bool isMe;
  final String siteName;
  final String? assignedArea;
  final Map<String, dynamic>? log;

  _Member({
    required this.name,
    required this.role,
    required this.isMe,
    required this.siteName,
    required this.assignedArea,
    required this.log,
  });

  List<Map<String, dynamic>> get _entries =>
      List<Map<String, dynamic>>.from(log?['time_entries'] ?? []);

  Map<String, dynamic>? get openEntry {
    final entries = _entries;
    return entries.isNotEmpty && entries.last['clockOut'] == null
        ? entries.last
        : null;
  }

  /// The most recent entry that was clocked in or out off site, if any.
  Map<String, dynamic>? get flaggedEntry {
    for (final e in _entries.reversed) {
      if (OffSiteBadge.isOffSite(e)) return e;
    }
    return null;
  }

  double get hours => _entries.fold(
    0,
    (total, e) => total + ((e['hoursWorked'] ?? 0) as num).toDouble(),
  );

  _Status get status {
    if (log == null || _entries.isEmpty) return _Status.notIn;
    if (log!['is_day_complete'] == true) return _Status.dayComplete;
    if (openEntry != null) {
      return log!['is_on_lunch'] == true ? _Status.lunch : _Status.working;
    }
    return _Status.clockedOut;
  }
}
