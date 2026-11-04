import 'package:flutter/material.dart';
import '../services/app_strings.dart';
import '../services/firestore_service.dart';

/// Red "⚠ in 1.8 mi from site" chip for a time entry whose clock-in or
/// clock-out happened outside the job site's radius. Renders nothing for an
/// on-site entry, or one made before the site had a pin.
class OffSiteBadge extends StatelessWidget {
  final Map<String, dynamic> entry;
  final EdgeInsetsGeometry margin;

  const OffSiteBadge(this.entry, {super.key, this.margin = EdgeInsets.zero});

  /// True when either end of [entry] was off site.
  static bool isOffSite(Map<String, dynamic> entry) =>
      entry['clockInOffSite'] == true || entry['clockOutOffSite'] == true;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (entry['clockInOffSite'] == true) {
      final d = formatDistanceFt(entry['clockInDistanceFt'] as num?);
      parts.add(tr('in $d from site', 'entrada a $d de la obra'));
    }
    if (entry['clockOutOffSite'] == true) {
      final d = formatDistanceFt(entry['clockOutDistanceFt'] as num?);
      parts.add(tr('out $d from site', 'salida a $d de la obra'));
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.red),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              parts.join(' • '),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
