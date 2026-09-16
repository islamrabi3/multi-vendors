import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/price_campaign_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../widgets/ad_destination_field.dart' show pickActiveStore;
import 'admin_manage_screen.dart' show adminManageWebSections;

/// Runs a discount campaign without the stores paying for it.
///
/// While a campaign is on, menu prices in its scope are raised by the same
/// percentage the customer is about to be given back as a discount. The store
/// is still paid on its own price, so the uplift is the platform's margin —
/// and when the campaign ends every price goes back to what it was.
class AdminPriceCampaignsScreen extends StatefulWidget {
  const AdminPriceCampaignsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminPriceCampaignsScreen> createState() =>
      _AdminPriceCampaignsScreenState();
}

class _AdminPriceCampaignsScreenState extends State<AdminPriceCampaignsScreen> {
  final _repository = PriceCampaignRepository();

  List<PriceCampaign>? _campaigns;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final campaigns = await _repository.fetchCampaigns();
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) => _CampaignForm(repository: _repository),
    );
    if (created == true) _load();
  }

  Future<void> _end(PriceCampaign campaign) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: campaign.name,
      message: context.l10n.campaignEndConfirm,
      confirmText: context.l10n.campaignEnd,
      cancelText: context.l10n.cancel,
      icon: Icons.stop_circle_outlined,
    );
    if (confirmed != true) return;
    try {
      final restored = await _repository.end(campaign.id);
      if (!mounted) return;
      showSnack(context, context.l10n.campaignEnded(restored));
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  String _scopeLabel(PriceCampaign campaign) {
    final l10n = context.l10n;
    return switch (campaign.scope) {
      'vendor' => campaign.vendorName ?? l10n.store,
      'category' => campaign.categoryName ?? l10n.category,
      _ => l10n.campaignScopeAll,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);
    final campaigns = _campaigns;

    final content = campaigns == null
        ? (_error != null
              ? FailureView(error: _error!, onRetry: _load)
              : const LoadingView())
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                96,
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.warmFill,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    l10n.campaignIntro,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                if (campaigns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: EmptyView(
                      message: l10n.campaignEmpty,
                      icon: Icons.trending_up_rounded,
                    ),
                  )
                else
                  for (final campaign in campaigns)
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpace.sm),
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  campaign.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.heading(15.5),
                                ),
                              ),
                              SoftBadge(
                                label: switch (campaign.status) {
                                  'active' => l10n.active,
                                  'ended' => l10n.campaignStatusEnded,
                                  _ => l10n.couponScheduled,
                                },
                                fill: campaign.isActive
                                    ? AppColors.successFill
                                    : campaign.isEnded
                                    ? AppColors.neutralFill
                                    : AppColors.amberFill,
                                ink: campaign.isActive
                                    ? AppColors.successInk
                                    : campaign.isEnded
                                    ? AppColors.textMuted
                                    : AppColors.amberInk,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              '+${campaign.markupPercent.toStringAsFixed(0)}%',
                              _scopeLabel(campaign),
                              if (campaign.itemCount > 0)
                                l10n.campaignItemsRaised(campaign.itemCount),
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            campaign.endsAt == null
                                ? formatDateTime(context, campaign.startsAt)
                                : '${formatDateTime(context, campaign.startsAt)}'
                                      ' → ${formatDateTime(context, campaign.endsAt!)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                          if (!campaign.isEnded) ...[
                            const SizedBox(height: AppSpace.sm),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: OutlinedButton.icon(
                                onPressed: () => _end(campaign),
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  size: 18,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.dangerInk,
                                  side: const BorderSide(
                                    color: AppColors.dangerInk,
                                  ),
                                ),
                                label: Text(l10n.campaignEnd),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
              ],
            ),
          );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.campaignNew),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Expanded(child: content),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/price-campaigns',
        sections: adminManageWebSections(context),
        pageTitle: l10n.campaignsTitle,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.campaignNew),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.campaignsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.campaignNew),
      ),
      body: SafeArea(top: false, child: content),
    );
  }
}

class _CampaignForm extends StatefulWidget {
  const _CampaignForm({required this.repository});

  final PriceCampaignRepository repository;

  @override
  State<_CampaignForm> createState() => _CampaignFormState();
}

class _CampaignFormState extends State<_CampaignForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _percent = TextEditingController(text: '10');

  String _scope = 'all';
  Vendor? _vendor;
  List<VendorCategory> _categories = const [];
  String? _categoryId;
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    CatalogRepository()
        .fetchVendorCategories()
        .then((list) {
          if (mounted) setState(() => _categories = list);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _startsAt : _endsAt) ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (!mounted) return;
    final at = DateTime(
      picked.year,
      picked.month,
      picked.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() {
      if (start) {
        _startsAt = at;
      } else {
        _endsAt = at;
      }
    });
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;
    if (_scope == 'vendor' && _vendor == null) {
      showSnack(context, l10n.required, error: true);
      return;
    }
    if (_scope == 'category' && _categoryId == null) {
      showSnack(context, l10n.required, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.create(
        name: _name.text,
        markupPercent: double.parse(_percent.text.trim()),
        scope: _scope,
        vendorId: _vendor?.id,
        categoryId: _categoryId,
        startsAt: _startsAt,
        endsAt: _endsAt,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showFailure(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.gutter,
          right: AppSpace.gutter,
          top: AppSpace.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpace.lg,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.campaignNew, style: AppType.heading(18)),
                const SizedBox(height: AppSpace.lg),
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: l10n.campaignName),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? l10n.required : null,
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _percent,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: l10n.campaignPercent,
                    suffixText: '%',
                    helperText: l10n.campaignPercentHint,
                    helperMaxLines: 3,
                  ),
                  validator: (v) {
                    final value = double.tryParse(v?.trim() ?? '');
                    return (value == null || value <= 0 || value > 100)
                        ? l10n.required
                        : null;
                  },
                ),
                const SizedBox(height: AppSpace.lg),
                SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text(
                        l10n.campaignScopeAll,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: 'vendor',
                      label: Text(
                        l10n.store,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment(
                      value: 'category',
                      label: Text(
                        l10n.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) => setState(() => _scope = s.first),
                ),
                if (_scope == 'vendor') ...[
                  const SizedBox(height: AppSpace.md),
                  InkWell(
                    onTap: () async {
                      final picked = await pickActiveStore(context);
                      if (picked != null) setState(() => _vendor = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.store,
                        prefixIcon: const Icon(
                          Icons.storefront_rounded,
                          size: 18,
                        ),
                      ),
                      child: Text(
                        _vendor?.name ?? l10n.pickOnMap,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                if (_scope == 'category') ...[
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.category),
                    items: [
                      for (final c in _categories)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            c.label(language),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: l10n.couponStartsAt,
                        value: _startsAt,
                        hint: l10n.campaignStartNow,
                        onTap: () => _pickDate(start: true),
                        onClear: () => setState(() => _startsAt = null),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: _DateTile(
                        label: l10n.couponExpiresAt,
                        value: _endsAt,
                        hint: l10n.notSet,
                        onTap: () => _pickDate(start: false),
                        onClear: () => setState(() => _endsAt = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: Text(
                    _startsAt == null ? l10n.campaignStartNow : l10n.save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: value == null
              ? const Icon(Icons.event_outlined, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null ? hint : formatDateTime(context, value!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }
}
