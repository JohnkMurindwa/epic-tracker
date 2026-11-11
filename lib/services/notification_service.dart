import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'app_strings.dart';

/// Local (on-device) notifications: reminding a worker who is still clocked
/// in at the end of the work day, and one who hasn't clocked in after the
/// site's start time.
///
/// Reminders are scheduled on the phone whenever the dashboard syncs state
/// (open, clock-in, clock-out), so they need no server and work offline.
/// Times come from the site's standing hours (workStart/workEnd on the
/// project, set by the foreman or supervisor); without them, the clock-out
/// reminder falls back to 4:00 PM and no clock-in reminder is scheduled.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int _clockOutReminderId = 1;
  static const int _clockInReminderId = 2;

  /// Grace periods after the site's start/end before a reminder fires.
  static const Duration clockInGrace = Duration(minutes: 15);
  static const Duration clockOutGrace = Duration(minutes: 30);

  /// Time of day the "forgot to clock out" reminder fires (4:00 PM).
  /// The in-app missed clock-out dialog uses the same time.
  static const int reminderHour = 16;
  static const int reminderMinute = 0;

  /// Call once in `main()` before `runApp`.
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Ask for permission at first clock-in, not on app launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// End-of-day reminder time on [day]: the site's end ('HH:mm') plus
  /// [clockOutGrace], or the 4:00 PM default when the site has no hours.
  static DateTime clockOutCutoff(DateTime day, String? workEnd) {
    final end = _parse(workEnd, day);
    return end != null
        ? end.add(clockOutGrace)
        : DateTime(day.year, day.month, day.day, reminderHour, reminderMinute);
  }

  /// Schedules today's end-of-day reminder if [isClockedIn], otherwise cancels
  /// it. Safe to call repeatedly — it always replaces the previous reminder.
  /// [workEnd] is the site's standing end time ('HH:mm'), when it has one.
  static Future<void> syncClockOutReminder({
    required bool isClockedIn,
    String? workEnd,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _clockOutReminderId);
      if (!isClockedIn) return;

      final now = DateTime.now();
      final remindAt = clockOutCutoff(now, workEnd);
      // Clocked in after the reminder time (overtime): no reminder today.
      if (!remindAt.isAfter(now)) return;

      if (!await _requestPermission()) return;

      await _plugin.zonedSchedule(
        id: _clockOutReminderId,
        // remindAt is phone-local time; converting the instant to UTC keeps
        // it firing at that local time without needing the device time zone.
        scheduledDate: tz.TZDateTime.from(remindAt, tz.UTC),
        title: tr('Still clocked in?', '¿Sigues con la entrada registrada?'),
        body: tr(
          'The work day is over. Tap to tell us what time you left, or that you\'re still working.',
          'La jornada terminó. Toca para decirnos a qué hora saliste, o que sigues trabajando.',
        ),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'clock_out_reminder',
            tr('Clock-out reminders', 'Recordatorios de salida'),
            channelDescription: tr(
              'Reminds you to clock out at the end of the day',
              'Te recuerda registrar tu salida al final del día',
            ),
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Inexact: may arrive a few minutes late, but needs no special
        // "exact alarm" permission on Android.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Could not schedule clock-out reminder: $e');
    }
  }

  static Future<void> cancelClockOutReminder() =>
      syncClockOutReminder(isClockedIn: false);

  /// Schedules the "you haven't clocked in" nudge at the next work-day start
  /// (+[clockInGrace]) for [siteName], or cancels it when [workStart] is null.
  ///
  /// [alreadyInToday] skips today and schedules for tomorrow instead; the
  /// next sync (tomorrow's open or clock-in) rolls it forward again.
  static Future<void> syncClockInReminder({
    required String? workStart,
    required bool alreadyInToday,
    required String siteName,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _clockInReminderId);
      if (workStart == null) return;

      final now = DateTime.now();
      var remindAt = _parse(workStart, now)!.add(clockInGrace);
      if (alreadyInToday || !remindAt.isAfter(now)) {
        remindAt = remindAt.add(const Duration(days: 1));
      }

      if (!await _requestPermission()) return;

      await _plugin.zonedSchedule(
        id: _clockInReminderId,
        scheduledDate: tz.TZDateTime.from(remindAt, tz.UTC),
        title: tr('Not clocked in yet', 'Aún no registras entrada'),
        body: tr(
          'Your crew at $siteName starts at ${_display(workStart)}. Don\'t forget to clock in.',
          'Tu equipo en $siteName empieza a las ${_display(workStart)}. No olvides registrar tu entrada.',
        ),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'clock_in_reminder',
            tr('Clock-in reminders', 'Recordatorios de entrada'),
            channelDescription: tr(
              'Reminds you to clock in after your site\'s start time',
              'Te recuerda registrar tu entrada después de la hora de inicio',
            ),
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Could not schedule clock-in reminder: $e');
    }
  }

  static Future<void> cancelClockInReminder() => syncClockInReminder(
    workStart: null,
    alreadyInToday: false,
    siteName: '',
  );

  /// 'HH:mm' on [day], or null if malformed.
  static DateTime? _parse(String? hhmm, DateTime day) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h > 23 || m > 59) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  /// '07:00' → '7:00 AM' for notification text.
  static String _display(String hhmm) {
    final t = _parse(hhmm, DateTime.now());
    if (t == null) return hhmm;
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static Future<bool> _requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      // null on Android 12 and older, where no runtime permission exists.
      return await android.requestNotificationsPermission() ?? true;
    }
    return false;
  }
}
