import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EpicWeekHeader extends StatefulWidget {
  final String userName;
  final String? userRole;
  final ValueChanged<DateTime>? onDaySelected;
  final VoidCallback? onAvatarTap;

  const EpicWeekHeader({
    super.key,
    required this.userName,
    this.userRole,
    this.onDaySelected,
    this.onAvatarTap,
  });

  @override
  State<EpicWeekHeader> createState() => _EpicWeekHeaderState();
}

class _EpicWeekHeaderState extends State<EpicWeekHeader> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  static const Color _darkText = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _weekStart = _getWeekStart(_selectedDay);
  }

  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${DateFormat('MMM d, yyyy').format(_weekStart)} – ${DateFormat('MMM d, yyyy').format(weekEnd)}';
    final today = DateTime.now();
    final isCurrentWeek = _weekStart.isAtSameMomentAs(_getWeekStart(today));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Row 1: Avatar + Centered Title + Avatar ─────
              Row(
                children: [
                  // Invisible spacer same size as avatar for centering
                  const SizedBox(width: 44),
                  Expanded(
                    child: Center(
                      child: const Text(
                        'Epic Installation',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _darkText,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onAvatarTap,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black87.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(widget.userName),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ─── Row 2: Week range + arrows ────────────
              Row(
                children: [
                  Text(
                    weekLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _weekStart = _weekStart.subtract(
                          const Duration(days: 7),
                        );
                        _selectedDay = _weekStart;
                      });
                      widget.onDaySelected?.call(_selectedDay);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_left,
                        color: Colors.black87,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: isCurrentWeek
                        ? null
                        : () {
                            setState(() {
                              _weekStart = _weekStart.add(
                                const Duration(days: 7),
                              );
                              // Don't go past current week
                              final currentWeekStart = _getWeekStart(today);
                              if (_weekStart.isAfter(currentWeekStart)) {
                                _weekStart = currentWeekStart;
                              }
                              _selectedDay = _weekStart;
                            });
                            widget.onDaySelected?.call(_selectedDay);
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.chevron_right,
                        color: isCurrentWeek
                            ? Colors.grey[300]
                            : Colors.black87,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ─── Row 3: Day circles ────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final day = _weekStart.add(Duration(days: index));
                  final isSelected =
                      day.year == _selectedDay.year &&
                      day.month == _selectedDay.month &&
                      day.day == _selectedDay.day;
                  final isToday =
                      day.year == today.year &&
                      day.month == today.month &&
                      day.day == today.day;
                  final dayLabel = DateFormat('E').format(day).substring(0, 3);

                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedDay = day);
                      widget.onDaySelected?.call(day);
                    },
                    child: Column(
                      children: [
                        Text(
                          dayLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.black87
                                : Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Colors.black87
                                : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.black87
                                  : isToday
                                  ? Colors.black87
                                  : Colors.black87.withValues(alpha: 0.35),
                              width: isSelected || isToday ? 2 : 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
