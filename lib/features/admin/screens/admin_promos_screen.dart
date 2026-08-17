import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/coupon.dart';
import '../../../core/repositories/coupons_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import '../admin_coupons_cubit.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

class AdminPromosScreen extends StatelessWidget {
  const AdminPromosScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    // Only coupons live here now. Banners moved to the Ads screen, which
    // owns the same `banners` table but with the placement, schedule,
    // audience and counters this screen never had — two editors for one
    // table meant whichever you happened to open decided what you could set.
    return BlocProvider(
      create: (_) => AdminCouponsCubit(CouponsRepository()),
      child: _PromosView(embedded: embedded),
    );
  }
}

class _PromosView extends StatelessWidget {
  const _PromosView({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final body = BlocListener<AdminCouponsCubit, AdminCouponsState>(
      listenWhen: (p, c) => p.error != c.error && c.error != null,
      listener: (context, s) => showFailure(context, s.error!),
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<AdminCouponsCubit>().load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            _SectionLabel('Coupons'),
            SizedBox(height: 10),
            _CouponsSection(),
          ],
        ),
      ),
    );

    final header = Row(
      children: [
        Text(l10n.promos, style: AppType.display(26)),
        const Spacer(),
        _NewButton(),
      ],
    );

    if (embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: AppSpace.lg),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/promos',
        sections: adminManageWebSections(context),
        pageTitle: l10n.promos,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: AppSpace.lg),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.promos),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 16, 10),
              child: header,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// One thing to create here now that banners live on the Ads screen, so this
/// is a button rather than the two-item menu it used to open.
class _NewButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showCouponForm(context, context.read<AdminCouponsCubit>()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.primaryGlow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text(
              context.l10n.newText,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    // Counts coupons, not banners. The old version read the *offers* cubit
    // even under the Coupons heading, which was left over from when this
    // screen owned both.
    final active = context.select(
      (AdminCouponsCubit c) => c.state.coupons.where((o) => o.isLive).length,
    );
    return Row(
      children: [
        Text(
          context.l10n.coupons.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.textFaint,
          ),
        ),
        Text(
          '  ·  $active ${context.l10n.active}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textFaint,
          ),
        ),
      ],
    );
  }
}

