import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/app_strings.dart';
import '../../widgets/off_site_badge.dart';
import '../../services/file_export.dart';
import '../../services/timecard_export.dart';

class TimesheetsScreen extends StatefulWidget {
  const TimesheetsScreen({super.key});

  @override
  State<TimesheetsScreen> createState() => _TimesheetsScreenState();
}

class _TimesheetsScreenState extends State<TimesheetsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Default: two weeks starting on a Monday (last week + this week),
  // matching the paper timecard's Week 1 / Week 2.
  DateTime _startDate = _mondayOfLastWeek();
  DateTime _endDate = DateTime.now();
  bool _isLoading = false;
  bool _isExporting = false;
  List<Map<String, dynamic>> _timesheetRows = [];

  /// Raw daily logs for the range, used to build the timecard export.
  List<Map<String, dynamic>> _logs = [];

  static DateTime _mondayOfLastWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1 + 7));
  }

  @override
  void initState() {
    super.initState();
    _loadTimesheets();
  }

  Future<void> _loadTimesheets() async {
    setState(() => _isLoading = true);

    try {
      final startOfDay = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      );
      final endOfDay = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
      );

      final snapshot = await _db
          .collection('daily_logs')
          .where(
            'log_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('log_date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      final List<Map<String, dynamic>> rows = [];
      final logs = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        logs.add({'id': doc.id, ...data});
        final installerName =
            data['installer_name'] ?? tr('Unknown', 'Desconocido');
        final installerRole = data['installer_role'] ?? '';
        final logDate = (data['log_date'] as Timestamp).toDate();
        final entries = List<Map<String, dynamic>>.from(
          data['time_entries'] ?? [],
        );

        double totalHours = 0;
        final List<String> sites = [];
        final List<String> areas = [];
        int offSite = 0;

        for (final entry in entries) {
          totalHours += (entry['hoursWorked'] ?? 0).toDouble();
          if (OffSiteBadge.isOffSite(entry)) offSite++;
          final siteName = entry['projectName'] as String? ?? '';
          final areaName = entry['areaName'] as String? ?? '';
          if (siteName.isNotEmpty && !sites.contains(siteName)) {
            sites.add(siteName);
          }
          if (areaName.isNotEmpty && !areas.contains(areaName)) {
            areas.add(areaName);
          }
        }

        rows.add({
          'offSite': offSite,
          'name': installerName,
          'role': installerRole,
          'date': logDate,
          'entries': entries.length,
          'hours': totalHours,
          'sites': sites.join(', '),
          'areas': areas.join(', '),
          'isDayComplete': data['is_day_complete'] ?? false,
        });
      }

      // Sort by date desc, then name
      rows.sort((a, b) {
        final dateCompare = (b['date'] as DateTime).compareTo(
          a['date'] as DateTime,
        );
        if (dateCompare != 0) return dateCompare;
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      if (mounted) {
        setState(() {
          _timesheetRows = rows;
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Error loading timesheets: $e',
                'Error al cargar las hojas de horas: $e',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black87,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadTimesheets();
    }
  }

  Future<void> _exportExcel(Rect? origin) async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('No data to export', 'No hay datos para exportar')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final bytes = buildTimecardWorkbook(
        logs: _logs,
        start: _startDate,
        end: _endDate,
      );
      if (bytes == null) throw 'Could not create the spreadsheet';

      final fileName =
          'Timecards_${DateFormat('yyyy-MM-dd').format(_startDate)}'
          '_to_${DateFormat('yyyy-MM-dd').format(_endDate)}.xlsx';
      await saveExportedFile(
        bytes,
        fileName,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        origin: origin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Export failed: $e', 'Error al exportar: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppStrings.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          tr('Timesheets', 'Hojas de horas'),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              onPressed: _isExporting
                  ? null
                  : () {
                      // Anchor for the iPad share sheet.
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      _exportExcel(
                        box == null
                            ? null
                            : box.localToGlobal(Offset.zero) & box.size,
                      );
                    },
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.black87,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.download, color: Colors.black87),
              tooltip: tr('Export timecards', 'Exportar hojas de horas'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range picker
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: GestureDetector(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.date_range,
                      size: 20,
                      color: Colors.black87,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${DateFormat('MMM d, yyyy', AppStrings.dateLocale).format(_startDate)} — ${DateFormat('MMM d, yyyy', AppStrings.dateLocale).format(_endDate)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.edit_calendar,
                      size: 18,
                      color: Colors.grey[500],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Summary row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildSummaryChip(
                  '${_timesheetRows.length}',
                  tr('records', 'registros'),
                  Icons.list_alt,
                ),
                const SizedBox(width: 10),
                _buildSummaryChip(
                  _totalHours(),
                  tr('hours', 'horas'),
                  Icons.schedule,
                ),
                const SizedBox(width: 10),
                _buildSummaryChip(
                  '${_uniqueWorkers()}',
                  tr('workers', 'trabajadores'),
                  Icons.people,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Table
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.black87),
                  )
                : _timesheetRows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(
                            'No timesheets for this period',
                            'No hay hojas de horas en este período',
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _timesheetRows.length,
                    itemBuilder: (context, index) {
                      final row = _timesheetRows[index];
                      return _buildTimesheetRow(row);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimesheetRow(Map<String, dynamic> row) {
    final date = row['date'] as DateTime;
    final hours = (row['hours'] as double).toStringAsFixed(1);
    final isDone = row['isDayComplete'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isDone ? Colors.green[50] : Colors.orange[50],
            child: Icon(
              isDone ? Icons.check_circle : Icons.schedule,
              color: isDone ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['name'] ?? tr('Unknown', 'Desconocido'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('EEE, MMM d', AppStrings.dateLocale).format(date)} • ${row['sites'] ?? ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((row['offSite'] as int? ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tr(
                            '${row['offSite']} off-site clock in/out',
                            '${row['offSite']} entrada/salida fuera de la obra',
                          ),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${hours}h',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                tr('${row['entries']} entries', '${row['entries']} registros'),
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _totalHours() {
    double total = 0;
    for (final row in _timesheetRows) {
      total += (row['hours'] as double?) ?? 0;
    }
    return total.toStringAsFixed(1);
  }

  int _uniqueWorkers() {
    return _timesheetRows.map((r) => r['name']).toSet().length;
  }
}
