import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// Builds the timesheet export as an Excel workbook laid out like Epic's
/// paper "Weekly Timecard Report" (Week 1 / Semana 1, Week 2 / Semana 2):
///
///  * a **Summary** sheet: hours per employee per week, and
///  * **one sheet per employee**: for each week, one block per day
///    (Mon–Sat, plus Sunday if worked) with time in/out, lunch and total
///    hours, followed by one line per area worked — project, hours per
///    area, area # and description — then week and period totals, notes
///    and a signature line.
///
/// [logs] are raw `daily_logs` documents (with their `id`) in the range.
/// Returns the encoded .xlsx bytes.
List<int>? buildTimecardWorkbook({
  required List<Map<String, dynamic>> logs,
  required DateTime start,
  required DateTime end,
}) {
  final excel = Excel.createExcel();
  final weeks = _weeksInRange(start, end);

  // Group each employee's logs by day.
  final employees = <String, _Employee>{};
  for (final log in logs) {
    final id = (log['installer_id'] ?? log['installer_name'] ?? '') as String;
    final employee = employees.putIfAbsent(
      id,
      () => _Employee(
        name: (log['installer_name'] as String?) ?? 'Unknown',
        role: (log['installer_role'] as String?) ?? '',
      ),
    );
    final date = (log['log_date'] as Timestamp).toDate();
    employee.days[_dayKey(date)] = _Day.fromLog(log);
  }
  final sorted = employees.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  // Summary first (renaming the default sheet keeps it first).
  const summaryName = 'Summary - Resumen';
  excel.rename('Sheet1', summaryName);
  _writeSummary(excel[summaryName], sorted, weeks, start, end);

  final usedNames = <String>{summaryName};
  for (final employee in sorted) {
    final sheetName = _sheetName(employee.name, usedNames);
    _writeEmployeeSheet(excel[sheetName], employee, weeks, start, end);
  }

  excel.setDefaultSheet(summaryName);
  return excel.encode();
}

// ─── Layout ────────────────────────────────────────────────

const _columns = [
  'Day /\nDía',
  'Date /\nFecha',
  'Time In /\nHora de Entrada',
  'Time Out /\nHora de Salida',
  'Lunch Start /\nInicio de Almuerzo',
  'Lunch End /\nFin de Almuerzo',
  'Total Hours Worked /\nHoras Trabajadas',
  'Project Name /\nNombre del Proyecto',
  'Hours per Area /\nHoras por Área',
  'Area # /\nÁrea #',
  'Description of Work /\nDescripción del Trabajo',
];
const _columnWidths = [
  22.0,
  12.0,
  13.0,
  13.0,
  14.0,
  14.0,
  15.0,
  26.0,
  16.0,
  9.0,
  44.0,
];
const _lastCol = 10;

const _dayNames = [
  'Monday / Lunes',
  'Tuesday / Martes',
  'Wednesday / Miércoles',
  'Thursday / Jueves',
  'Friday / Viernes',
  'Saturday / Sábado',
  'Sunday / Domingo',
];

final _thin = Border(borderStyle: BorderStyle.Thin);
final _cellStyle = CellStyle(
  leftBorder: _thin,
  rightBorder: _thin,
  topBorder: _thin,
  bottomBorder: _thin,
  verticalAlign: VerticalAlign.Top,
  textWrapping: TextWrapping.WrapText,
);
final _hoursStyle = _cellStyle.copyWith(
  numberFormat: NumFormat.standard_2,
  horizontalAlignVal: HorizontalAlign.Right,
);
final _dayStyle = _cellStyle.copyWith(boldVal: true);
final _headerStyle = _cellStyle.copyWith(
  boldVal: true,
  backgroundColorHexVal: ExcelColor.fromHexString('FFD9D9D9'),
  horizontalAlignVal: HorizontalAlign.Center,
  verticalAlignVal: VerticalAlign.Center,
);
final _weekBandStyle = CellStyle(
  bold: true,
  fontSize: 12,
  backgroundColorHex: ExcelColor.fromHexString('FFA6A6A6'),
  verticalAlign: VerticalAlign.Center,
);
final _totalLabelStyle = _cellStyle.copyWith(
  boldVal: true,
  horizontalAlignVal: HorizontalAlign.Right,
);
final _totalStyle = _hoursStyle.copyWith(boldVal: true);
// No wrapping, so the label spills left across the empty cells beside it.
final _weekTotalLabelStyle = CellStyle(
  bold: true,
  horizontalAlign: HorizontalAlign.Right,
  topBorder: _thin,
  bottomBorder: _thin,
);
final _titleStyle = CellStyle(bold: true, fontSize: 14);
final _labelStyle = CellStyle(bold: true);

