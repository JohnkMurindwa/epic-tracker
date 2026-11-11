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
///
/// While the foreman is clocked in at a site, the roster narrows to that
/// site's crew; when he is not clocked in, it shows all his sites.
///
/// With [allActiveSites] (the supervisor's My Crew), it covers every active
/// job site instead of one foreman's: collapsed, scoreboard-style groups per
/// site — "3 of 5 working · 2 not in yet" — with each site's foreman listed
/// first, no "(You)" card, and no clocked-in filtering.
class ForemanCrewRoster extends StatelessWidget {
  final UserModel foreman;

  /// Day shown (the dashboard's selected day).
  final DateTime day;

  /// Supervisor mode: all active sites, collapsed groups.
  final bool allActiveSites;

  const ForemanCrewRoster({
    super.key,
    required this.foreman,
    required this.day,
    this.allActiveSites = false,
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
      stream: allActiveSites
          ? db
                .collection('projects')
                .where('status', isEqualTo: 'active')
                .snapshots()
          : db
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
                    final logs = logSnap.data!.docs;
                    final activeSiteId = allActiveSites
                        ? null
                        : _activeSiteId(logs);
                    final crew = _buildCrew(
                      projects: projects,
                      areas: areaSnap.data?.docs ?? [],
                      users: userSnap.data!.docs,
                      logs: logs,
                      onlySiteId: activeSiteId,
                    );
                    String? activeSiteName;
                    if (activeSiteId != null) {
                      for (final p in projects) {
                        if (p.id == activeSiteId) {
                          activeSiteName =
                              (p.data() as Map<String, dynamic>)['name']
                                  as String?;
                        }
                      }
                    }
                    return _buildList(
                      context,
                      crew,
                      projects.isEmpty,
                      filteredSite: activeSiteName,
                    );
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

  /// Site the foreman is clocked into right now — his open time entry's
  /// projectId — or null when he isn't clocked in.
  String? _activeSiteId(List<QueryDocumentSnapshot> logs) {
    for (final l in logs) {
      final data = l.data() as Map<String, dynamic>;
      if (data['installer_id'] != foreman.id) continue;
      for (final e in List<Map<String, dynamic>>.from(
        data['time_entries'] ?? [],
      )) {
        if (e['clockOut'] == null) return e['projectId'] as String?;
      }
    }
    return null;
  }

  List<_Member> _buildCrew({
    required List<QueryDocumentSnapshot> projects,
    required List<QueryDocumentSnapshot> areas,
    required List<QueryDocumentSnapshot> users,
    required List<QueryDocumentSnapshot> logs,
    String? onlySiteId,
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
      // Supervisor view lists each site's foreman too, first in its group.
      if (allActiveSites) {
        for (final id in List<String>.from(data['assignedForemen'] ?? [])) {
          siteOf.putIfAbsent(id, () => p.id);
        }
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

    if (!allActiveSites) add(foreman.id, isMe: true);
    for (final id in siteOf.keys) {
      if (id == foreman.id) continue;
      // Clocked in somewhere: show only that site's crew.
      if (onlySiteId != null && siteOf[id] != onlySiteId) continue;
      add(id, isMe: false);
    }
    return crew;
  }

  // ─── UI ────────────────────────────────────────────────────

  Widget _buildList(
    BuildContext context,
    List<_Member> crew,
    bool noSites, {
    String? filteredSite,
  }) {
    final others = crew.where((m) => !m.isMe).toList();

    // Group by site; the site's foreman first (supervisor view), then by
    // status (working first), then name.
    final bySite = <String, List<_Member>>{};
    for (final m in others) {
      bySite.putIfAbsent(m.siteName, () => []).add(m);
    }
    for (final members in bySite.values) {
      members.sort((a, b) {
        if (allActiveSites) {
          final aForeman = a.role == 'foreman' ? 0 : 1;
          final bForeman = b.role == 'foreman' ? 0 : 1;
          if (aForeman != bForeman) return aForeman - bForeman;
        }
        final byStatus = a.status.index.compareTo(b.status.index);
        return byStatus != 0
            ? byStatus
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!allActiveSites) _buildMemberCard(crew.firstWhere((m) => m.isMe)),
        if (filteredSite != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.filter_alt, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tr(
                      'Showing $filteredSite — where you are clocked in',
                      'Mostrando $filteredSite — donde estás registrado',
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (noSites)
          _buildEmpty(
            allActiveSites
                ? tr('No active job sites.', 'No hay obras activas.')
                : tr(
                    'You are not assigned to any job sites yet. Ask your supervisor to assign you.',
                    'Aún no tienes obras asignadas. Pide a tu supervisor que te asigne.',
                  ),
          )
        else if (others.isEmpty)
          _buildEmpty(
            allActiveSites
                ? tr(
                    'No workers assigned to any active job site yet.',
                    'Aún no hay trabajadores asignados a ninguna obra activa.',
                  )
                : filteredSite != null
                ? tr(
                    'No one else is assigned to $filteredSite yet.',
                    'Aún no hay nadie más asignado a $filteredSite.',
                  )
                : tr(
                    'No one is assigned to your job sites yet. Assign people to areas on the Job Sites tab.',
                    'Aún no hay nadie asignado a tus obras. Asigna personas a áreas en la pestaña Obras.',
                  ),
          )
        else if (allActiveSites)
          for (final site in bySite.entries)
            _buildSiteGroup(site.key, site.value)
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

  /// Collapsed, scoreboard-style site group for the supervisor's view.
  Widget _buildSiteGroup(String site, List<_Member> members) {
    final working = members.where((m) => m.status == _Status.working).length;
    final notIn = members.where((m) => m.status == _Status.notIn).length;

    // A Material (not a colored Container) so the ExpansionTile's ink
    // splashes paint on the card instead of being hidden behind it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey[200]!),
        ),
        child: Theme(
          data: ThemeData(dividerColor: Colors.transparent),
          child: ExpansionTile(
            // Keeps a group's open/closed state across live updates.
            key: PageStorageKey('crew-$site'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: const Icon(
              Icons.location_city,
              size: 18,
              color: Colors.black54,
            ),
            title: Text(
              site,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            subtitle: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: tr(
                      '$working of ${members.length} working',
                      '$working de ${members.length} trabajando',
                    ),
                  ),
                  if (notIn > 0)
                    TextSpan(
                      text: tr(
                        ' · $notIn not in yet',
                        ' · $notIn sin registrar',
                      ),
                      style: const TextStyle(
                        color: Color(0xFFA32D2D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            children: [for (final m in members) _buildMemberCard(m)],
          ),
        ),
      ),
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
                // Foremen work the whole site, so no area line for them.
                if (!m.isMe && m.role != 'foreman')
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
