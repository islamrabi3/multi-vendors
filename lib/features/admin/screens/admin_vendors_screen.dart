import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../admin_vendors_cubit.dart';
import 'admin_vendor_detail_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminVendorsScreen extends StatelessWidget {
  const AdminVendorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminVendorsCubit(AdminRepository()),
      child: const _VendorsView(),
    );
  }
}

class _VendorsView extends StatefulWidget {
  const _VendorsView();

  @override
  State<_VendorsView> createState() => _VendorsViewState();
}

class _VendorsViewState extends State<_VendorsView> {
  /// Store selected into the detail pane. Split widths only; below that a tap
  /// still pushes the detail route.
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split = AppBreakpoints.isSplit(constraints.maxWidth);
            return BlocConsumer<AdminVendorsCubit, AdminVendorsState>(
              listenWhen: (p, c) => p.error != c.error && c.error != null,
              listener: (context, state) =>
                  showSnack(context, readableError(state.error!), error: true),
              builder: (context, state) {
                final cubit = context.read<AdminVendorsCubit>();
                final list = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 22, 12),
                      child: Row(
                        children: [
                          if (Navigator.canPop(context))
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          Text(context.l10n.vendors, style: AppType.display(26)),
                        ],
                      ),
                    ),
                    _FilterBar(state: state, cubit: cubit),
                    if (state.loading)
                      const Expanded(child: LoadingView())
                    else
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: cubit.load,
                          child: _VendorList(
                            state: state,
                            cubit: cubit,
                            selectedId: split ? _selectedId : null,
                            onSelect: split
                                ? (v) => setState(() => _selectedId = v.id)
                                : null,
                          ),
                        ),
                      ),
                  ],
                );
                if (!split) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: list),
                    const VerticalDivider(
                        width: 1, thickness: 1, color: AppColors.border),
                    Expanded(
                      flex: 5,
                      child: _DetailPane(
                        vendorId: _selectedId,
                        onStatusChanged: cubit.load,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Right-hand pane of the wide layout: the selected store, or a hint to pick
/// one.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.vendorId, required this.onStatusChanged});

  final String? vendorId;
  final VoidCallback onStatusChanged;

  @override
  Widget build(BuildContext context) {
    if (vendorId == null) {
      return Center(
        child: EmptyView(
          message: context.l10n.vendors,
          icon: Icons.storefront_outlined,
        ),
      );
    }
    return AdminVendorDetailView(
      // Rebuild the view's state when the selection changes.
      key: ValueKey(vendorId),
      vendorId: vendorId!,
      embedded: true,
      onStatusChanged: onStatusChanged,
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state, required this.cubit});

  final AdminVendorsState state;
  final AdminVendorsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        children: [
          _chip('${context.l10n.all} ${state.countFor(VendorFilter.all)}',
              VendorFilter.all),
          _chip(
              '${context.l10n.pending} ${state.countFor(VendorFilter.pending)}',
              VendorFilter.pending,
              highlight: true),
          _chip(context.l10n.active, VendorFilter.active),
          _chip(context.l10n.suspended, VendorFilter.suspended),
        ],
      ),
    );
  }

  Widget _chip(String label, VendorFilter value, {bool highlight = false}) {
    final selected = state.filter == value;
    final bg = selected
        ? AppColors.ink
        : highlight
            ? AppColors.warmFill
            : AppColors.surface;
    final fg = selected
        ? Colors.white
        : highlight
            ? AppColors.primaryDark
            : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          onTap: () => cubit.setFilter(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(
                  color: hovered && !selected
                      ? AppColors.primary
                      : selected || highlight
                          ? Colors.transparent
                          : AppColors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ),
      ),
    );
  }
}

class _VendorList extends StatelessWidget {
  const _VendorList({
    required this.state,
    required this.cubit,
    this.selectedId,
    this.onSelect,
  });

  final AdminVendorsState state;
  final AdminVendorsCubit cubit;
  final String? selectedId;
  final ValueChanged<Vendor>? onSelect;

