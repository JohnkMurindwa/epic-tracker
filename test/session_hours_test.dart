import 'package:epic_tracker/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int h, [int m = 0]) => DateTime(2026, 10, 21, h, m);

void main() {
  group('sessionHoursWorked', () {
    test('plain session with no lunch', () {
      expect(sessionHoursWorked(clockIn: _at(7), clockOut: _at(15, 30)), 8.5);
    });

    test('deducts a lunch taken inside the session', () {
      // 7:00–3:30 with 11:00–11:30 lunch = 8.0 h (the paper-form example)
      expect(
        sessionHoursWorked(
          clockIn: _at(7),
          clockOut: _at(15, 30),
          lunchStart: _at(11),
          lunchEnd: _at(11, 30),
        ),
        8.0,
      );
    });

    test('ignores a lunch taken in an earlier session that day', () {
      // Lunch 11:00–11:30 belongs to the morning area, not this 12:00 one.
      expect(
        sessionHoursWorked(
          clockIn: _at(12),
          clockOut: _at(15, 30),
          lunchStart: _at(11),
          lunchEnd: _at(11, 30),
        ),
        3.5,
      );
    });

    test('lunch still open at clock-out ends at clock-out', () {
      // Started lunch at 11:00, forgot to end it, clocked out at 11:45.
      expect(
        sessionHoursWorked(
          clockIn: _at(7),
          clockOut: _at(11, 45),
          lunchStart: _at(11),
          isOnLunch: true,
        ),
        4.0,
      );
    });

    test('never goes negative', () {
      expect(
        sessionHoursWorked(clockIn: _at(9), clockOut: _at(8)),
        0,
      );
    });
  });
}
