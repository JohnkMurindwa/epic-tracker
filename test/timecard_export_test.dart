import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:epic_tracker/services/timecard_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp _t(int y, int m, int d, int h, int min) =>
    Timestamp.fromDate(DateTime(y, m, d, h, min));

void main() {
  // Monday 2026-09-28 .. Sunday 2026-10-11 (two weeks, like the paper form).
  final start = DateTime(2026, 9, 28);
  final end = DateTime(2026, 10, 11);

  final logs = <Map<String, dynamic>>[
    // Installer, Monday of week 1: 7:00–3:30, lunch 11:00–11:30, 8 h split
    // across three areas (as on the paper example).
    {
      'id': 'log1',
      'installer_id': 'u1',
      'installer_name': 'Salvador',
      'installer_role': 'installer',
      'log_date': _t(2026, 9, 28, 0, 0),
      'lunch_start': _t(2026, 9, 28, 11, 0),
      'lunch_end': _t(2026, 9, 28, 11, 30),
      'time_entries': [
        {
          'projectName': '19 del Mar',
          'areaId': 'a7',
          'areaName': 'A7 — Fiberglass shower',
          'clockIn': _t(2026, 9, 28, 7, 0),
          'clockOut': _t(2026, 9, 28, 10, 0),
          'hoursWorked': 3.0,
          'description': 'Waterproofing at shower pan',
        },
        {
          'projectName': '19 del Mar',
          'areaId': 'a5',
          'areaName': 'A5 — Gym',
          'clockIn': _t(2026, 9, 28, 10, 0),
          'clockOut': _t(2026, 9, 28, 13, 30),
          'hoursWorked': 3.0,
          'description': 'Install tile',
        },
        {
          'projectName': '19 del Mar',
          'areaId': 'a22',
          'areaName': 'A22 — Master bath',
          'clockIn': _t(2026, 9, 28, 13, 30),
          'clockOut': _t(2026, 9, 28, 15, 30),
          'hoursWorked': 2.0,
          'description': 'Grout',
        },
      ],
    },
    // Foreman in week 2: whole-site entry, missed clock-out.
    {
      'id': 'log2',
      'installer_id': 'u2',
      'installer_name': 'Andrés',
      'installer_role': 'foreman',
      'log_date': _t(2026, 10, 6, 0, 0),
      'time_entries': [
        {
          'projectName': 'Ocean View',
          'areaId': null,
          'areaName': null,
          'clockIn': _t(2026, 10, 6, 6, 30),
          'clockOut': _t(2026, 10, 6, 15, 0),
          'hoursWorked': 8.5,
          'description': 'Forgot to clock out',
          'clockOutMissed': true,
        },
      ],
    },
  ];

  test('builds a summary sheet and one timecard sheet per employee', () {
    final bytes = buildTimecardWorkbook(logs: logs, start: start, end: end);
    expect(bytes, isNotNull);

    // Keep a copy to open in Excel when checking the layout by eye.
    final outDir = Platform.environment['TIMECARD_EXPORT_DIR'];
    if (outDir != null) {
      File('$outDir/timecards_sample.xlsx').writeAsBytesSync(bytes!);
    }

    final book = Excel.decodeBytes(bytes!);
    expect(book.tables.keys.toList(), [
      'Summary - Resumen',
      'Andrés',
      'Salvador',
    ]);

    String text(Sheet s, int col, int row) =>
        s
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
            .value
            ?.toString() ??
        '';

    // Salvador: week 1 band, header, then Monday's block with 3 area lines.
    final salvador = book.tables['Salvador']!;
    final rows = List.generate(salvador.maxRows, (r) => text(salvador, 0, r));
    final week1 = rows.indexWhere((v) => v.startsWith('WEEK 1 / SEMANA 1'));
    final monday = week1 + 2;
    expect(text(salvador, 0, monday), 'Monday / Lunes');
    expect(text(salvador, 1, monday), '09/28/2026');
    expect(text(salvador, 2, monday), '7:00 AM');
    expect(text(salvador, 3, monday), '3:30 PM');
    expect(text(salvador, 4, monday), '11:00 AM');
    expect(text(salvador, 5, monday), '11:30 AM');
    expect(text(salvador, 6, monday), '8'); // shown as 8.00 (0.00 format)
    expect(text(salvador, 9, monday), 'A7');
    expect(text(salvador, 9, monday + 1), 'A5');
    expect(text(salvador, 9, monday + 2), 'A22');
    expect(text(salvador, 10, monday + 2), 'Master bath: Grout');
    expect(text(salvador, 0, monday + 3), 'Tuesday / Martes');
    expect(rows, contains('WEEK 2 / SEMANA 2    (10/05/2026 – 10/11/2026)'));

    // Foreman: whole-site line.
    final andres = book.tables['Andrés']!;
    final aRows = List.generate(andres.maxRows, (r) => text(andres, 9, r));
    expect(aRows, contains('Site / Obra'));
  });
}
