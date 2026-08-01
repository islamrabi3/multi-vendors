import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/tokens.dart';
import '../../../core/models/banner_item.dart';
import '../../../core/models/coupon.dart';
import '../../../core/repositories/coupons_repository.dart';
import '../../../core/repositories/offers_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../admin_coupons_cubit.dart';
import '../admin_offers_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminPromosScreen extends StatelessWidget {
  const AdminPromosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AdminOffersCubit(OffersRepository())),
        BlocProvider(create: (_) => AdminCouponsCubit(CouponsRepository())),
      ],
      child: const _PromosView(),
    );
  }
}

class _PromosView extends StatelessWidget {
  const _PromosView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.l10n.promos),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 16, 10),
              child: Row(
                children: [
                  Text(context.l10n.promos, style: AppType.display(26)),
                  const Spacer(),
                  _NewButton(),
                ],
              ),
            ),
            Expanded(
              child: MultiBlocListener(
                listeners: [
                  BlocListener<AdminOffersCubit, AdminOffersState>(
                    listenWhen: (p, c) => p.error != c.error && c.error != null,
                    listener: (context, s) =>
                        showFailure(context, s.error!),
                  ),
                  BlocListener<AdminCouponsCubit, AdminCouponsState>(
                    listenWhen: (p, c) => p.error != c.error && c.error != null,
                    listener: (context, s) =>
                        showFailure(context, s.error!),
                  ),
                ],
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    final offersFuture = context.read<AdminOffersCubit>().load();
                    final couponsFuture = context.read<AdminCouponsCubit>().load();
                    await Future.wait([offersFuture, couponsFuture]);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      _SectionLabel('Home banners'),
                      SizedBox(height: 10),
                      _BannersSection(),
                      SizedBox(height: 20),
                      _SectionLabel('Coupons'),
                      SizedBox(height: 10),
                      _CouponsSection(),
                    ],
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

class _NewButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'banner') {
          _showBannerForm(context, context.read<AdminOffersCubit>());
        } else {
          _showCouponForm(context, context.read<AdminCouponsCubit>());
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'banner', child: Text(context.l10n.newBanner)),
        PopupMenuItem(value: 'coupon', child: Text(context.l10n.newCoupon)),
      ],
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
            Text(context.l10n.newText,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
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
    final active = context.select((AdminOffersCubit c) =>
        c.state.offers.where((o) => o.isActive).length);
    final isBanners = text == 'Home banners';
    final labelText = isBanners ? context.l10n.homeBanners : context.l10n.coupons;
    return Row(
      children: [
        Text(labelText.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textFaint)),
        if (isBanners)
          Text('  ·  $active ${context.l10n.active}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textFaint)),
      ],
    );
  }
}