void _writeEmployeeSheet(
  Sheet sheet,
  _Employee employee,
  List<DateTime> weeks,
  DateTime start,
  DateTime end,
) {
  for (var c = 0; c <= _lastCol; c++) {
    sheet.setColumnWidth(c, _columnWidths[c]);
  }

  var row = 0;
  _put(
    sheet,
    0,
    row,
    TextCellValue(
      'EPIC CERAMIC & STONE, INC. — WEEKLY TIMECARD REPORT / '
      'REPORTE SEMANAL DE HORAS',
    ),
    _titleStyle,
  );
  row += 2;
  _put(
    sheet,
    0,
    row,
    TextCellValue('Employee Name / Nombre de Empleado:'),
    _labelStyle,
  );
  _put(sheet, 3, row, TextCellValue(employee.name), _labelStyle);
  _put(sheet, 7, row, TextCellValue('Role / Puesto:'), _labelStyle);
  _put(sheet, 8, row, TextCellValue(_role(employee.role)));
  row++;
  _put(sheet, 0, row, TextCellValue('Period / Período:'), _labelStyle);
  _put(sheet, 3, row, TextCellValue('${_date(start)} – ${_date(end)}'));
  row += 2;

  double periodTotal = 0;
  for (var w = 0; w < weeks.length; w++) {
    final monday = weeks[w];
    final sunday = monday.add(const Duration(days: 6));

    // Week band
    _put(
      sheet,
      0,
      row,
      TextCellValue(
        'WEEK ${w + 1} / SEMANA ${w + 1}    '
        '(${_date(monday)} – ${_date(sunday)})',
      ),
      _weekBandStyle,
    );
    for (var c = 1; c <= _lastCol; c++) {
      _put(sheet, c, row, null, _weekBandStyle);
    }
    sheet.setRowHeight(row, 20);
    row++;

    // Column headers
    for (var c = 0; c <= _lastCol; c++) {
      _put(sheet, c, row, TextCellValue(_columns[c]), _headerStyle);
    }
    sheet.setRowHeight(row, 32);
    row++;

    double weekTotal = 0;
    for (var d = 0; d < 7; d++) {
      final date = monday.add(Duration(days: d));
      final day = employee.days[_dayKey(date)];
      // Mon–Sat always (like the paper form); Sunday only if worked.
      if (d == 6 && day == null) continue;
      final inRange =
          !date.isBefore(_dateOnly(start)) && !date.isAfter(_dateOnly(end));

      _put(sheet, 0, row, TextCellValue(_dayNames[d]), _dayStyle);
      _put(
        sheet,
        1,
        row,
        inRange ? TextCellValue(_date(date)) : null,
        _cellStyle,
      );

      if (day == null) {
        for (var c = 2; c <= _lastCol; c++) {
          _put(sheet, c, row, null, _cellStyle);
        }
        row++;
        continue;
      }

      weekTotal += day.totalHours;
      _put(sheet, 2, row, _timeCell(day.timeIn), _cellStyle);
      _put(
        sheet,
        3,
        row,
        day.stillClockedIn
            ? TextCellValue('Still clocked in / Sin salida')
            : _timeCell(day.timeOut),
        _cellStyle,
      );
      _put(sheet, 4, row, _timeCell(day.lunchStart), _cellStyle);
      _put(sheet, 5, row, _timeCell(day.lunchEnd), _cellStyle);
      _put(sheet, 6, row, DoubleCellValue(day.totalHours), _hoursStyle);

      // One line per area; the first shares the day's row.
      final lines = day.lines.isEmpty ? [null] : day.lines;
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) {
          for (var c = 0; c <= 6; c++) {
            _put(sheet, c, row, null, _cellStyle);
          }
        }
        final line = lines[i];
        _put(
          sheet,
          7,
          row,
          line == null ? null : TextCellValue(line.project),
          _cellStyle,
        );
        _put(
          sheet,
          8,
          row,
          line == null ? null : DoubleCellValue(line.hours),
          _hoursStyle,
        );
        _put(
          sheet,
          9,
          row,
          line == null ? null : TextCellValue(line.areaNumber),
          _cellStyle,
        );
        _put(
          sheet,
          10,
          row,
          line == null ? null : TextCellValue(line.description),
          _cellStyle,
        );
        row++;
      }
    }

    // Week total: label right-aligned next to the total, spilling left.
    for (var c = 0; c <= 4; c++) {
      _put(sheet, c, row, null, _weekTotalLabelStyle);
    }
    _put(
      sheet,
      5,
      row,
      TextCellValue('Week ${w + 1} total / Total semana ${w + 1}'),
      _weekTotalLabelStyle,
    );
    _put(sheet, 6, row, DoubleCellValue(weekTotal), _totalStyle);
    periodTotal += weekTotal;
    row += 2;
  }

  _put(
    sheet,
    0,
    row,
    TextCellValue('TOTAL HOURS FOR PERIOD / TOTAL DE HORAS DEL PERÍODO'),
    _labelStyle,
  );
  _put(sheet, 6, row, DoubleCellValue(periodTotal), _totalStyle);
  row += 2;

  _put(sheet, 0, row, TextCellValue('Notes / Notas:'), _labelStyle);
  row++;
  for (var i = 0; i < 3; i++) {
    for (var c = 0; c <= _lastCol; c++) {
      _put(sheet, c, row, null, _cellStyle);
    }
    sheet.setRowHeight(row, 22);
    row++;
  }
  row++;

  _put(
    sheet,
    0,
    row,
    TextCellValue('Employee Signature / Firma del Empleado:'),
    _labelStyle,
  );
  _put(sheet, 3, row, TextCellValue('______________________________'));
  _put(sheet, 7, row, TextCellValue('Date / Fecha:'), _labelStyle);
  _put(sheet, 8, row, TextCellValue('______________'));
}

