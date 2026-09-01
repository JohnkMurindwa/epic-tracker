import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'dart:typed_data';

class ExcelImportDialog extends StatefulWidget {
  final String projectId;
  final String projectName;

  const ExcelImportDialog({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<ExcelImportDialog> createState() => _ExcelImportDialogState();
}

class _ExcelImportDialogState extends State<ExcelImportDialog> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isImporting = false;
  String? _fileName;

  // Parsed data: list of areas grouped by level
  final Map<String, List<_ParsedArea>> _levelGroups = {};
  // Track which areas are selected for import
  final Set<String> _selectedKeys = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.upload_file,
                    size: 24,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Import Areas from Spreadsheet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.projectName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: _levelGroups.isEmpty
                  ? _buildUploadSection()
                  : _buildSelectionList(),
            ),

            // Footer actions
            if (_levelGroups.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    // Select all / none
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedKeys.length == _allKeys.length) {
                            _selectedKeys.clear();
                          } else {
                            _selectedKeys.addAll(_allKeys);
                          }
                        });
                      },
                      child: Text(
                        _selectedKeys.length == _allKeys.length
                            ? 'Deselect All'
                            : 'Select All',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_selectedKeys.length} areas selected',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectedKeys.isEmpty || _isImporting
                          ? null
                          : _importSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text('Import ${_selectedKeys.length} Areas'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'Upload your Daily Log spreadsheet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'The app will read the areas, levels, and crew days from your .xlsx file',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _pickAndParseFile,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_isLoading ? 'Reading...' : 'Choose File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Text(
              _fileName!,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectionList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shrinkWrap: true,
      children: _levelGroups.entries.map((levelEntry) {
        final levelName = levelEntry.key;
        final areas = levelEntry.value;
        final levelSelected = areas
            .where((a) => _selectedKeys.contains(a.key))
            .length;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              leading: Icon(Icons.layers, size: 18, color: Colors.grey[600]),
              title: Text(
                levelName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '$levelSelected of ${areas.length} selected',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              children: areas.map((area) {
                final isSelected = _selectedKeys.contains(area.key);
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedKeys.remove(area.key);
                      } else {
                        _selectedKeys.add(area.key);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black87 : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 20,
                          color: isSelected ? Colors.white : Colors.grey[400],
                        ),
                        const SizedBox(width: 10),
                        // Area code
                        Container(
                          width: 36,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            area.code,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white70
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Area name
                        Expanded(
                          child: Text(
                            area.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        // Crew days
                        if (area.crewDays > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${area.crewDays.toStringAsFixed(1)} days',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }).toList(),
    );
  }

  Set<String> get _allKeys {
    final keys = <String>{};
    for (final areas in _levelGroups.values) {
      for (final a in areas) {
        keys.add(a.key);
      }
    }
    return keys;
  }

  Future<void> _pickAndParseFile() async {
    setState(() => _isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.first;
      setState(() => _fileName = file.name);

      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Parse the Excel file
      final excelFile = excel_lib.Excel.decodeBytes(bytes);
      final sheet = excelFile.tables.values.first; // First sheet

      _levelGroups.clear();
      _selectedKeys.clear();

      String currentLevel = 'General';

      for (final row in sheet.rows) {
        if (row.isEmpty) continue;

        // Get cell values
        final col0 = row.isNotEmpty
            ? row[0]?.value?.toString().trim() ?? ''
            : '';
        final col1 = row.length > 1
            ? row[1]?.value?.toString().trim() ?? ''
            : '';
        final col2 = row.length > 2
            ? row[2]?.value?.toString().trim() ?? ''
            : '';
        // Check for level headers like ** BASEMENT **
        if (col1.startsWith('**') && col1.endsWith('**')) {
          currentLevel = col1.replaceAll('*', '').trim();
          continue;
        }

        // Check if this is an area row (starts with A followed by digits, or CO followed by digits)
        final isArea =
            RegExp(r'^A\d+$').hasMatch(col0) ||
            RegExp(r'^CO\d+').hasMatch(col0);
        if (!isArea) continue;

        // Parse crew days — could be in col2 or empty
        double crewDays = 0;
        if (col2.isNotEmpty) {
          crewDays = double.tryParse(col2) ?? 0;
        }

        // Get the area description from col1
        String areaName = col1;
        if (areaName.isEmpty) continue;

        // Clean up the name — take just the first line (before any newlines or details)
        if (areaName.contains(':')) {
          areaName = areaName.split(':').first.trim();
        }

        final area = _ParsedArea(
          code: col0,
          name: areaName,
          crewDays: crewDays,
          level: currentLevel,
        );

        _levelGroups.putIfAbsent(currentLevel, () => []).add(area);

        // Pre-select areas with crew days (likely tile labor)
        if (crewDays > 0) {
          _selectedKeys.add(area.key);
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importSelected() async {
    setState(() => _isImporting = true);

    try {
      int imported = 0;

      for (final levelEntry in _levelGroups.entries) {
        final levelName = levelEntry.key;
        final areas = levelEntry.value;

        for (final area in areas) {
          if (!_selectedKeys.contains(area.key)) continue;

          await _db.collection('areas').add({
            'projectId': widget.projectId,
            'projectName': widget.projectName,
            'levelName': levelName,
            'name': '${area.code} — ${area.name}',
            'totalCrewDays': area.crewDays,
            'consumedCrewDays': 0.0,
            'assignedPeople': <String>[],
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
          });

          imported++;
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported $imported areas into ${widget.projectName}',
            ),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } catch (e) {
      setState(() => _isImporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ParsedArea {
  final String code;
  final String name;
  final double crewDays;
  final String level;

  _ParsedArea({
    required this.code,
    required this.name,
    required this.crewDays,
    required this.level,
  });

  String get key => '$level-$code';
}