class _BannersSection extends StatelessWidget {
  const _BannersSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminOffersCubit, AdminOffersState>(
      builder: (context, state) {
        if (state.loading) {
          return const Padding(
              padding: EdgeInsets.all(24), child: LoadingView());
        }
        if (state.offers.isEmpty) {
          return _emptyCard(context.l10n.noBannersYetTapNew);
        }
        final cubit = context.read<AdminOffersCubit>();
        return Column(
          children: state.offers
              .map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: _BannerCard(offer: o, cubit: cubit),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.offer, required this.cubit});

  final BannerItem offer;
  final AdminOffersCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AppNetworkImage(
                  url: offer.imageUrl, height: 78, width: double.infinity),
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xCC1A1714), Color(0x221A1714)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.title ?? context.l10n.untitledBanner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.heading(18, color: Colors.white)),
                      if (offer.subtitle?.isNotEmpty ?? false)
                        Text(offer.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: offer.isActive
                          ? AppColors.success
                          : AppColors.textFaint,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                 Text(offer.isActive ? context.l10n.live : context.l10n.hidden,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                if (offer.code?.isNotEmpty ?? false) ...[
                  const SizedBox(width: 8),
                  SoftBadge(
                      label: offer.code!,
                      fill: AppColors.amberFill,
                      ink: AppColors.amberInk),
                ],
                const Spacer(),
                Switch(
                  value: offer.isActive,
                  activeThumbColor: AppColors.primary,
                  onChanged: (_) => cubit.toggleActive(offer),
                ),
                IconButton(
                  tooltip: context.l10n.delete,
                  onPressed: () => _confirmDelete(context),
                  icon:
                      const Icon(Icons.delete_outline, color: Color(0xFFC0392B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: context.l10n.deleteBanner,
      message: '"${offer.title ?? offer.imageUrl}" ${context.l10n.willBeRemoved}',
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.image_not_supported_rounded,
    );
    if (confirmed == true) {
      cubit.delete(offer);
    }
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
              padding: EdgeInsets.all(24), child: LoadingView());
        }
        if (state.coupons.isEmpty) {
          return _emptyCard(context.l10n.noCouponsYetTapNew);
        }
        final cubit = context.read<AdminCouponsCubit>();
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

class _CouponRow extends StatelessWidget {
  const _CouponRow(
      {required this.coupon, required this.cubit, required this.last});

  final Coupon coupon;
  final AdminCouponsCubit cubit;
  final bool last;

  String _summary(BuildContext context) {
    final v = coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}%'
        : formatMoney(coupon.value);
    final cap = coupon.maxDiscount != null
        ? ' · ${context.l10n.max} ${formatMoney(coupon.maxDiscount!)}'
        : '';
    final min = coupon.minOrderAmount > 0
        ? ' · ${context.l10n.min} ${formatMoney(coupon.minOrderAmount)}'
        : '';
    if (coupon.isExpired) return '$v · ${context.l10n.expired}';
    return '$v ${context.l10n.off}$cap$min';
  }

  String _usage(BuildContext context) {
    final limit = coupon.usageLimit == null ? '∞' : '${coupon.usageLimit}';
    return '${coupon.usedCount} / $limit ${context.l10n.used}';
  }

  @override
  Widget build(BuildContext context) {
    final dim = coupon.isExpired || !coupon.isActive;
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
            color: dim ? const Color(0xFFF1ECE6) : AppColors.amberFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(coupon.code,
              style: AppType.mono(13,
                  color: dim ? AppColors.textFaint : AppColors.ink)),
        ),
        title: Text(_summary(context),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: dim ? AppColors.textMuted : AppColors.ink)),
        subtitle: Text(_usage(context),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: coupon.isActive,
              activeThumbColor: AppColors.primary,
              onChanged: coupon.isExpired ? null : (_) => cubit.toggleActive(coupon),
            ),
            IconButton(
              tooltip: context.l10n.delete,
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFC0392B), size: 20),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: context.l10n.deleteCoupon,
      message: '"${coupon.code}" ${context.l10n.willBeRemoved}',
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.confirmation_number_outlined,
    );
    if (confirmed == true) {
      cubit.delete(coupon);
    }
  }
}

Widget _emptyCard(String message) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted)),
    );

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

void _showBannerForm(BuildContext context, AdminOffersCubit cubit) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(value: cubit, child: const _BannerForm()),
  );
}

class _BannerForm extends StatefulWidget {
  const _BannerForm();

  @override
  State<_BannerForm> createState() => _BannerFormState();
}

class _BannerFormState extends State<_BannerForm> {
  final _image = TextEditingController();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  bool _saving = false;
  bool _uploading = false;

  BannerType _type = BannerType.event;
  String? _vendorId;
  String? _couponCode;
  List<({String id, String name})> _vendors = const [];
  List<String> _couponCodes = const [];

  @override
  void initState() {
    super.initState();
    _loadPickerData();
  }

  Future<void> _loadPickerData() async {
    try {
      final client = Supabase.instance.client;
      final vendors = await client
          .from('vendors')
          .select('id, name')
          .eq('approval_status', 'active')
          .order('name', ascending: true);
      final coupons = await client
          .from('coupons')
          .select('code')
          .eq('is_active', true)
          .order('code', ascending: true);
      if (!mounted) return;
      setState(() {
        _vendors = (vendors as List)
            .map((v) => (id: v['id'] as String, name: v['name'] as String))
            .toList();
        _couponCodes =
            (coupons as List).map((c) => c['code'] as String).toList();
      });
    } catch (_) {
      // Pickers stay empty; validation will catch a missing selection.
    }
  }

