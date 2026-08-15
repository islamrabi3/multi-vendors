import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor_schedule.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/common.dart';

/// The store's weekly opening hours.
///
/// The screen used to be a row of switches: a day could be opened or closed
/// but its hours were fixed at 09:00–23:00 for every store, because nothing
/// ever called the times `updateSchedule` already accepted. A store that opens
/// at 13:00 had no way to say so, and since the hours now actually close the
/// store, that was the difference between trading and not.
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

class _VendorScheduleScreenState extends State<VendorScheduleScreen> {
  final _repository = VendorAdminRepository();

  List<Map<String, dynamic>> _schedules = const [];
  bool _loading = true;
  String? _error;

  /// The day mid-write, so it cannot be edited twice at once.
  int? _savingDay;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.fetchSchedules(widget.vendorId);
      if (!mounted) return;
      setState(() {
        _schedules = data;
        _loading = false;
      });
    } catch (error) {
      // A failed read used to leave the spinner up for good.
      if (!mounted) return;
      setState(() {
        _error = errorText(context, error);
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _dayFor(int index) => _schedules.firstWhere(
    (s) => s['day_of_week'] == index,
    orElse: () => {
      'day_of_week': index,
      'open_time': '09:00',
      'close_time': '23:00',
      'is_closed': false,
    },
  );

  Future<void> _save(
    int index, {
    String? openTime,
    String? closeTime,
    bool? isClosed,
  }) async {
    final day = _dayFor(index);
    setState(() => _savingDay = index);
    try {
      await _repository.updateSchedule(
        widget.vendorId,
        index,
        openTime ?? day['open_time'] as String? ?? '09:00',
        closeTime ?? day['close_time'] as String? ?? '23:00',
        isClosed ?? day['is_closed'] as bool? ?? false,
      );
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _savingDay = null);
    }
  }

  /// `HH:MM` in, `HH:MM` out — the column is text and the server parses it as
  /// a time, so the padding is not cosmetic.
  Future<void> _pickTime(int index, {required bool isOpening}) async {
    final day = _dayFor(index);
    final raw =
        (isOpening ? day['open_time'] : day['close_time']) as String? ??
        (isOpening ? '09:00' : '23:00');
    final parts = raw.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      ),
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await _save(
      index,
      openTime: isOpening ? value : null,
      closeTime: isOpening ? null : value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(l10n.operatingHoursSchedule)),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.md,
                  AppSpace.gutter,
                  AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: Text(
                      l10n.hoursCloseTheStoreNotice,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  for (var index = 0; index < 7; index++)
                    _DayCard(
                      name: _dayName(index),
                      day: _dayFor(index),
                      busy: _savingDay == index,
                      disabled: _savingDay != null && _savingDay != index,
                      onToggle: (open) => _save(index, isClosed: !open),
                      onPickOpen: () => _pickTime(index, isOpening: true),
                      onPickClose: () => _pickTime(index, isOpening: false),
                    ),
                ],
              ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.name,
    required this.day,
    required this.busy,
    required this.disabled,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
  });

  final String name;
  final Map<String, dynamic> day;
  final bool busy;
  final bool disabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final closed = day['is_closed'] as bool? ?? false;
    final open = day['open_time'] as String? ?? '09:00';
    final close = day['close_time'] as String? ?? '23:00';
    // Equal times mean the store trades round the clock, which is worth saying
    // rather than rendering as an empty-looking "22:00 - 22:00".
    final allDay = open == close;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(15),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(value: !closed, onChanged: disabled ? null : onToggle),
            ],
          ),
          if (!closed) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: l10n.opensAt,
                    value: open,
                    onTap: disabled || busy ? null : onPickOpen,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: _TimeButton(
                    label: l10n.closesAt,
                    value: close,
                    onTap: disabled || busy ? null : onPickClose,
                  ),
                ),
              ],
            ),
            if (allDay)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  l10n.openAllDay,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.successInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (_crossesMidnight(open, close))
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text(
                  // A 18:00–02:00 shift is legitimate and easy to mistake for a
                  // typo, so the screen confirms it was understood.
                  l10n.closesNextDay,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.amberInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  bool _crossesMidnight(String open, String close) {
    final o = VendorSchedule(
      id: '',
      vendorId: '',
      dayOfWeek: 0,
      openTime: open,
      closeTime: close,
      isClosed: false,
    );
    // Midday sits inside every ordinary window and outside every overnight
    // one, which is the cheapest way to tell them apart without re-parsing.
    return !o.containsTime(DateTime(2026, 1, 1, 12));
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.mono(14, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