class _CouponsSection extends StatelessWidget {
  const _CouponsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminCouponsCubit, AdminCouponsState>(
      builder: (context, state) {
        if (state.loading) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingView(),
          );
        }
        if (state.coupons.isEmpty) {
          return _emptyCard(context.l10n.noCouponsYetTapNew);
        }
        final cubit = context.read<AdminCouponsCubit>();
        if (AppBreakpoints.isWebWide(context)) {
          return _CouponTable(coupons: state.coupons, cubit: cubit);
        }
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < state.coupons.length; i++)
                _CouponRow(
                  coupon: state.coupons[i],
                  cubit: cubit,
                  last: i == state.coupons.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Web/wide: coupons as a real table.
///
/// A coupon is a record with the same six facts every time — code, what it
/// takes off, who it is for, how much of it is gone, when it dies, whether it
/// is on. Stacked cards make you re-find each of those in a different place
/// per row; columns put them where the eye already is.
class _CouponTable extends StatelessWidget {
  const _CouponTable({required this.coupons, required this.cubit});

  final List<Coupon> coupons;
  final AdminCouponsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final columns = [
      WebTableColumn(label: l10n.couponCode, flex: 2),
      WebTableColumn(label: l10n.discount, flex: 2),
      WebTableColumn(label: l10n.used, width: 120),
      WebTableColumn(label: l10n.expiresLabel, width: 120),
      WebTableColumn(label: l10n.statusLabel, width: 104),
    ];

    return WebTable(
      columns: columns,
      trailingWidth: 96,
      rows: [
        for (final coupon in coupons)
          WebTableRow.aligned(
            columns: columns,
            trailingWidth: 96,
            cells: [
              Text(
                coupon.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.mono(13, weight: FontWeight.w800),
              ),
              Text(
                _discount(context, coupon),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
              Text(
                '${coupon.usedCount} / ${coupon.usageLimit ?? '∞'}',
                style: AppType.mono(12.5, color: AppColors.textSecondary),
              ),
              Text(
                coupon.expiresAt == null
                    ? '—'
                    : DateFormat('MMM d, y').format(coupon.expiresAt!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
              _CouponStatus(coupon: coupon),
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Expired or exhausted codes cannot be switched back on by
                // flipping a toggle — the date or the cap is what stopped
                // them, so the switch would lie.
                SizedBox(
                  width: 44,
                  child: Transform.scale(
                    scale: 0.78,
                    child: Switch(
                      value: coupon.isActive,
                      onChanged: coupon.isExpired || coupon.isExhausted
                          ? null
                          : (_) => cubit.toggleActive(coupon),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.delete,
                  onPressed: () => _confirmDeleteCoupon(context, coupon, cubit),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.dangerInk,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _discount(BuildContext context, Coupon coupon) {
    final l10n = context.l10n;
    if (coupon.isFreeDelivery) return l10n.couponTypeFreeDelivery;
    final value = coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}%'
        : formatMoney(coupon.value);
    final cap = coupon.maxDiscount != null
        ? ' · ${l10n.max} ${formatMoney(coupon.maxDiscount!)}'
        : '';
    final min = coupon.minOrderAmount > 0
        ? ' · ${l10n.min} ${formatMoney(coupon.minOrderAmount)}'
        : '';
    return '$value$cap$min';
  }
}

/// Why a coupon is or is not working, in one badge.
class _CouponStatus extends StatelessWidget {
  const _CouponStatus({required this.coupon});

  final Coupon coupon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Order matters: a code can be expired *and* switched off, and the
    // reason it stopped is more useful than the switch position.
    final (label, fill, ink) = coupon.isExpired
        ? (l10n.expired, AppColors.dangerFill, AppColors.dangerInk)
        : coupon.isExhausted
        ? (l10n.couponExhausted, AppColors.dangerFill, AppColors.dangerInk)
        : coupon.isScheduled
        ? (l10n.couponScheduled, AppColors.amberFill, AppColors.amberInk)
        : coupon.isActive
        ? (l10n.active, AppColors.successFill, AppColors.successInk)
        : (l10n.pausedLabel, AppColors.neutralFill, AppColors.textMuted);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SoftBadge(label: label, fill: fill, ink: ink),
    );
  }
}

class _CouponRow extends StatelessWidget {
  const _CouponRow({
    required this.coupon,
    required this.cubit,
    required this.last,
  });

  final Coupon coupon;
  final AdminCouponsCubit cubit;
  final bool last;

  String _summary(BuildContext context) {
    final l10n = context.l10n;
    final v = coupon.isFreeDelivery
        ? l10n.couponTypeFreeDelivery
        : coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}%'
        : formatMoney(coupon.value);
    final cap = coupon.maxDiscount != null
        ? ' · ${l10n.max} ${formatMoney(coupon.maxDiscount!)}'
        : '';
    final min = coupon.minOrderAmount > 0
        ? ' · ${l10n.min} ${formatMoney(coupon.minOrderAmount)}'
        : '';
    // The reason it is not working, when it is not working — an admin looking
    // at a list of codes needs that before anything else.
    if (coupon.isExpired) return '$v · ${l10n.expired}';
    if (coupon.isScheduled) return '$v · ${l10n.couponScheduled}';
    if (coupon.isExhausted) return '$v · ${l10n.couponExhausted}';
    return coupon.isFreeDelivery ? '$v$min' : '$v ${l10n.off}$cap$min';
  }

  /// Both limits on one line: how much of the campaign is gone, and how many
  /// times any one customer may take it.
  String _usage(BuildContext context) {
    final l10n = context.l10n;
    final limit = coupon.usageLimit == null ? '∞' : '${coupon.usageLimit}';
    final perUser = switch (coupon.perUserLimit) {
      null => l10n.perCustomerUnlimited,
      1 => l10n.oncePerCustomer,
      final n => l10n.usesPerCustomer(n),
    };
    return [
      '${coupon.usedCount} / $limit ${l10n.used}',
      perUser,
      if (coupon.firstOrderOnly) l10n.couponFirstOrderOnly,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final dim = !coupon.isLive;
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: dim ? AppColors.neutralFill : AppColors.amberFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            coupon.code,
            style: AppType.mono(
              13,
              color: dim ? AppColors.textFaint : AppColors.ink,
            ),
          ),
        ),
        title: Text(
          _summary(context),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: dim ? AppColors.textMuted : AppColors.ink,
          ),
        ),
        subtitle: Text(
          _usage(context),
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: coupon.isActive,
              activeThumbColor: AppColors.primary,
              onChanged: coupon.isExpired || coupon.isExhausted
                  ? null
                  : (_) => cubit.toggleActive(coupon),
            ),
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: () => _confirmDelete(context),
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.dangerInk,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) =>
      _confirmDeleteCoupon(context, coupon, cubit);
}

/// Shared by the mobile row and the desktop table, so the two cannot drift
/// into asking for confirmation differently.
Future<void> _confirmDeleteCoupon(
  BuildContext context,
  Coupon coupon,
  AdminCouponsCubit cubit,
) async {
  final confirmed = await AppDialogs.showConfirmDialog(
    context: context,
    title: context.l10n.deleteCoupon,
    message: '"${coupon.code}" ${context.l10n.willBeRemoved}',
    confirmText: context.l10n.delete,
    cancelText: context.l10n.cancel,
    isDestructive: true,
    icon: Icons.confirmation_number_outlined,
  );
  if (confirmed == true) cubit.delete(coupon);
}

Widget _emptyCard(String message) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(22),
  decoration: BoxDecoration(
    color: AppColors.surface,
    border: Border.all(color: AppColors.border),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Text(
    message,
    textAlign: TextAlign.center,
    style: const TextStyle(color: AppColors.textMuted),
  ),
);

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

void _showCouponForm(BuildContext context, AdminCouponsCubit cubit) {
  showAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const _CouponForm()),
  );
}

class _CouponForm extends StatefulWidget {
  const _CouponForm();

  @override
  State<_CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends State<_CouponForm> {
  final _code = TextEditingController();
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _minOrder = TextEditingController();
  final _maxDiscount = TextEditingController();
  final _limit = TextEditingController();

  /// Defaults to one use per customer. That is what an admin almost always
  /// means by "promo code", and the old form had no way to say it at all —
  /// which is why a single code could be spent on every order.
  final _perUser = TextEditingController(text: '1');

  _CouponKind _kind = _CouponKind.percentage;
  DateTime? _startsAt;
  DateTime? _expiresAt;
  bool _firstOrderOnly = false;
  bool _isPublic = false;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _value.dispose();
    _minOrder.dispose();
    _maxDiscount.dispose();
    _limit.dispose();
    _perUser.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _startsAt : _expiresAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // End of day for an expiry: a code that dies at midnight-as-typed would
      // stop working the moment the admin picked today.
      if (start) {
        _startsAt = picked;
      } else {
        _expiresAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.newCoupon, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: l10n.codeEgEaty40),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: InputDecoration(hintText: l10n.couponTitleLabel),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_CouponKind>(
              segments: [
                ButtonSegment(
                  value: _CouponKind.percentage,
                  label: Text(l10n.percentage),
                ),
                ButtonSegment(
                  value: _CouponKind.fixed,
                  label: Text(l10n.fixedEgp),
                ),
                ButtonSegment(
                  value: _CouponKind.freeDelivery,
                  label: Text(l10n.couponTypeFreeDelivery),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            // Free delivery has no amount of its own: it is worth whatever the
            // store charges, resolved when the code is applied.
            if (_kind != _CouponKind.freeDelivery) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: _kind == _CouponKind.percentage
                      ? l10n.discountPercent
                      : l10n.discountAmountEgp,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _minOrder,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: l10n.minOrderOptional),
            ),
            if (_kind == _CouponKind.percentage) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _maxDiscount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: l10n.maxDiscountCapOptional,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _perUser,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.perCustomerLimit,
                      helperText: l10n.perCustomerUnlimited,
                      helperMaxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.totalUsageLimit,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: l10n.couponStartsAt,
                    value: _startsAt,
                    onTap: () => _pickDate(start: true),
                    onClear: () => setState(() => _startsAt = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateField(
                    label: l10n.couponExpiresAt,
                    value: _expiresAt,
                    onTap: () => _pickDate(start: false),
                    onClear: () => setState(() => _expiresAt = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _firstOrderOnly,
              onChanged: (v) => setState(() => _firstOrderOnly = v),
              title: Text(l10n.couponFirstOrderOnly),
              subtitle: Text(
                l10n.couponFirstOrderOnlyDesc,
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: Text(l10n.couponPublic),
              subtitle: Text(
                l10n.couponPublicDesc,
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.createCoupon),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final value = double.tryParse(_value.text.trim());
    final needsValue = _kind != _CouponKind.freeDelivery;
    if (code.isEmpty || (needsValue && (value == null || value <= 0))) {
      showSnack(context, context.l10n.enterACodeAndAValidDiscount, error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<AdminCouponsCubit>().create(
      code: code,
      discountType: _kind.wire,
      value: value ?? 0,
      minOrderAmount: double.tryParse(_minOrder.text.trim()) ?? 0,
      maxDiscount: _kind == _CouponKind.percentage
          ? double.tryParse(_maxDiscount.text.trim())
          : null,
      usageLimit: int.tryParse(_limit.text.trim()),
      // Blank means unlimited, which the server reads as a null column.
      perUserLimit: int.tryParse(_perUser.text.trim()),
      startsAt: _startsAt,
      expiresAt: _expiresAt,
      firstOrderOnly: _firstOrderOnly,
      isPublic: _isPublic,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      showSnack(context, context.l10n.couponCreated);
    } else {
      setState(() => _saving = false);
    }
  }
}

/// The three shapes a discount can take.
enum _CouponKind {
  percentage('percentage'),
  fixed('fixed'),
  freeDelivery('free_delivery');

  const _CouponKind(this.wire);

  final String wire;
}

/// A date the admin may set or leave empty — an unset start means "live now",
/// an unset expiry means "until switched off".
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: value == null
              ? const Icon(Icons.event_outlined, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                  tooltip: context.l10n.clearDate,
                ),
        ),
        child: Text(
          value == null
              ? context.l10n.notSet
              : DateFormat.yMMMd().format(value!),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