void _writeSummary(
  Sheet sheet,
  List<_Employee> employees,
  List<DateTime> weeks,
  DateTime start,
  DateTime end,
) {
  final headers = [
    'Employee /\nEmpleado',
    'Role /\nPuesto',
    for (var w = 0; w < weeks.length; w++)
      'Week ${w + 1} hours /\nHoras semana ${w + 1}',
    'Total Hours /\nHoras Totales',
    'Days Worked /\nDías Trabajados',
    'Missed Clock-outs /\nSalidas Olvidadas',
  ];
  sheet.setColumnWidth(0, 26);
  sheet.setColumnWidth(1, 18);
  for (var c = 2; c < headers.length; c++) {
    sheet.setColumnWidth(c, 16);
  }

  _put(
    sheet,
    0,
    0,
    TextCellValue('EPIC CERAMIC & STONE, INC. — TIMECARD SUMMARY / RESUMEN'),
    _titleStyle,
  );
  _put(
    sheet,
    0,
    1,
    TextCellValue('Period / Período: ${_date(start)} – ${_date(end)}'),
  );

  var row = 3;
  for (var c = 0; c < headers.length; c++) {
    _put(sheet, c, row, TextCellValue(headers[c]), _headerStyle);
  }
  sheet.setRowHeight(row, 32);
  row++;

  final weekTotals = List<double>.filled(weeks.length, 0);
  double grandTotal = 0;
  for (final employee in employees) {
    var c = 0;
    _put(sheet, c++, row, TextCellValue(employee.name), _dayStyle);
    _put(sheet, c++, row, TextCellValue(_role(employee.role)), _cellStyle);
    double total = 0;
    for (var w = 0; w < weeks.length; w++) {
      final hours = employee.hoursInWeek(weeks[w]);
      weekTotals[w] += hours;
      total += hours;
      _put(sheet, c++, row, DoubleCellValue(hours), _hoursStyle);
    }
    grandTotal += total;
    _put(sheet, c++, row, DoubleCellValue(total), _totalStyle);
    _put(sheet, c++, row, IntCellValue(employee.days.length), _cellStyle);
    _put(sheet, c++, row, IntCellValue(employee.missedClockOuts), _cellStyle);
    row++;
  }

  // Totals row
  _put(sheet, 0, row, TextCellValue('TOTAL'), _totalLabelStyle);
  _put(sheet, 1, row, null, _totalLabelStyle);
  for (var w = 0; w < weeks.length; w++) {
    _put(sheet, 2 + w, row, DoubleCellValue(weekTotals[w]), _totalStyle);
  }
  _put(sheet, 2 + weeks.length, row, DoubleCellValue(grandTotal), _totalStyle);
}