  @override
  Widget build(BuildContext context) {
    final showSections = state.filter == VendorFilter.all;
    final vendors = state.visible;
    if (vendors.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: 120),
          EmptyView(
              message: context.l10n.noVendorsHere, icon: Icons.storefront_outlined),
        ],
      );
    }
    return InfiniteScroll(
      onLoadMore: cubit.loadMore,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        children: [
          if (showSections && state.pending.isNotEmpty) ...[
            _sectionLabel('${context.l10n.awaitingApproval} · ${state.counts.pending}'),
            ...state.pending.map((v) => _PendingCard(
                  vendor: v,
                  cubit: cubit,
                  selected: v.id == selectedId,
                  onSelect: onSelect,
                )),
            const SizedBox(height: 8),
          ],
          if (showSections) ...[
            if (state.active.isNotEmpty)
              _sectionLabel('${context.l10n.active} · ${state.counts.active}'),
            ...state.active.map((v) => _VendorRow(
                  vendor: v,
                  selected: v.id == selectedId,
                  onSelect: onSelect,
                )),
            if (state.suspended.isNotEmpty) ...[
              _sectionLabel('${context.l10n.suspended} · ${state.counts.suspended}'),
              ...state.suspended.map((v) => _VendorRow(
                    vendor: v,
                    selected: v.id == selectedId,
                    onSelect: onSelect,
                  )),
            ],
          ] else
            ...vendors.map((v) => v.isPending
                ? _PendingCard(
                    vendor: v,
                    cubit: cubit,
                    selected: v.id == selectedId,
                    onSelect: onSelect,
                  )
                : _VendorRow(
                    vendor: v,
                    selected: v.id == selectedId,
                    onSelect: onSelect,
                  )),
          PagingFooter(loading: state.loadingMore, hasMore: state.hasMore),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textFaint)),
      );
}

/// Store avatar tile (logo or fallback icon).
class _StoreAvatar extends StatelessWidget {
  const _StoreAvatar({required this.vendor, this.size = 44});

  final Vendor vendor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      clipBehavior: Clip.antiAlias,
      child: vendor.logoUrl != null && vendor.logoUrl!.isNotEmpty
          ? AppNetworkImage(url: vendor.logoUrl, width: size, height: size)
          : const Icon(Icons.storefront, color: AppColors.primary),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.vendor,
    required this.cubit,
    this.selected = false,
    this.onSelect,
  });

  final Vendor vendor;
  final AdminVendorsCubit cubit;
  final bool selected;
  final ValueChanged<Vendor>? onSelect;

  void _review(BuildContext context) => onSelect != null
      ? onSelect!(vendor)
      : context.push('/admin-app/vendors/${vendor.id}');

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
              color: selected
                  ? AppColors.primary
                  : hovered
                      ? AppColors.primaryLight
                      : const Color(0xFFFAD9CC),
              width: 1.5),
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _StoreAvatar(vendor: vendor),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: AppColors.ink)),
                      if (vendor.addressText != null)
                        Text(vendor.addressText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                SoftBadge(
                    label: context.l10n.newText,
                    fill: AppColors.warmFill,
                    ink: AppColors.primaryDark),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textMuted),
                    onPressed: () => _reject(context),
                    child: Text(context.l10n.reject),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(40)),
                    onPressed: () => _review(context),
                    child: Text(context.l10n.review),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final ok = await AppDialogs.showConfirmDialog(
      context: context,
      title: context.l10n.rejectVendor,
      message: '"${vendor.name}" ${context.l10n.willBeSuspendedAndHiddenFromCustomers}',
      confirmText: context.l10n.reject,
      cancelText: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.store_rounded,
    );
    if (ok == true) await cubit.setStatus(vendor.id, 'suspended');
  }
}

class _VendorRow extends StatelessWidget {
  const _VendorRow({
    required this.vendor,
    this.selected = false,
    this.onSelect,
  });

  final Vendor vendor;
  final bool selected;
  final ValueChanged<Vendor>? onSelect;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (context, hovered) => InkWell(
        onTap: () => onSelect != null
            ? onSelect!(vendor)
            : context.push('/admin-app/vendors/${vendor.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
                color: selected
                    ? AppColors.primary
                    : hovered
                        ? AppColors.primaryLight
                        : AppColors.border,
                width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(16),
            boxShadow: hovered || selected ? AppShadows.card : null,
          ),
          child: Row(
            children: [
              _StoreAvatar(vendor: vendor, size: 42),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vendor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppColors.rating),
                        const SizedBox(width: 3),
                        Text(
                          '${vendor.ratingAvg.toStringAsFixed(1)} · '
                          '${vendor.ratingCount} ${context.l10n.ratings}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(vendor: vendor),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    if (vendor.isSuspended) {
      return SoftBadge(
          label: context.l10n.suspended,
          fill: Color(0xFFFBE7E4),
          ink: Color(0xFFC0392B));
    }
    if (vendor.isOpen) {
      return SoftBadge(
        label: context.l10n.open,
        fill: AppColors.successFill,
        ink: AppColors.successInk,
        leading: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
              color: AppColors.success, shape: BoxShape.circle),
        ),
      );
    }
    return SoftBadge(
        label: context.l10n.closed, fill: Color(0xFFF1ECE6), ink: AppColors.textMuted);
  }
}
