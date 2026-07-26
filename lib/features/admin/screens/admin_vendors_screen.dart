import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/common.dart';
import '../admin_vendors_cubit.dart';
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

class _VendorsView extends StatelessWidget {
  const _VendorsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<AdminVendorsCubit, AdminVendorsState>(
          listenWhen: (p, c) => p.error != c.error && c.error != null,
          listener: (context, state) =>
              showSnack(context, readableError(state.error!), error: true),
          builder: (context, state) {
            final cubit = context.read<AdminVendorsCubit>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                  child: Text(context.l10n.vendors, style: AppType.display(26)),
                ),
                _FilterBar(state: state, cubit: cubit),
                if (state.loading)
                  const Expanded(child: LoadingView())
                else
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: cubit.load,
                      child: _VendorList(state: state, cubit: cubit),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
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
          _chip('${context.l10n.all} ${state.vendors.length}', VendorFilter.all),
          _chip('${context.l10n.pending} ${state.pending.length}', VendorFilter.pending,
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
      child: GestureDetector(
        onTap: () => cubit.setFilter(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
                color: selected || highlight
                    ? Colors.transparent
                    : AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ),
    );
  }
}

class _VendorList extends StatelessWidget {
  const _VendorList({required this.state, required this.cubit});

  final AdminVendorsState state;
  final AdminVendorsCubit cubit;

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
      children: [
        if (showSections && state.pending.isNotEmpty) ...[
          _sectionLabel('${context.l10n.awaitingApproval} · ${state.pending.length}'),
          ...state.pending.map((v) =>
              _PendingCard(vendor: v, cubit: cubit)),
          const SizedBox(height: 8),
        ],
        if (showSections) ...[
          if (state.active.isNotEmpty)
            _sectionLabel('${context.l10n.active} · ${state.active.length}'),
          ...state.active.map((v) => _VendorRow(vendor: v)),
          if (state.suspended.isNotEmpty) ...[
            _sectionLabel('${context.l10n.suspended} · ${state.suspended.length}'),
            ...state.suspended.map((v) => _VendorRow(vendor: v)),
          ],
        ] else
          ...vendors.map((v) => v.isPending
              ? _PendingCard(vendor: v, cubit: cubit)
              : _VendorRow(vendor: v)),
      ],
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
  const _PendingCard({required this.vendor, required this.cubit});

  final Vendor vendor;
  final AdminVendorsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: const Color(0xFFFAD9CC), width: 1.5),
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
                  onPressed: () =>
                      context.push('/admin-app/vendors/${vendor.id}'),
                  child: Text(context.l10n.review),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.l10n.rejectVendor),
        content: Text('"${vendor.name}" ${context.l10n.willBeSuspendedAndHiddenFromCustomers}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(context.l10n.reject)),
        ],
      ),
    );
    if (ok == true) await cubit.setStatus(vendor.id, 'suspended');
  }
}

class _VendorRow extends StatelessWidget {
  const _VendorRow({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/admin-app/vendors/${vendor.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
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