// ─── Data ──────────────────────────────────────────────────

class _Employee {
  final String name;
  final String role;

  /// Keyed by [_dayKey].
  final Map<String, _Day> days = {};

  _Employee({required this.name, required this.role});

  double hoursInWeek(DateTime monday) {
    double total = 0;
    for (var d = 0; d < 7; d++) {
      total += days[_dayKey(monday.add(Duration(days: d)))]?.totalHours ?? 0;
    }
    return total;
  }

  int get missedClockOuts =>
      days.values.fold(0, (total, day) => total + day.missedClockOuts);
}

class _Day {
  final DateTime? timeIn;
  final DateTime? timeOut;
  final DateTime? lunchStart;
  final DateTime? lunchEnd;
  final bool stillClockedIn;
  final double totalHours;
  final int missedClockOuts;
  final List<_Line> lines;

  _Day({
    required this.timeIn,
    required this.timeOut,
    required this.lunchStart,
    required this.lunchEnd,
    required this.stillClockedIn,
    required this.totalHours,
    required this.missedClockOuts,
    required this.lines,
  });

  factory _Day.fromLog(Map<String, dynamic> log) {
    final entries = List<Map<String, dynamic>>.from(log['time_entries'] ?? []);

    DateTime? timeIn;
    DateTime? timeOut;
    double total = 0;
    var missed = 0;
    // Combine sessions at the same project + area into one line, like the
    // paper form's "hours per area" rows.
    final lines = <String, _Line>{};

    for (final entry in entries) {
      final clockIn = (entry['clockIn'] as Timestamp?)?.toDate();
      final clockOut = (entry['clockOut'] as Timestamp?)?.toDate();
      if (clockIn != null && (timeIn == null || clockIn.isBefore(timeIn))) {
        timeIn = clockIn;
      }
      if (clockOut != null && (timeOut == null || clockOut.isAfter(timeOut))) {
        timeOut = clockOut;
      }
      if (entry['clockOutMissed'] == true) missed++;

      final hours = ((entry['hoursWorked'] ?? 0) as num).toDouble();
      total += hours;

      final project = (entry['projectName'] as String?) ?? '';
      final areaName = entry['areaName'] as String?;
      final key = '$project|${areaName ?? ''}';
      final line = lines.putIfAbsent(
        key,
        () => _Line(project: project, areaNumber: _areaNumber(entry)),
      );
      line.hours += hours;
      final description = _description(entry);
      if (description.isNotEmpty && !line.descriptions.contains(description)) {
        line.descriptions.add(description);
      }
    }

    final stillClockedIn =
        entries.isNotEmpty && entries.last['clockOut'] == null;

    return _Day(
      timeIn: timeIn,
      timeOut: stillClockedIn ? null : timeOut,
      lunchStart: (log['lunch_start'] as Timestamp?)?.toDate(),
      lunchEnd: (log['lunch_end'] as Timestamp?)?.toDate(),
      stillClockedIn: stillClockedIn,
      totalHours: total,
      missedClockOuts: missed,
      lines: lines.values.toList(),
    );
  }
}