  @override
  void dispose() {
    _image.dispose();
    _title.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final name = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final client = Supabase.instance.client;
      await client.storage.from('product-images').uploadBinary('banners/$name', bytes);
      final url = client.storage.from('product-images').getPublicUrl('banners/$name');
      setState(() {
        _image.text = url;
      });
      if (mounted) showSnack(context, 'Image uploaded successfully!');
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.newBanner, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _uploading ? null : _pickImage,
            child: Container(
              height: 128,
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_image.text.trim().isNotEmpty) ...[
                    AppNetworkImage(
                      url: _image.text.trim(),
                      height: 128,
                      width: double.infinity,
                    ),
                    Container(
                      color: Colors.black26,
                      width: double.infinity,
                      height: 128,
                    ),
                  ],
                  if (_uploading)
                    const CircularProgressIndicator(color: AppColors.primary)
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _image.text.trim().isNotEmpty
                              ? Icons.edit_outlined
                              : Icons.add_photo_alternate_outlined,
                          color: _image.text.trim().isNotEmpty ? Colors.white : AppColors.primary,
                          size: 32,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _image.text.trim().isNotEmpty
                              ? 'Tap to change photo'
                              : 'Tap to upload banner image',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _image.text.trim().isNotEmpty ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<BannerType>(
            segments: [
              ButtonSegment(
                  value: BannerType.coupon,
                  label: Text(context.l10n.bannerTypeCoupon),
                  icon: const Icon(Icons.confirmation_number_outlined,
                      size: 16)),
              ButtonSegment(
                  value: BannerType.vendor,
                  label: Text(context.l10n.bannerTypeVendor),
                  icon: const Icon(Icons.storefront_outlined, size: 16)),
              ButtonSegment(
                  value: BannerType.event,
                  label: Text(context.l10n.bannerTypeEvent),
                  icon: const Icon(Icons.campaign_outlined, size: 16)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          if (_type == BannerType.vendor) ...[
            DropdownButtonFormField<String>(
              initialValue: _vendorId,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: context.l10n.selectVendor,
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              items: _vendors
                  .map((v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _vendorId = v),
            ),
            const SizedBox(height: 10),
          ],
          if (_type == BannerType.coupon) ...[
            DropdownButtonFormField<String>(
              initialValue: _couponCode,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: context.l10n.selectCoupon,
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
              ),
              items: _couponCodes
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _couponCode = v),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
                hintText: context.l10n.titleEg40OffFirstOrder),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subtitle,
            decoration:
                InputDecoration(hintText: context.l10n.subtitleOptional),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _image,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: context.l10n.imageUrl,
              prefixIcon: const Icon(Icons.link_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving || _uploading ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.l10n.publishBanner),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final image = _image.text.trim();
    final title = _title.text.trim();
    if (image.isEmpty && title.isEmpty) {
      showSnack(context, context.l10n.addATitleOrImageFirst, error: true);
      return;
    }
    if (_type == BannerType.vendor && (_vendorId == null || _vendorId!.isEmpty)) {
      showSnack(context, context.l10n.chooseVendorForBanner, error: true);
      return;
    }
    if (_type == BannerType.coupon &&
        (_couponCode == null || _couponCode!.isEmpty)) {
      showSnack(context, context.l10n.chooseCouponForBanner, error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<AdminOffersCubit>().create(
          imageUrl: image.isEmpty
              ? 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800'
              : image,
          type: _type,
          title: title,
          subtitle: _subtitle.text.trim(),
          code: _type == BannerType.coupon ? _couponCode : null,
          vendorId: _type == BannerType.vendor ? _vendorId : null,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      showSnack(context, context.l10n.bannerPublished);
    } else {
      setState(() => _saving = false);
    }
  }
}

void _showCouponForm(BuildContext context, AdminCouponsCubit cubit) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(value: cubit, child: const _CouponForm()),
  );
}

class _CouponForm extends StatefulWidget {
  const _CouponForm();

  @override
  State<_CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends State<_CouponForm> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _minOrder = TextEditingController();
  final _maxDiscount = TextEditingController();
  final _limit = TextEditingController();
  bool _percentage = true;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minOrder.dispose();
    _maxDiscount.dispose();
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.newCoupon, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: context.l10n.codeEgEaty40),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(context.l10n.percentage)),
              ButtonSegment(value: false, label: Text(context.l10n.fixedEgp)),
            ],
            selected: {_percentage},
            onSelectionChanged: (s) => setState(() => _percentage = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                hintText: _percentage ? context.l10n.discountPercent : context.l10n.discountAmountEgp),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _minOrder,
            keyboardType: TextInputType.number,
            decoration:
                InputDecoration(hintText: context.l10n.minOrderOptional),
          ),
          if (_percentage) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _maxDiscount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  hintText: context.l10n.maxDiscountCapOptional),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration:
                InputDecoration(hintText: context.l10n.usageLimitOptional),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.l10n.createCoupon),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final value = double.tryParse(_value.text.trim());
    if (code.isEmpty || value == null || value <= 0) {
      showSnack(context, context.l10n.enterACodeAndAValidDiscount, error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await context.read<AdminCouponsCubit>().create(
          code: code,
          discountType: _percentage ? 'percentage' : 'fixed',
          value: value,
          minOrderAmount: double.tryParse(_minOrder.text.trim()) ?? 0,
          maxDiscount:
              _percentage ? double.tryParse(_maxDiscount.text.trim()) : null,
          usageLimit: int.tryParse(_limit.text.trim()),
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
