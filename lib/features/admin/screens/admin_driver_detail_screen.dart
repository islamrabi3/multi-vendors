import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/finance.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/dialer.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../auth/auth_cubit.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

/// One driver: what they owe, what they're owed, and their documents — the
/// view neither role had before this. The list screen could approve or
/// suspend a driver, but an admin trying to answer "how much cash are they
/// holding" or "what have we already settled with them" had nowhere to look.
class AdminDriverDetailScreen extends StatefulWidget {
  const AdminDriverDetailScreen({super.key, required this.driverId});

  final String driverId;

  @override
  State<AdminDriverDetailScreen> createState() =>
      _AdminDriverDetailScreenState();
}

class _AdminDriverDetailScreenState extends State<AdminDriverDetailScreen> {
  final _repo = AdminRepository();
  final _finance = FinanceRepository();

  DriverAccount? _driver;
  PartyBalance? _balance;
  List<Settlement> _settlements = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchDriver(widget.driverId),
        // No single-driver balance RPC exists — the list is small enough
        // that scanning it is what the settlements screen already does.
        _finance.driverBalances(),
        _finance.settlements(
          ownerType: LedgerOwner.driver,
          ownerId: widget.driverId,
          limit: 20,
        ),
      ]);
      if (!mounted) return;
      final balances = results[1] as List<PartyBalance>;
      setState(() {
        _driver = results[0] as DriverAccount;
        _balance = balances
            .where((b) => b.ownerId == widget.driverId)
            .firstOrNull;
        _settlements = results[2] as List<Settlement>;
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

  Future<void> _setStatus(String status) async {
    final l10n = context.l10n;
    String? reason;
    if (status == 'suspended') {
      final controller = TextEditingController();
      final confirmed = await showFormDialog<bool>(
        context: context,
        title: l10n.rejectSuspendDriver,
        icon: Icons.block_rounded,
        tone: AppDialogTone.danger,
        contentBuilder: (_) => TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.rejectionReasonHint),
        ),
        submitLabel: l10n.reject,
        cancelLabel: l10n.cancel,
        onSubmit: (_) async => true,
      );
      if (confirmed != true || !mounted) return;
      reason = controller.text.trim();
    }

    setState(() => _busy = true);
    try {
      await _repo.setDriverStatus(widget.driverId, status, reason: reason);
      if (!mounted) return;
      showSnack(
        context,
        status == 'active' ? l10n.driverApproved : l10n.driverSuspendedToast,
      );
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _viewDocument(String title, String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpace.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title, style: const TextStyle(fontSize: 15)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(child: AppNetworkImage(url: url)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);
    final body = _loading
        ? const _DriverDetailSkeleton()
        : _error != null
        ? ErrorView(message: _error!, onRetry: _load)
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
              ),
              children: _content(context),
            ),
          );

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/drivers',
        sections: adminManageWebSections(context),
        pageTitle: _driver?.name ?? l10n.driversTab,
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(_driver?.name ?? l10n.driversTab)),
      body: body,
    );
  }

  List<Widget> _content(BuildContext context) {
    final l10n = context.l10n;
    final driver = _driver!;
    final balance = _balance;
    final canApprove = context.watch<AuthCubit>().state.can('drivers.approve');

    return [
      _DriverHeader(driver: driver),
      if (balance != null) ...[
        const SizedBox(height: AppSpace.lg),
        FinanceHero(
          tone: balance.cashDue > 0
              ? FinanceHeroTone.warning
              : FinanceHeroTone.brand,
          eyebrow: balance.cashDue > 0 ? l10n.driverHolds : l10n.owedToYou,
          amount: formatMoney(
            balance.cashDue > 0 ? balance.cashDue : balance.payable,
          ),
        ),
        FinanceSection(
          title: l10n.summaryLabel,
          child: FinanceCard(
            children: [
              FinanceRow(
                icon: Icons.two_wheeler_rounded,
                label: l10n.totalEarned,
                value: formatMoney(balance.totalEarnings),
              ),
              FinanceRow(
                icon: Icons.payments_rounded,
                label: l10n.cashCollectedLabel,
                value: formatMoney(balance.cashCollected),
              ),
              FinanceRow(
                icon: Icons.account_balance_rounded,
                label: l10n.alreadySettled,
                value: formatMoney(balance.totalSettlements),
              ),
            ],
          ),
        ),
      ],
      if (_settlements.isNotEmpty)
        FinanceSection(
          title: l10n.settlementsTitle,
          child: FinanceCard(
            children: [
              for (final settlement in _settlements)
                SettlementTile(settlement: settlement, partyName: driver.name),
            ],
          ),
        ),
      FinanceSection(
        title: l10n.submittedDocuments,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpace.sm,
          mainAxisSpacing: AppSpace.sm,
          childAspectRatio: 1.4,
          children: [
            _doc(l10n.idFront, driver.idCardUrl),
            _doc(l10n.idBack, driver.idCardBackUrl),
            _doc(l10n.licenseFront, driver.licenseUrl),
            _doc(l10n.licenseBack, driver.licenseBackUrl),
          ],
        ),
      ),
      if (canApprove && !driver.isApproved) ...[
        const SizedBox(height: AppSpace.lg),
        FilledButton.icon(
          onPressed: _busy ? null : () => _setStatus('active'),
          icon: _busy
              ? const ButtonSpinner(size: 18)
              : const Icon(Icons.check_rounded),
          label: Text(l10n.approve),
        ),
      ],
      if (canApprove && !driver.isSuspended) ...[
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _setStatus('suspended'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.dangerInk,
            side: const BorderSide(color: AppColors.dangerInk),
          ),
          icon: const Icon(Icons.block_rounded),
          label: Text(l10n.rejectSuspendDriver),
        ),
      ],
    ];
  }

  Widget _doc(String title, String? url) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: url == null || url.isEmpty
          ? Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textFaint,
                ),
              ),
            )
          : InkWell(
              onTap: () => _viewDocument(title, url),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(url: url),
                  PositionedDirectional(
                    bottom: 4,
                    start: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadii.xs),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DriverHeader extends StatelessWidget {
  const _DriverHeader({required this.driver});

  final DriverAccount driver;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (fill, ink) = switch (driver.approvalStatus) {
      'active' => (AppColors.successFill, AppColors.successInk),
      'suspended' => (AppColors.dangerFill, AppColors.dangerInk),
      _ => (AppColors.amberFill, AppColors.amberInk),
    };
    final statusLabel = switch (driver.approvalStatus) {
      'active' => l10n.statusApproved,
      'suspended' => l10n.statusSuspended,
      _ => l10n.statusPending,
    };

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.warmFill,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.two_wheeler_rounded,
            color: AppColors.primary,
            size: 26,
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driver.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.heading(17),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsetsDirectional.only(end: 5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: driver.isOnline
                          ? AppColors.successInk
                          : AppColors.textFaint,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      [
                        driver.isOnline
                            ? l10n.youAreOnline
                            : l10n.youAreOffline,
                        if (driver.vehicleType != null) driver.vehicleType!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SoftBadge(label: statusLabel, fill: fill, ink: ink),
            if (driver.phone != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => callPhone(context, driver.phone),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.call_rounded,
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      driver.phone!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _DriverDetailSkeleton extends StatelessWidget {
  const _DriverDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(
            children: const [
              Skeleton.circle(size: 52),
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton.line(widthFactor: 0.5, height: 16),
                    SizedBox(height: 6),
                    Skeleton.line(widthFactor: 0.35, height: 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          const Skeleton.box(height: 120, radius: AppRadii.xl),
          const SizedBox(height: AppSpace.lg),
          const Skeleton.box(height: 160, radius: AppRadii.lg),
        ],
      ),
    );
  }
}
