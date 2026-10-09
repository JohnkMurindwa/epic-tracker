import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'app_strings.dart';

/// Local (on-device) notifications. Currently used for one thing: reminding
/// a worker who is still clocked in at the end of the work day.
///
/// The reminder is scheduled on the phone when the worker clocks in and
/// cancelled when they clock out, so it needs no server and works offline.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int _clockOutReminderId = 1;

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

  /// Schedules today's end-of-day reminder if [isClockedIn], otherwise cancels
  /// it. Safe to call repeatedly — it always replaces the previous reminder.
  static Future<void> syncClockOutReminder({required bool isClockedIn}) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _clockOutReminderId);
      if (!isClockedIn) return;

      final now = DateTime.now();
      final remindAt = DateTime(
        now.year,
        now.month,
        now.day,
        reminderHour,
        reminderMinute,
      );
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
          'It\'s 4:00 PM. Tap to tell us what time you left, or that you\'re still working.',
          'Son las 4:00 PM. Toca para decirnos a qué hora saliste, o que sigues trabajando.',
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
