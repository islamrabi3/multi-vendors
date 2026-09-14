import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/core/utils/time_format.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor_schedule.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';

/// The store's weekly opening hours.
///
/// Each day is one row: its hours at a glance, a switch to close it, and a
/// tap to change the times — with "apply to every day" in the same editor,
/// because most shops keep one timetable all week and setting it seven times
/// is where mistakes come from.
class VendorScheduleScreen extends StatefulWidget {
  const VendorScheduleScreen({
    super.key,
    required this.vendorId,
    this.embedded = false,
  });

  final String vendorId;
  final bool embedded;

  @override
  State<VendorScheduleScreen> createState() => _VendorScheduleScreenState();
}

/// Saturday first: the working week in Egypt starts there, and the store
/// owner reads their week in that order.
const _weekOrder = [6, 0, 1, 2, 3, 4, 5];

class _VendorScheduleScreenState extends State<VendorScheduleScreen> {
  final _repository = VendorAdminRepository();

  List<Map<String, dynamic>> _schedules = const [];
  bool _loading = true;
  String? _error;

  /// Days mid-write, so they cannot be edited twice at once.
  final Set<int> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dayName(int index) => switch (index) {
    0 => context.l10n.daySunday,
    1 => context.l10n.dayMonday,
    2 => context.l10n.dayTuesday,
    3 => context.l10n.dayWednesday,
    4 => context.l10n.dayThursday,
    5 => context.l10n.dayFriday,
    _ => context.l10n.daySaturday,
  };

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repository.fetchSchedules(widget.vendorId);
      if (!mounted) return;
      setState(() {
        _schedules = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorText(context, error);
        _loading = false;
      });
    }
  }

  _Day _dayFor(int index) {
    final row = _schedules.firstWhere(
      (s) => s['day_of_week'] == index,
      orElse: () => const {},
    );
    return _Day(
      index: index,
      open: _hhmm(row['open_time'] as String? ?? '09:00'),
      close: _hhmm(row['close_time'] as String? ?? '23:00'),
      closed: row['is_closed'] as bool? ?? false,
    );
  }

  /// The column may come back as `09:00:00`; the app writes and compares
  /// `HH:MM`.
  static String _hhmm(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return value;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  Future<void> _write(List<_Day> days) async {
    setState(() => _saving.addAll(days.map((d) => d.index)));
    try {
      for (final day in days) {
        await _repository.updateSchedule(
          widget.vendorId,
          day.index,
          day.open,
          day.close,
          day.closed,
        );
      }
      await _load(quiet: true);
      if (mounted) showSnack(context, context.l10n.saved);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving.removeAll(days.map((d) => d.index)));
    }
  }

  Future<void> _edit(_Day day) async {
    final l10n = context.l10n;
    var open = day.open;
    var close = day.close;
    var closed = day.closed;
    var applyToAll = false;

    Future<String?> pick(String current) async {
      final parts = current.split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.tryParse(parts.first) ?? 9,
          minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
        ),
      );
      if (picked == null) return null;
      return '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    }

    await showFormSheet<bool>(
      context: context,
      title: _dayName(day.index),
      icon: Icons.schedule_rounded,
      contentBuilder: (rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              closed ? l10n.closed : l10n.openThisDay,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            value: !closed,
            onChanged: (v) {
              closed = !v;
              rebuild();
            },
          ),
          if (!closed) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: l10n.opensAt,
                    value: open,
                    onTap: () async {
                      final v = await pick(open);
                      if (v == null) return;
                      open = v;
                      rebuild();
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: AppColors.textFaint,
                  ),
                ),
                Expanded(
                  child: _TimeField(
                    label: l10n.closesAt,
                    value: close,
                    onTap: () async {
                      final v = await pick(close);
                      if (v == null) return;
                      close = v;
                      rebuild();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                avatar: const Icon(Icons.all_inclusive_rounded, size: 16),
                label: Text(l10n.openAllDay),
                onPressed: () {
                  open = '00:00';
                  close = '00:00';
                  rebuild();
                },
              ),
            ),
            if (open != close && _crossesMidnight(open, close))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  l10n.closesNextDay,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.amberInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          const Divider(height: AppSpace.xl),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.applyToAllDays),
            value: applyToAll,
            onChanged: (v) {
              applyToAll = v ?? false;
              rebuild();
            },
          ),
        ],
      ),
      submitLabel: l10n.save,
      cancelLabel: l10n.cancel,
      onSubmit: (_) async {
        final indexes = applyToAll ? _weekOrder : [day.index];
        await _write([
          for (final i in indexes)
            _Day(index: i, open: open, close: close, closed: closed),
        ]);
        return true;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (_error != null) {
      body = ErrorView(message: _error!, onRetry: _load);
    } else {
      final today = dayOfWeekIndex(DateTime.now());
      final days = [for (final i in _weekOrder) _dayFor(i)];
      body = LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 820 ? 2 : 1;
          final cards = [
            for (final day in days)
              _DayRow(
                name: _dayName(day.index),
                day: day,
                isToday: day.index == today,
                saving: _saving.contains(day.index),
                onTap: _saving.isEmpty ? () => _edit(day) : null,
                onToggle: _saving.isEmpty
                    ? (open) => _write([day.copyWith(closed: !open)])
                    : null,
              ),
          ];
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TodayCard(day: _dayFor(today)),
                        const SizedBox(height: AppSpace.md),
                        Text(
                          l10n.hoursCloseTheStoreNotice,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        if (columns == 1)
                          ...cards
                        else
                          Wrap(
                            spacing: AppSpace.md,
                            children: [
                              for (final card in cards)
                                SizedBox(
                                  width:
                                      ((constraints.maxWidth -
                                                  AppSpace.gutter * 2)
                                              .clamp(0.0, 1000.0) -
                                          AppSpace.md) /
                                      2,
                                  child: card,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(l10n.operatingHoursSchedule)),
      body: body,
    );
  }
}

bool _crossesMidnight(String open, String close) {
  final window = VendorSchedule(
    id: '',
    vendorId: '',
    dayOfWeek: 0,
    openTime: open,
    closeTime: close,
    isClosed: false,
  );
  // Midday sits inside every ordinary window and outside every overnight one.
  return !window.containsTime(DateTime(2026, 1, 1, 12));
}

class _Day {
  const _Day({
    required this.index,
    required this.open,
    required this.close,
    required this.closed,
  });

  final int index;
  final String open;
  final String close;
  final bool closed;

  bool get allDay => open == close;

  _Day copyWith({bool? closed}) => _Day(
    index: index,
    open: open,
    close: close,
    closed: closed ?? this.closed,
  );
}

String _rangeText(BuildContext context, _Day day) {
  final l10n = context.l10n;
  if (day.closed) return l10n.closed;
  if (day.allDay) return l10n.openAllDay;
  return '${formatClockText(context, day.open)} – '
      '${formatClockText(context, day.close)}';
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day});

  final _Day day;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final open = !day.closed;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: open
              ? const [AppColors.primaryLight, AppColors.primaryDark]
              : const [AppColors.textMuted, AppColors.textSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              open ? Icons.schedule_rounded : Icons.event_busy_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.todayHours,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _rangeText(context, day),
                  style: AppType.display(20, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.name,
    required this.day,
    required this.isToday,
    required this.saving,
    required this.onTap,
    required this.onToggle,
  });

  final String name;
  final _Day day;
  final bool isToday;
  final bool saving;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: day.closed ? AppColors.neutralFill : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: isToday ? AppColors.primary : AppColors.border,
                width: isToday ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.heading(15),
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 8),
                            SoftBadge(
                              label: l10n.today,
                              fill: AppColors.warmFill,
                              ink: AppColors.primaryDark,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            day.closed
                                ? Icons.block_rounded
                                : Icons.access_time_rounded,
                            size: 14,
                            color: day.closed
                                ? AppColors.textFaint
                                : AppColors.successInk,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _rangeText(context, day),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: day.closed
                                    ? AppColors.textMuted
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (saving)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  Switch(
                    value: !day.closed,
                    onChanged: onToggle,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.success,
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textFaint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(formatClockText(context, value), style: AppType.heading(16)),
          ],
        ),
      ),
    );
  }
}
