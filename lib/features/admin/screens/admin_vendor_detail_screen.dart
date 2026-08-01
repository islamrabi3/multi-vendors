import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/location_picker.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Route entry for the phone flow: the vendor review view on its own page.
class AdminVendorDetailScreen extends StatelessWidget {
  const AdminVendorDetailScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  Widget build(BuildContext context) =>
      AdminVendorDetailView(vendorId: vendorId);
}

/// The store review view. Embedded (`embedded: true`) it drops the back button
/// and its own Scaffold, and reports approvals through [onStatusChanged]
/// instead of popping, so it can live in a wide master–detail pane.
class AdminVendorDetailView extends StatefulWidget {
  const AdminVendorDetailView({
    super.key,
    required this.vendorId,
    this.embedded = false,
    this.onStatusChanged,
  });

  final String vendorId;
  final bool embedded;
  final VoidCallback? onStatusChanged;

  @override
  State<AdminVendorDetailView> createState() => _AdminVendorDetailViewState();
}

class _AdminVendorDetailViewState extends State<AdminVendorDetailView> {
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
      widget.onStatusChanged?.call();
      if (widget.embedded) {
        setState(() {
          _busy = false;
          _future = _load();
        });
      } else {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, e);
      }
    }
  }

  /// Drops the store's map pin on the owner's behalf.
  Future<void> _setLocation(Vendor vendor) async {
    final picked = await showLocationPicker(
      context,
      initial: vendor.lat == null || vendor.lng == null
          ? null
          : LatLng(vendor.lat!, vendor.lng!),
      title: context.l10n.storeLocationOnMap,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await VendorAdminRepository().updateVendor(vendor.id, {
        'lat': picked.point.latitude,
        'lng': picked.point.longitude,
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _future = _load();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, e);
      }
    }
  }

  /// Promotion onto the customer home's recommended rail. Only offered for an
  /// approved store — promoting a pending one would advertise a store the
  /// customer cannot order from.
  Future<void> _setRecommended(bool recommended, {int rank = 0}) async {
    setState(() => _busy = true);
    try {
      await _repo.setVendorRecommended(widget.vendorId, recommended,
          rank: rank);
      if (!mounted) return;
      widget.onStatusChanged?.call();
      setState(() {
        _busy = false;
        _future = _load();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, e);
      }
    }
  }

  Widget _content() => FutureBuilder<(Vendor, VendorOwner?)>(
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
          return Column(
            children: [
              Expanded(
                child: _Body(
                  vendor: vendor,
                  owner: owner,
                  showBack: !widget.embedded,
                ),
              ),
              // Stores onboarded before the map picker have no pin, so they
              // never surface in "nearby". The owner can fix it in their own
              // settings, but an operator should not have to chase them.
              if (vendor.lat == null || vendor.lng == null)
                Container(
                  margin: const EdgeInsets.fromLTRB(
                      AppSpace.gutter, 0, AppSpace.gutter, AppSpace.sm),
                  decoration: BoxDecoration(
                    color: AppColors.warmFill,
                    border: Border.all(color: AppColors.attentionBorder),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.add_location_alt_outlined,
                        color: AppColors.primary),
                    title: Text(context.l10n.storeLocationOnMap,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(context.l10n.pickOnMap,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                    onTap: _busy ? null : () => _setLocation(vendor),
                  ),
                ),
              if (vendor.isApproved)
                Container(
                  margin: const EdgeInsets.fromLTRB(
                      AppSpace.gutter, 0, AppSpace.gutter, AppSpace.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: vendor.isRecommended,
                        onChanged: _busy
                            ? null
                            : (v) => _setRecommended(v,
                                rank: vendor.recommendedRank),
                        secondary: Icon(Icons.auto_awesome,
                            color: vendor.isRecommended
                                ? AppColors.primary
                                : AppColors.textMuted),
                        title: Text(context.l10n.manageRecommended,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(context.l10n.recommended,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ),
                      // Rank decides the order of the rail on the customer
                      // home. Only meaningful once the store is promoted, so
                      // it stays hidden until then.
                      if (vendor.isRecommended)
                        ListTile(
                          dense: true,
                          leading: const SizedBox(width: 24),
                          title: Text(context.l10n.sortOrder,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: _busy || vendor.recommendedRank <= 0
                                    ? null
                                    : () => _setRecommended(true,
                                        rank: vendor.recommendedRank - 1),
                              ),
                              Text('${vendor.recommendedRank}',
                                  style: AppType.mono(15)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _busy
                                    ? null
                                    : () => _setRecommended(true,
                                        rank: vendor.recommendedRank + 1),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      );

  Widget _actionBar() => FutureBuilder<(Vendor, VendorOwner?)>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return _ActionBar(
            vendor: snap.data!.$1,
            busy: _busy,
            onApprove: () => _setStatus('active', context.l10n.vendorApproved),
            onSuspend: () =>
                _setStatus('suspended', context.l10n.vendorSuspended),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          Expanded(child: _content()),
          _actionBar(),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: _content(),
      bottomNavigationBar: _actionBar(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.vendor,
    required this.owner,
    this.showBack = true,
  });

  final Vendor vendor;
  final VendorOwner? owner;
  final bool showBack;

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
                  if (showBack)
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
            // Phone / id rows are mono and must be copyable by an operator.
            if (mono)
              SelectableId(value, style: AppType.mono(13.5))
            else
              Text(value,
                  style: const TextStyle(
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
      // Keep the bar's shape while an approval runs, so the layout does not
      // jump — a bare spinner in a 52px bar reads as a broken button.
      child: busy
          ? FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  minimumSize: const Size.fromHeight(52)),
              onPressed: null,
              child: const ButtonSpinner(),
            )
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
