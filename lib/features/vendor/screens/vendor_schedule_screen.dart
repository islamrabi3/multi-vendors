import 'package:flutter/material.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/common.dart';

import 'package:multi_vendor/core/utils/l10n_extension.dart';

class VendorScheduleScreen extends StatefulWidget {
  const VendorScheduleScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<VendorScheduleScreen> createState() => _VendorScheduleScreenState();
}

class _VendorScheduleScreenState extends State<VendorScheduleScreen> {
  final VendorAdminRepository _vendorRepo = VendorAdminRepository();
  List<Map<String, dynamic>> _schedules = [];
  bool _isLoading = true;

  String _getDayName(BuildContext context, int index) {
    switch (index) {
      case 0:
        return context.l10n.daySunday;
      case 1:
        return context.l10n.dayMonday;
      case 2:
        return context.l10n.dayTuesday;
      case 3:
        return context.l10n.dayWednesday;
      case 4:
        return context.l10n.dayThursday;
      case 5:
        return context.l10n.dayFriday;
      case 6:
        return context.l10n.daySaturday;
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);
    try {
      final data = await _vendorRepo.fetchSchedules(widget.vendorId);
      if (!mounted) return;
      setState(() => _schedules = data);
    } catch (e) {
      // A failed read used to leave the spinner up for good.
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The day whose switch is mid-write, so it cannot be toggled twice.
  int? _savingDay;

  Future<void> _setDayOpen(Map<String, dynamic> day, int index, bool isOpen) async {
    setState(() => _savingDay = index);
    try {
      await _vendorRepo.updateSchedule(
        widget.vendorId,
        index,
        day['open_time'] as String? ?? '09:00',
        day['close_time'] as String? ?? '23:00',
        !isOpen,
      );
      await _loadSchedules();
    } catch (e) {
      // Previously this threw into nothing: no message, no reload, and the
      // switch silently sprang back — which read as "it will not turn on".
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _savingDay = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.operatingHoursSchedule),
      ),
      body: _isLoading
          ? const LoadingView()
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16,
                  16 + MediaQuery.paddingOf(context).bottom),
              itemCount: 7,
              itemBuilder: (context, index) {
                final dayName = _getDayName(context, index);
                final match = _schedules.firstWhere(
                  (s) => s['day_of_week'] == index,
                  orElse: () => {
                    'day_of_week': index,
                    'open_time': '09:00',
                    'close_time': '23:00',
                    'is_closed': false,
                  },
                );

                final isClosed = match['is_closed'] as bool? ?? false;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: SwitchListTile(
                    title: Text(dayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      isClosed
                          ? context.l10n.closedStatus
                          : '${context.l10n.openStatus}: ${match['open_time']} - ${match['close_time']}',
                    ),
                    value: !isClosed,
                    onChanged: _savingDay != null
                        ? null
                        : (val) => _setDayOpen(match, index, val),
                  ),
                );
              },
            ),
    );
  }
}
