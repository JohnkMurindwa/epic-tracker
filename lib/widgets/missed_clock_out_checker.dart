import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/app_strings.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

/// Asks a worker who is still clocked in at the end of the day what time
/// they left, and clocks them out at that time.
///
/// Two triggers:
///  * **Same day (primary):** at the site's end time + 30 min (or 4:00 PM
///    when the site has no standing hours) while the app is open, or as
///    soon as it is opened or brought back after that. The worker can also
///    answer "I'm still working", which asks again an hour later.
///  * **Later day (backup):** on opening the app, any earlier day (last
///    two weeks) whose session was never closed.
///
/// Sessions clocked in after the cutoff (overtime) are not prompted the
/// same day; the backup catches them if they are never closed.
///
/// Usage: mix into a dashboard's State, call [startMissedClockOutChecks] in
/// `initState` and [stopMissedClockOutChecks] in `dispose`.
mixin MissedClockOutChecker<T extends StatefulWidget> on State<T> {
  /// The signed-in user whose sessions are checked.
  String get checkerUserId;

  /// Called after a session was clocked out through the dialog, so the
  /// screen can reload today's state.
  void onMissedClockOutSaved();

  final FirestoreService _missedService = FirestoreService();
  Timer? _missedTimer;
  AppLifecycleListener? _missedLifecycle;
  bool _missedDialogOpen = false;
  DateTime? _snoozedUntil;

  static const _snooze = Duration(hours: 1);

  /// Site end times already looked up this session (projectId → 'HH:mm').
  final Map<String, String?> _siteEndCache = {};

  void startMissedClockOutChecks() {
    _missedLifecycle = AppLifecycleListener(
      onResume: () {
        _scheduleSameDayCheck();
        checkMissedClockOuts();
      },
    );
    _scheduleSameDayCheck();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkMissedClockOuts());
  }

  void stopMissedClockOutChecks() {
    _missedTimer?.cancel();
    _missedLifecycle?.dispose();
  }

  /// End-of-day cutoff on [day] for the site of [entry]: the site's end
  /// time + 30 min, or 4:00 PM when the site has no standing hours.
  Future<DateTime> _cutoffFor(DateTime day, Map<String, dynamic> entry) async {
    final projectId = entry['projectId'] as String?;
    String? end;
    if (projectId != null) {
      if (_siteEndCache.containsKey(projectId)) {
        end = _siteEndCache[projectId];
      } else {
        end = (await _missedService.getProjectWorkHours(projectId)).end;
        _siteEndCache[projectId] = end;
      }
    }
    return NotificationService.clockOutCutoff(day, end);
  }

  /// Timers do not run while the app is in the background, so this is
  /// re-armed whenever the app comes back to the foreground.
  Future<void> _scheduleSameDayCheck() async {
    _missedTimer?.cancel();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    // Today's cutoff depends on the site of today's open session, if any.
    var target = NotificationService.clockOutCutoff(now, null);
    try {
      final logs = await _missedService.getLogsWithOpenEntry(checkerUserId);
      for (final log in logs) {
        final logDate = (log['log_date'] as Timestamp).toDate();
        if (logDate.isBefore(todayStart)) continue;
        final entry = List<Map<String, dynamic>>.from(
          log['time_entries'],
        ).last;
        target = await _cutoffFor(now, entry);
      }
    } catch (_) {
      // Offline: keep the default cutoff.
    }

    final snoozedUntil = _snoozedUntil;
    if (snoozedUntil != null && snoozedUntil.isAfter(target)) {
      target = snoozedUntil;
    }
    if (!mounted) return;
    if (target.isAfter(now)) {
      _missedTimer = Timer(target.difference(now), checkMissedClockOuts);
    }
  }

  Future<void> checkMissedClockOuts() async {
    if (_missedDialogOpen || !mounted) return;

    final List<Map<String, dynamic>> logs;
    try {
      logs = await _missedService.getLogsWithOpenEntry(checkerUserId);
    } catch (e) {
      debugPrint('Missed clock-out check failed: $e');
      return;
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    for (final log in logs) {
      if (!mounted || _missedDialogOpen) return;

      final logDate = (log['log_date'] as Timestamp).toDate();
      final isToday = !logDate.isBefore(todayStart);
      final entry = List<Map<String, dynamic>>.from(log['time_entries']).last;
      final clockIn = (entry['clockIn'] as Timestamp?)?.toDate();
      if (clockIn == null) continue;

      if (isToday) {
        final cutoff = await _cutoffFor(now, entry);
        final snoozedUntil = _snoozedUntil;
        if (now.isBefore(cutoff)) continue;
        if (!clockIn.isBefore(cutoff)) continue; // overtime session
        if (snoozedUntil != null && now.isBefore(snoozedUntil)) continue;
      }

      final leftAt = await _askWhenTheyLeft(
        log: log,
        entry: entry,
        clockIn: clockIn,
        isToday: isToday,
      );

      if (leftAt == null) {
        // "I'm still working": ask again later today.
        _snoozedUntil = DateTime.now().add(_snooze);
        _scheduleSameDayCheck();
        return;
      }

      try {
        await _missedService.clockOutMissed(
          logId: log['id'] as String,
          userId: checkerUserId,
          leftAt: leftAt,
        );
        if (isToday) await NotificationService.cancelClockOutReminder();
        if (!mounted) return;
        onMissedClockOutSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Clocked out at ${_formatTime(leftAt)}',
                'Salida registrada a las ${_formatTime(leftAt)}',
              ),
            ),
            backgroundColor: Colors.black87,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        return;
      }
    }
  }

  /// Shows the dialog. Returns the chosen leave time, or null if the worker
  /// said they are still working (only offered for today).
  Future<DateTime?> _askWhenTheyLeft({
    required Map<String, dynamic> log,
    required Map<String, dynamic> entry,
    required DateTime clockIn,
    required bool isToday,
  }) async {
    final day = (log['log_date'] as Timestamp).toDate();
    final now = DateTime.now();
    // Latest allowed: now for today, end of that day for an earlier day.
    final latest = isToday
        ? now
        : DateTime(day.year, day.month, day.day, 23, 59);

    // Suggest the site's cutoff (end + 30 min, or 4:00 PM), kept between
    // clock-in and the latest allowed time.
    DateTime suggested;
    try {
      suggested = await _cutoffFor(day, entry);
    } catch (_) {
      suggested = NotificationService.clockOutCutoff(day, null);
    }
    if (!mounted) return null;
    if (!suggested.isAfter(clockIn)) {
      suggested = clockIn.add(const Duration(minutes: 1));
    }
    if (suggested.isAfter(latest)) suggested = latest;

    final areaName = entry['areaName'] as String?;
    final projectName = entry['projectName'] as String? ?? '';
    final place = areaName == null ? projectName : '$areaName · $projectName';
    final dayLabel = DateFormat(
      'EEEE, MMM d',
      AppStrings.dateLocale,
    ).format(day);

    // Kept outside the dialog builder so they survive its rebuilds.
    var leftAt = suggested;
    String? error;

    _missedDialogOpen = true;
    try {
      return await showDialog<DateTime>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> pickTime() async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(leftAt),
                );
                if (picked == null) return;
                final chosen = DateTime(
                  day.year,
                  day.month,
                  day.day,
                  picked.hour,
                  picked.minute,
                );
                setDialogState(() {
                  leftAt = chosen;
                  if (!chosen.isAfter(clockIn)) {
                    error = tr(
                      'Must be after you clocked in (${_formatTime(clockIn)}).',
                      'Debe ser después de tu entrada (${_formatTime(clockIn)}).',
                    );
                  } else if (chosen.isAfter(latest)) {
                    error = tr(
                      'That time hasn\'t happened yet.',
                      'Esa hora todavía no ha llegado.',
                    );
                  } else {
                    error = null;
                  }
                });
              }

              return AlertDialog(
                title: Text(
                  tr(
                    'You forgot to clock out',
                    'Olvidaste registrar tu salida',
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday
                          ? tr(
                              'You\'re still clocked in at $place since ${_formatTime(clockIn)}.',
                              'Sigues con entrada registrada en $place desde las ${_formatTime(clockIn)}.',
                            )
                          : tr(
                              'On $dayLabel you clocked in at $place at ${_formatTime(clockIn)} and never clocked out.',
                              'El $dayLabel registraste tu entrada en $place a las ${_formatTime(clockIn)} y nunca registraste la salida.',
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('What time did you leave?', '¿A qué hora saliste?'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: pickTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        _formatTime(leftAt),
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (isToday)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(tr('I\'m still working', 'Sigo trabajando')),
                    ),
                  ElevatedButton(
                    onPressed: error != null
                        ? null
                        : () => Navigator.pop(dialogContext, leftAt),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(tr('Clock Out', 'Registrar Salida')),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _missedDialogOpen = false;
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
