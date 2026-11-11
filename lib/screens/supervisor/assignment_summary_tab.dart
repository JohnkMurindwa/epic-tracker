import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/app_strings.dart';

/// The supervisor's "Dash" tab: the daily dispatch sheet he used to write on
/// paper. One card per active job site — which foreman runs it and which
/// crew he gave them, with each worker's area. Assignments only, no live
/// clock-in status (that's the My Crew tab). Sites with nobody assigned
/// are left off the sheet.
class AssignmentSummaryTab extends StatelessWidget {
  const AssignmentSummaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    final db = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('projects')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, projectSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: db.collection('users').snapshots(),
          builder: (context, userSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('areas')
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, areaSnap) {
                if (!projectSnap.hasData || !userSnap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black87),
                  );
                }
                return _buildSheet(
                  projects: projectSnap.data!.docs,
                  users: userSnap.data!.docs,
                  areas: areaSnap.data?.docs ?? [],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSheet({
    required List<QueryDocumentSnapshot> projects,
    required List<QueryDocumentSnapshot> users,
    required List<QueryDocumentSnapshot> areas,
  }) {
    final names = <String, String>{};
    final roles = <String, String>{};
    for (final u in users) {
      final data = u.data() as Map<String, dynamic>;
      names[u.id] = data['name'] as String? ?? '';
      roles[u.id] = data['role'] as String? ?? '';
    }

    // Worker id → assigned area name, per site.
    final areaOf = <String, Map<String, String>>{}; // projectId → user → area
    for (final a in areas) {
      final data = a.data() as Map<String, dynamic>;
      final projectId = data['projectId'] as String? ?? '';
      for (final id in List<String>.from(data['assignedPeople'] ?? [])) {
        areaOf.putIfAbsent(projectId, () => {})[id] =
            data['name'] as String? ?? '';
      }
    }

    // Only staffed sites (a foreman or workers assigned), sorted by name.
    final sorted = projects.where((p) {
      final data = p.data() as Map<String, dynamic>;
      return List.from(data['assignedWorkers'] ?? []).isNotEmpty ||
          List.from(data['assignedForemen'] ?? []).isNotEmpty;
    }).toList()
      ..sort((a, b) {
        final an = ((a.data() as Map<String, dynamic>)['name'] ?? '') as String;
        final bn = ((b.data() as Map<String, dynamic>)['name'] ?? '') as String;
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });
    final allAssigned = <String>{};
    var sitesWithoutForeman = 0;
    for (final p in sorted) {
      final data = p.data() as Map<String, dynamic>;
      allAssigned.addAll(List<String>.from(data['assignedWorkers'] ?? []));
      if (List.from(data['assignedForemen'] ?? []).isEmpty) {
        sitesWithoutForeman++;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Sheet header: today's date, like the top of the paper version.
        Text(
          DateFormat(
            'EEEE, MMMM d',
            AppStrings.dateLocale,
          ).format(DateTime.now()),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: tr(
                  '${sorted.length} active sites · ${allAssigned.length} workers assigned',
                  '${sorted.length} obras activas · ${allAssigned.length} trabajadores asignados',
                ),
              ),
              if (sitesWithoutForeman > 0)
                TextSpan(
                  text: tr(
                    ' · $sitesWithoutForeman without a foreman',
                    ' · $sitesWithoutForeman sin capataz',
                  ),
                  style: const TextStyle(
                    color: Color(0xFFA32D2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        if (sorted.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tr(
                'No assignments yet. Assign foremen and workers on the Job Sites tab.',
                'Aún no hay asignaciones. Asigna capataces y trabajadores en la pestaña Obras.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          )
        else
          for (final p in sorted)
            _buildSiteCard(
              p.data() as Map<String, dynamic>,
              names: names,
              roles: roles,
              areaOfWorker: areaOf[p.id] ?? const {},
            ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSiteCard(
    Map<String, dynamic> data, {
    required Map<String, String> names,
    required Map<String, String> roles,
    required Map<String, String> areaOfWorker,
  }) {
    final name = data['name'] as String? ?? '';
    final location = data['location'] as String? ?? '';
    final foremanIds = List<String>.from(data['assignedForemen'] ?? []);
    final foremanNames = foremanIds
        .map((id) => names[id] ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');

    // Crew sorted: workers with an area first (by area), then the rest.
    final workerIds = List<String>.from(data['assignedWorkers'] ?? [])
      ..sort((a, b) {
        final aHas = areaOfWorker.containsKey(a) ? 0 : 1;
        final bHas = areaOfWorker.containsKey(b) ? 0 : 1;
        if (aHas != bHas) return aHas - bHas;
        return (names[a] ?? '').toLowerCase().compareTo(
          (names[b] ?? '').toLowerCase(),
        );
      });

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Site name + where
          Text(
            name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (location.isNotEmpty)
            Text(
              location,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          const SizedBox(height: 8),

          // Foreman line
          Row(
            children: [
              Icon(
                Icons.engineering,
                size: 15,
                color: foremanNames.isEmpty
                    ? const Color(0xFFA32D2D)
                    : Colors.black54,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  foremanNames.isEmpty
                      ? tr('No foreman assigned', 'Sin capataz asignado')
                      : foremanNames,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foremanNames.isEmpty
                        ? const Color(0xFFA32D2D)
                        : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Crew, one line per worker — like the paper sheet
          if (workerIds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: Text(
                tr('No workers assigned', 'Sin trabajadores asignados'),
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[500],
                ),
              ),
            )
          else
            for (final id in workerIds)
              if ((names[id] ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 21, bottom: 3),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: names[id],
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: ' · ${AppStrings.role(roles[id] ?? '')}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        TextSpan(
                          text: areaOfWorker.containsKey(id)
                              ? ' · ${areaOfWorker[id]}'
                              : tr(' · no area yet', ' · aún sin área'),
                          style: TextStyle(
                            color: areaOfWorker.containsKey(id)
                                ? Colors.grey[800]
                                : Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
          const SizedBox(height: 4),
          Text(
            tr(
              '${workerIds.length} workers',
              '${workerIds.length} trabajadores',
            ),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