class _Line {
  final String project;
  final String areaNumber;
  double hours = 0;
  final List<String> descriptions = [];

  _Line({required this.project, required this.areaNumber});

  String get description => descriptions.join('; ');
}

/// Area # for an entry. Imported areas are named "A12 — Sliding door…",
/// so the code before " — " is the area number. Foremen clock in at the
/// whole site (no area).
String _areaNumber(Map<String, dynamic> entry) {
  final areaName = entry['areaName'] as String?;
  if (areaName == null) {
    return entry['areaId'] == null ? 'Site / Obra' : '';
  }
  final dash = areaName.indexOf(' — ');
  return dash > 0 ? areaName.substring(0, dash) : areaName;
}

/// Work description plus the area name, so each line reads on its own.
String _description(Map<String, dynamic> entry) {
  final areaName = entry['areaName'] as String?;
  final dash = areaName?.indexOf(' — ') ?? -1;
  final areaTitle = (areaName != null && dash > 0)
      ? areaName.substring(dash + 3)
      : null;
  final work = (entry['description'] as String?) ?? '';
  if (entry['areaName'] == null && entry['areaId'] == null) {
    return work.isEmpty ? 'Site supervision / Supervisión de obra' : work;
  }
  if (areaTitle == null || areaTitle.isEmpty) return work;
  return work.isEmpty ? areaTitle : '$areaTitle: $work';
}

// ─── Helpers ───────────────────────────────────────────────

void _put(Sheet sheet, int col, int row, CellValue? value, [CellStyle? style]) {
  final cell = sheet.cell(
    CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
  );
  cell.value = value;
  if (style != null) cell.cellStyle = style;
}

CellValue? _timeCell(DateTime? time) =>
    time == null ? null : TextCellValue(DateFormat('h:mm a').format(time));

String _date(DateTime d) => DateFormat('MM/dd/yyyy').format(d);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Mondays of every week overlapping [start]..[end].
List<DateTime> _weeksInRange(DateTime start, DateTime end) {
  final first = _dateOnly(start);
  var monday = first.subtract(Duration(days: first.weekday - 1));
  final last = _dateOnly(end);
  final weeks = <DateTime>[];
  while (!monday.isAfter(last)) {
    weeks.add(monday);
    monday = DateTime(monday.year, monday.month, monday.day + 7);
  }
  return weeks;
}

/// Role label for the export. Data stays in English (payroll document);
/// only the headers are bilingual.
String _role(String role) =>
    const {
      'installer': 'Installer',
      'junior_installer': 'Junior Installer',
      'helper': 'Helper',
      'foreman': 'Foreman',
      'supervisor': 'Supervisor',
      'admin': 'Admin',
    }[role] ??
    role;

/// Excel sheet names: max 31 chars, no []:*?/\, unique.
String _sheetName(String name, Set<String> used) {
  var base = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (base.isEmpty) base = 'Employee';
  if (base.length > 28) base = base.substring(0, 28);
  var candidate = base;
  var n = 2;
  while (used.contains(candidate)) {
    candidate = '$base ($n)';
    n++;
  }
  used.add(candidate);
  return candidate;
}
