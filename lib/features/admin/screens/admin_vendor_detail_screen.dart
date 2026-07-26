import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminVendorDetailScreen extends StatefulWidget {
  const AdminVendorDetailScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<AdminVendorDetailScreen> createState() =>
      _AdminVendorDetailScreenState();
}

class _AdminVendorDetailScreenState extends State<AdminVendorDetailScreen> {
  final _repo = AdminRepository();
  late Future<(Vendor, VendorOwner?)> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Vendor, VendorOwner?)> _load() async {
    final vendor = await _repo.fetchVendor(widget.vendorId);
    final owner = await _repo.fetchVendorOwner(vendor.ownerId);
    return (vendor, owner);
  }

  Future<void> _setStatus(String status, String done) async {
    setState(() => _busy = true);
    try {
      await _repo.setVendorStatus(widget.vendorId, status);
      if (!mounted) return;
      showSnack(context, done);
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, readableError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: FutureBuilder<(Vendor, VendorOwner?)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError || !snap.hasData) {
            return ErrorView(
              message: context.l10n.couldNotLoadThisVendor,
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final (vendor, owner) = snap.data!;
          return _Body(vendor: vendor, owner: owner);
        },
      ),
      bottomNavigationBar: FutureBuilder<(Vendor, VendorOwner?)>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return _ActionBar(
            vendor: snap.data!.$1,
            busy: _busy,
            onApprove: () => _setStatus('active', context.l10n.vendorApproved),
            onSuspend: () => _setStatus('suspended', context.l10n.vendorSuspended),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vendor, required this.owner});

  final Vendor vendor;
  final VendorOwner? owner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Cover with the store logo overlapping its bottom edge.
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              height: 176,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(url: vendor.coverUrl, fit: BoxFit.cover),
                  Positioned(
                    left: 16,
                    top: MediaQuery.of(context).padding.top + 8,
                    child: _CircleButton(
                      icon: Icons.chevron_left,
                      onTap: () => context.pop(),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 22,
              bottom: -34,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: AppColors.amberFill,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.canvas, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: vendor.logoUrl != null && vendor.logoUrl!.isNotEmpty
                    ? AppNetworkImage(url: vendor.logoUrl, width: 70, height: 70)
                    : const Icon(Icons.storefront,
                        color: AppColors.primary, size: 32),
              ),
            ),
          ],
        ),
        Transform.translate(
          offset: const Offset(0, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Space reserved for the logo overlapping the cover.
                    const SizedBox(width: 83),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vendor.name,
                                style: AppType.heading(21)),
                            if (vendor.addressText != null)
                              Text(vendor.addressText!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                    _StatusChip(vendor: vendor),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _stat(context.l10n.deliveryFee, formatMoney(vendor.deliveryFee)),
                    const SizedBox(width: 9),
                    _stat(context.l10n.minimumOrder, formatMoney(vendor.minOrderAmount)),
                    const SizedBox(width: 9),
                    _stat(context.l10n.prep, '${vendor.avgPrepMinutes} ${context.l10n.minShort}'),
                  ],
                ),
                const SizedBox(height: 18),
                _label(context.l10n.ownerAndContact),
                const SizedBox(height: 9),
                _Card(children: [
                  _row(context.l10n.owner, owner?.name ?? '—'),
                  _row(context.l10n.phoneNumber, owner?.phone ?? '—', mono: true),
                  _row(context.l10n.address, vendor.addressText ?? '—', last: true),
                ]),
                if (vendor.description != null &&
                    vendor.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _label(context.l10n.about),
                  const SizedBox(height: 9),
                  _Card(children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(vendor.description!,
                          style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: AppColors.textSecondary)),
                    ),
                  ]),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textFaint)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: AppType.mono(14)),
              ),
            ],
          ),
        ),
      );

  Widget _label(String text) => Text(text.toUpperCase(),
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.textFaint));

  Widget _row(String label, String value,
          {bool mono = false, bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.borderSoft)),
        ),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMuted))),
            Text(value,
                style: mono
                    ? AppType.mono(13.5)
                    : const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.ink),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    if (vendor.isPending) {
      return SoftBadge(
          label: context.l10n.pending,
          fill: AppColors.warmFill,
          ink: AppColors.primaryDark);
    }
    if (vendor.isSuspended) {
      return SoftBadge(
          label: context.l10n.suspended1,
          fill: Color(0xFFFBE7E4),
          ink: Color(0xFFC0392B));
    }
    return SoftBadge(
        label: context.l10n.active1, fill: AppColors.successFill, ink: AppColors.successInk);
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.vendor,
    required this.busy,
    required this.onApprove,
    required this.onSuspend,
  });

  final Vendor vendor;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onSuspend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      child: busy
          ? const SizedBox(
              height: 52,
              child: Center(child: CircularProgressIndicator()))
          : Row(
              children: [
                if (!vendor.isSuspended)
                  Expanded(
                    flex: vendor.isPending ? 2 : 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: const BorderSide(color: AppColors.border),
                          foregroundColor: AppColors.textMuted),
                      onPressed: onSuspend,
                      child: Text(vendor.isPending ? context.l10n.reject : context.l10n.suspend),
                    ),
                  ),
                if (!vendor.isApproved) ...[
                  if (!vendor.isSuspended) const SizedBox(width: 11),
                  Expanded(
                    flex: vendor.isPending ? 3 : 1,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          minimumSize: const Size.fromHeight(52)),
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded, size: 19),
                      label: Text(vendor.isPending
                          ? context.l10n.approveVendor
                          : context.l10n.reactivate),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
