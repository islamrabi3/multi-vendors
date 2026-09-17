import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/errors/app_failure.dart' show UserMessage;
import '../../../core/models/finance.dart';
import '../../../core/models/vendor.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/repositories/account_onboarding_repository.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/location_picker.dart';
import '../../../core/utils/email.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';
import '../../auth/auth_cubit.dart';
import '../../vendor/screens/vendor_schedule_screen.dart';
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

  /// The commercial terms, which only an admin may write.
  ///
  /// A database trigger refuses these columns to the store itself, so this
  /// screen is the only place they can change: the delivery fee the customer
  /// pays, and how the platform earns from the store.
  Future<void> _editTerms(Vendor vendor) async {
    final fee = TextEditingController(
      text: vendor.deliveryFee.toStringAsFixed(2),
    );
    final commission = TextEditingController(
      text: vendor.commissionRate.toStringAsFixed(1),
    );
    final subscription = TextEditingController(
      text: vendor.subscriptionFee.toStringAsFixed(2),
    );
    var model = vendor.billingModel;

    final saved = await showFormDialog<bool>(
      context: context,
      title: context.l10n.platformTerms,
      icon: Icons.receipt_long_rounded,
      submitLabel: context.l10n.save,
      cancelLabel: context.l10n.cancel,
      contentBuilder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: fee,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: context.l10n.deliveryFee),
            ),
            const SizedBox(height: AppSpace.md),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'commission',
                  label: Text(context.l10n.billingCommission),
                ),
                ButtonSegment(
                  value: 'subscription',
                  label: Text(context.l10n.billingSubscription),
                ),
              ],
              selected: {model},
              onSelectionChanged: (s) => setDialogState(() => model = s.first),
            ),
            const SizedBox(height: AppSpace.md),
            // Only one of the two can be in force at a time, so only one is
            // ever on screen.
            if (model == 'commission')
              TextField(
                controller: commission,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.commissionRate,
                  suffixText: '%',
                ),
              )
            else
              TextField(
                controller: subscription,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.subscriptionFee,
                ),
              ),
          ],
        ),
      ),
      onSubmit: (_) async {
        await VendorAdminRepository().updateVendor(vendor.id, {
          'delivery_fee': double.tryParse(fee.text.trim()) ?? 0,
          'billing_model': model,
          // A subscription store pays nothing per order, and a commission
          // store pays nothing per month; writing both would leave whichever
          // is not in force lying around to be applied by mistake later.
          'commission_rate': model == 'commission'
              ? (double.tryParse(commission.text.trim()) ?? 0)
              : 0,
          'subscription_fee': model == 'subscription'
              ? (double.tryParse(subscription.text.trim()) ?? 0)
              : 0,
        });
        return true;
      },
    );

    disposeAfterClose([fee, commission, subscription]);
    if (saved != true || !mounted) return;
    setState(() {
      _future = _load();
    });
    showSnack(context, context.l10n.termsSaved);
  }

  /// Everything about the store the owner could edit themselves.
  ///
  /// An operator onboarding a shop in person has the details in front of them
  /// — a corrected phone number, the real address, the minimum the owner just
  /// agreed to — and had no way to enter any of it: the store row was the
  /// owner's alone to write once created. The platform's commercial terms
  /// stay in their own editor, behind their own permission.
  Future<void> _editProfile(Vendor vendor) async {
    final l10n = context.l10n;
    final name = TextEditingController(text: vendor.name);
    final description = TextEditingController(text: vendor.description ?? '');
    final phone = TextEditingController(text: vendor.phone ?? '');
    final address = TextEditingController(text: vendor.addressText ?? '');
    final minOrder = TextEditingController(
      text: vendor.minOrderAmount > 0
          ? vendor.minOrderAmount.toStringAsFixed(0)
          : '',
    );
    final prep = TextEditingController(text: '${vendor.avgPrepMinutes}');
    final radius = TextEditingController(
      text: vendor.deliveryRadiusKm.toStringAsFixed(1),
    );
    var categoryId = vendor.categoryId;
    final categories = await _repo.fetchVendorCategories();
    if (!mounted) return;

    Widget field(
      TextEditingController controller,
      String label, {
      TextInputType keyboard = TextInputType.text,
      int maxLines = 1,
      String? suffix,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      ),
    );

    final saved = await showFormDialog<bool>(
      context: context,
      title: l10n.storeProfile,
      icon: Icons.storefront_rounded,
      submitLabel: l10n.save,
      cancelLabel: l10n.cancel,
      contentBuilder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(name, l10n.storeName),
            field(description, l10n.description, maxLines: 3),
            field(phone, l10n.storePhone, keyboard: TextInputType.phone),
            field(address, l10n.storeAddress, maxLines: 2),
            // A store filed under nothing never appears when a customer
            // browses by category, so it is offered here rather than left to
            // whatever was picked at signup.
            DropdownButtonFormField<String>(
              initialValue: categories.any((c) => c.id == categoryId)
                  ? categoryId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.category),
              items: [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(
                      category.label(Localizations.localeOf(context).languageCode),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setDialogState(() => categoryId = value),
            ),
            const SizedBox(height: AppSpace.md),
            field(
              minOrder,
              l10n.minimumOrder,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            field(
              prep,
              l10n.avgPrepTime,
              keyboard: TextInputType.number,
              suffix: l10n.minShort,
            ),
            field(
              radius,
              l10n.deliveryRadius,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              suffix: 'km',
            ),
          ],
        ),
      ),
      onSubmit: (_) async {
        final storeName = name.text.trim();
        if (storeName.isEmpty) throw UserMessage(l10n.required);
        await VendorAdminRepository().updateVendor(vendor.id, {
          'name': storeName,
          'description': description.text.trim().isEmpty
              ? null
              : description.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
          'address_text': address.text.trim().isEmpty
              ? null
              : address.text.trim(),
          // Left out entirely when unset, so a store that was never filed
          // keeps whatever it had rather than being cleared.
          'category_id': ?categoryId,
          'min_order_amount': double.tryParse(minOrder.text.trim()) ?? 0,
          // A prep time of zero would promise the customer an instant
          // kitchen, so the store's own floor of one minute applies here too.
          'avg_prep_minutes': (int.tryParse(prep.text.trim()) ?? 20).clamp(
            1,
            240,
          ),
          'delivery_radius_km':
              double.tryParse(radius.text.trim())?.clamp(0.5, 50) ?? 10,
        });
        return true;
      },
    );

    disposeAfterClose([
      name,
      description,
      phone,
      address,
      minOrder,
      prep,
      radius,
    ]);
    if (saved != true || !mounted) return;
    setState(() {
      _future = _load();
    });
    showSnack(context, context.l10n.saved);
  }

  /// The login the store signs in with.
  ///
  /// An owner who forgets their password or mistyped their email at signup
  /// rings the operator, who until now could do nothing about either: both
  /// live in auth.users, which no client may write. Every field is optional —
  /// what is left alone is left alone, and an empty password keeps the
  /// current one rather than clearing it.
  Future<void> _editAccount(Vendor vendor) async {
    final l10n = context.l10n;
    final accounts = AccountOnboardingRepository();
    AccountLogin? login;
    try {
      login = await accounts.fetchLogin(vendor.ownerId);
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (!mounted) return;

    final name = TextEditingController(text: login?.fullName ?? '');
    final phone = TextEditingController(text: login?.phone ?? '');
    final email = TextEditingController(text: login?.email ?? '');
    final username = TextEditingController(text: login?.username ?? '');
    final password = TextEditingController();
    final before = login;

    final saved = await showFormDialog<bool>(
      context: context,
      title: l10n.ownerAccount,
      icon: Icons.manage_accounts_rounded,
      submitLabel: l10n.save,
      cancelLabel: l10n.cancel,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.ownerAccountHint,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: l10n.ownerName),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l10n.phoneNumber),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l10n.email),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: username,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: l10n.usernameLabel,
              helperText: l10n.usernameHint,
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: password,
            obscureText: true,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: l10n.newPasswordOptional,
              helperText: l10n.passwordMin8,
            ),
          ),
        ],
      ),
      onSubmit: (_) async {
        final newEmail = email.text.trim().toLowerCase();
        if (newEmail.isNotEmpty && !isValidEmail(newEmail)) {
          throw UserMessage(l10n.enterValidEmail);
        }
        if (password.text.isNotEmpty && password.text.length < 8) {
          throw UserMessage(l10n.passwordMin8);
        }
        // Only what actually differs is sent: an unchanged email would still
        // be a write to the login, and an unchanged username would still be a
        // uniqueness check that could refuse the whole save.
        await accounts.updateAccount(
          userId: vendor.ownerId,
          email: newEmail == (before?.email ?? '') ? null : newEmail,
          password: password.text.isEmpty ? null : password.text,
          username: username.text.trim() == (before?.username ?? '')
              ? null
              : username.text.trim(),
          fullName: name.text.trim() == (before?.fullName ?? '')
              ? null
              : name.text.trim(),
          phone: phone.text.trim() == (before?.phone ?? '')
              ? null
              : phone.text.trim(),
        );
        return true;
      },
    );

    disposeAfterClose([name, phone, email, username, password]);
    if (saved != true || !mounted) return;
    setState(() {
      _future = _load();
    });
    showSnack(context, context.l10n.accountUpdated);
  }

  /// The store's logo or its cover photo, uploaded on the owner's behalf.
  Future<void> _pickImage(Vendor vendor, {required bool logo}) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final safe = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final url = await VendorAdminRepository().uploadImage(
        bucket: 'vendor-assets',
        path: '${logo ? 'logo' : 'cover'}/${vendor.id}/${stamp}_$safe',
        bytes: bytes,
      );
      await VendorAdminRepository().updateVendor(vendor.id, {
        logo ? 'logo_url' : 'cover_url': url,
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _future = _load();
      });
      showSnack(context, context.l10n.photoUpdated);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, error);
      }
    }
  }

  /// Deletes the store's entire catalogue.
  ///
  /// The undo for a menu imported from the wrong source, or against the wrong
  /// shop — otherwise a few hundred items have to go one at a time. Guarded by
  /// typing the store's name, not by an "are you sure": this cannot be undone,
  /// and the one mistake worth designing against is doing it to the store
  /// beside the one intended.
  Future<void> _clearMenu(Vendor vendor) async {
    final l10n = context.l10n;
    final typed = TextEditingController();
    final confirmed = await showFormDialog<bool>(
      context: context,
      title: l10n.clearMenu,
      icon: Icons.delete_forever_rounded,
      submitLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      contentBuilder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerFill,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Text(
                l10n.clearMenuWarning,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.dangerInk,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              vendor.name,
              style: AppType.heading(15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: typed,
              autocorrect: false,
              onChanged: (_) => setDialogState(() {}),
              decoration: InputDecoration(
                labelText: l10n.clearMenuConfirmHint,
              ),
            ),
          ],
        ),
      ),
      onSubmit: (_) async {
        if (typed.text.trim() != vendor.name.trim()) {
          throw UserMessage(l10n.clearMenuConfirmHint);
        }
        return true;
      },
    );

    disposeAfterClose([typed]);
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final removed = await _repo.clearVendorMenu(vendor.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _future = _load();
      });
      showSnack(
        context,
        removed.items == 0 && removed.sections == 0
            ? context.l10n.menuAlreadyEmpty
            : context.l10n.menuCleared(removed.items, removed.sections),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, error);
      }
    }
  }

  /// The store's weekly opening hours, in the same editor the owner uses.
  Future<void> _editSchedule(Vendor vendor) async {
    await showAdaptiveSheet<void>(
      context: context,
      showDragHandle: true,
      // The editor is a list of seven days: it needs a height to live in
      // rather than the unbounded one a sheet offers.
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.82,
        child: Column(
          children: [
            // The embedded editor drops its own app bar, so the sheet says
            // which store's week is being set.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sheetContext.l10n.operatingHoursSchedule,
                          style: AppType.heading(16),
                        ),
                        Text(
                          vendor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: VendorScheduleScreen(vendorId: vendor.id, embedded: true),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _future = _load());
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
  /// Hands the AI menu importer to this store, or takes it back.
  ///
  /// Each run costs a model call per photo, so this is off by default and
  /// granted per store rather than to everyone. The server checks the same
  /// flag in `can_extract_menu`, so switching it off stops the spending and
  /// not merely the button.
  Future<void> _setAiMenu(bool enabled) async {
    setState(() => _busy = true);
    try {
      await VendorAdminRepository().updateVendor(widget.vendorId, {
        'ai_menu_enabled': enabled,
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

  /// Hands the store's orders to the platform, or gives them back.
  Future<void> _setOrderFlow(bool platformRun) async {
    setState(() => _busy = true);
    try {
      await _repo.setVendorOrderFlow(widget.vendorId, platformRun);
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

  Future<void> _setRecommended(bool recommended, {int rank = 0}) async {
    setState(() => _busy = true);
    try {
      await _repo.setVendorRecommended(
        widget.vendorId,
        recommended,
        rank: rank,
      );
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
          onRetry: () => setState(() {
            _future = _load();
          }),
        );
      }
      final (vendor, owner) = snap.data!;
      return Column(
        children: [
          Expanded(
            child: _Body(
              vendor: vendor,
              owner: owner,
              onEditProfile: _busy ? null : () => _editProfile(vendor),
              onEditSchedule: _busy ? null : () => _editSchedule(vendor),
              onEditAccount: _busy ? null : () => _editAccount(vendor),
              onClearMenu: _busy ? null : () => _clearMenu(vendor),
              onSetLocation: _busy ? null : () => _setLocation(vendor),
              onChangeLogo: _busy
                  ? null
                  : () => _pickImage(vendor, logo: true),
              onChangeCover: _busy
                  ? null
                  : () => _pickImage(vendor, logo: false),
              onEditTerms:
                  _busy ||
                      !context.watch<AuthCubit>().state.can('vendors.terms')
                  ? null
                  : () => _editTerms(vendor),
              showBack: !widget.embedded,
            ),
          ),
          // Stores onboarded before the map picker have no pin, so they
          // never surface in "nearby". The owner can fix it in their own
          // settings, but an operator should not have to chase them.
          if (vendor.lat == null || vendor.lng == null)
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                0,
                AppSpace.gutter,
                AppSpace.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                border: Border.all(color: AppColors.attentionBorder),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.add_location_alt_outlined,
                  color: AppColors.primary,
                ),
                title: Text(
                  context.l10n.storeLocationOnMap,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  context.l10n.pickOnMap,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                onTap: _busy ? null : () => _setLocation(vendor),
              ),
            ),
          if (vendor.isApproved &&
              context.watch<AuthCubit>().state.can('vendors.promote'))
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                0,
                AppSpace.gutter,
                AppSpace.sm,
              ),
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
                        : (v) =>
                              _setRecommended(v, rank: vendor.recommendedRank),
                    secondary: Icon(
                      Icons.auto_awesome,
                      color: vendor.isRecommended
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    title: Text(
                      context.l10n.manageRecommended,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      context.l10n.recommended,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.borderSoft),
                  SwitchListTile(
                    value: vendor.isPlatformRun,
                    onChanged: _busy ? null : _setOrderFlow,
                    secondary: Icon(
                      Icons.support_agent_rounded,
                      color: vendor.isPlatformRun
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    title: Text(
                      context.l10n.platformRunOrders,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      vendor.isPlatformRun
                          ? context.l10n.platformRunOn
                          : context.l10n.platformRunOff,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.borderSoft),
                  SwitchListTile(
                    value: vendor.aiMenuEnabled,
                    onChanged: _busy ? null : _setAiMenu,
                    secondary: Icon(
                      Icons.document_scanner_outlined,
                      color: vendor.aiMenuEnabled
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    title: Text(
                      context.l10n.aiMenuImport,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      vendor.aiMenuEnabled
                          ? context.l10n.aiMenuImportOn
                          : context.l10n.aiMenuImportOff,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.borderSoft),
                  // Rank decides the order of the rail on the customer
                  // home. Only meaningful once the store is promoted, so
                  // it stays hidden until then.
                  if (vendor.isRecommended)
                    ListTile(
                      dense: true,
                      leading: const SizedBox(width: 24),
                      title: Text(
                        context.l10n.sortOrder,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _busy || vendor.recommendedRank <= 0
                                ? null
                                : () => _setRecommended(
                                    true,
                                    rank: vendor.recommendedRank - 1,
                                  ),
                          ),
                          Text(
                            '${vendor.recommendedRank}',
                            style: AppType.mono(15),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: _busy
                                ? null
                                : () => _setRecommended(
                                    true,
                                    rank: vendor.recommendedRank + 1,
                                  ),
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
      // Approving a store is its own permission; a Finance role that can
      // set terms has no business letting stores onto the platform.
      if (!context.watch<AuthCubit>().state.can('vendors.approve')) {
        return const SizedBox.shrink();
      }
      return _ActionBar(
        vendor: snap.data!.$1,
        busy: _busy,
        onApprove: () => _setStatus('active', context.l10n.vendorApproved),
        onSuspend: () => _setStatus('suspended', context.l10n.vendorSuspended),
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
    required this.onEditTerms,
    this.onEditProfile,
    this.onEditSchedule,
    this.onEditAccount,
    this.onClearMenu,
    this.onSetLocation,
    this.onChangeLogo,
    this.onChangeCover,
    this.showBack = true,
  });

  final Vendor vendor;
  final VendorOwner? owner;

  /// Opens the platform-terms editor. Owned by the screen above, which holds
  /// the busy flag and reloads once it saves.
  final VoidCallback? onEditTerms;

  /// The store's own details, and its opening hours.
  final VoidCallback? onEditProfile;
  final VoidCallback? onEditSchedule;

  /// The login behind the store, its map pin, and its two photographs.
  final VoidCallback? onEditAccount;

  /// Empties the store's catalogue. Destructive, and drawn as such.
  final VoidCallback? onClearMenu;
  final VoidCallback? onSetLocation;
  final VoidCallback? onChangeLogo;
  final VoidCallback? onChangeCover;
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
                    // Directional: the back button and the logo sit at the
                    // reading start, which is the right edge in Arabic.
                    PositionedDirectional(
                      start: 16,
                      top: MediaQuery.of(context).padding.top + 8,
                      child: _CircleButton(
                        icon: Icons.chevron_left,
                        onTap: () => context.pop(),
                      ),
                    ),
                ],
              ),
            ),
            PositionedDirectional(
              start: 22,
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
                    ? AppNetworkImage(
                        url: vendor.logoUrl,
                        width: 70,
                        height: 70,
                      )
                    : const Icon(
                        Icons.storefront,
                        color: AppColors.primary,
                        size: 32,
                      ),
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
                            Text(vendor.name, style: AppType.heading(21)),
                            if (vendor.addressText != null)
                              Text(
                                vendor.addressText!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
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
                    _stat(
                      context.l10n.deliveryFee,
                      formatMoney(vendor.deliveryFee),
                    ),
                    const SizedBox(width: 9),
                    _stat(
                      context.l10n.minimumOrder,
                      formatMoney(vendor.minOrderAmount),
                    ),
                    const SizedBox(width: 9),
                    _stat(
                      context.l10n.prep,
                      '${vendor.avgPrepMinutes} ${context.l10n.minShort}',
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    _stat(
                      context.l10n.billingPlan,
                      vendor.isSubscription
                          ? '${context.l10n.billingSubscription} · '
                                '${formatMoney(vendor.subscriptionFee)}'
                          : '${context.l10n.billingCommission} · '
                                '${vendor.commissionRate.toStringAsFixed(0)}%',
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEditTerms,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(context.l10n.editTerms),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _label(context.l10n.financialSummary),
                const SizedBox(height: 9),
                _FinancePanel(vendorId: vendor.id),
                const SizedBox(height: 18),
                _label(context.l10n.ownerAndContact),
                const SizedBox(height: 9),
                _Card(
                  children: [
                    _row(context.l10n.owner, owner?.name ?? '—'),
                    _row(
                      context.l10n.phoneNumber,
                      owner?.phone ?? '—',
                      mono: true,
                    ),
                    _row(
                      context.l10n.address,
                      vendor.addressText ?? '—',
                      last: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEditProfile,
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: Text(
                          context.l10n.storeProfile,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEditSchedule,
                        icon: const Icon(Icons.schedule_rounded, size: 18),
                        label: Text(
                          context.l10n.operatingHoursSchedule,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEditAccount,
                        icon: const Icon(
                          Icons.manage_accounts_rounded,
                          size: 18,
                        ),
                        label: Text(
                          context.l10n.ownerAccount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      // Offered whether or not the store already has a pin:
                      // moving a shop that pinned itself wrongly is as much
                      // the operator's job as pinning one that never did.
                      child: OutlinedButton.icon(
                        onPressed: onSetLocation,
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: Text(
                          context.l10n.storeLocationOnMap,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onChangeLogo,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(
                          context.l10n.changeLogo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onChangeCover,
                        icon: const Icon(Icons.panorama_outlined, size: 18),
                        label: Text(
                          context.l10n.changeCover,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                // Importing a catalogue was already possible; correcting one
                // price in it afterwards was not, which left the operator
                // talking a shop through a fix or importing all over again.
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () =>
                            context.push('/admin-app/menu/${vendor.id}'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                        icon: const Icon(
                          Icons.restaurant_menu_rounded,
                          size: 18,
                        ),
                        label: Text(
                          context.l10n.menu,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    // Drawn in the danger colour and placed last: it reads as
                    // what it is rather than as another menu action.
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onClearMenu,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: AppColors.dangerInk,
                          side: const BorderSide(color: AppColors.dangerInk),
                        ),
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: Text(
                          context.l10n.clearMenu,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                if (vendor.description != null &&
                    vendor.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _label(context.l10n.about),
                  const SizedBox(height: 9),
                  _Card(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          vendor.description!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
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
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
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

  Widget _label(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: AppColors.textFaint,
    ),
  );

  Widget _row(
    String label,
    String value, {
    bool mono = false,
    bool last = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.borderSoft)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        // Phone / id rows are mono and must be copyable by an operator.
        if (mono)
          SelectableId(value, style: AppType.mono(13.5))
        else
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
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
        ink: AppColors.primaryDark,
      );
    }
    if (vendor.isSuspended) {
      return SoftBadge(
        label: context.l10n.suspended1,
        fill: AppColors.dangerFill,
        ink: AppColors.dangerInk,
      );
    }
    return SoftBadge(
      label: context.l10n.active1,
      fill: AppColors.successFill,
      ink: AppColors.successInk,
    );
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
                minimumSize: const Size.fromHeight(52),
              ),
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
                        foregroundColor: AppColors.textMuted,
                      ),
                      onPressed: onSuspend,
                      child: Text(
                        vendor.isPending
                            ? context.l10n.reject
                            : context.l10n.suspend,
                      ),
                    ),
                  ),
                if (!vendor.isApproved) ...[
                  if (!vendor.isSuspended) const SizedBox(width: 11),
                  Expanded(
                    flex: vendor.isPending ? 3 : 1,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: onApprove,
                      icon: const Icon(Icons.check_rounded, size: 19),
                      label: Text(
                        vendor.isPending
                            ? context.l10n.approveVendor
                            : context.l10n.reactivate,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// What this store is owed, what it owes, and its lifetime numbers — the one
/// thing the profile view above it never showed. An admin fielding "where is
/// my money" had to leave this screen, open Settlements, and search the store
/// by name in a flat list to answer a question this screen is the obvious
/// place to ask.
class _FinancePanel extends StatefulWidget {
  const _FinancePanel({required this.vendorId});

  final String vendorId;

  @override
  State<_FinancePanel> createState() => _FinancePanelState();
}

class _FinancePanelState extends State<_FinancePanel> {
  final _repository = FinanceRepository();
  late Future<WalletSummary> _future = _repository.vendorWallet(
    widget.vendorId,
  );

  Future<void> _openHistory() async {
    List<Settlement> history;
    try {
      history = await _repository.settlements(
        ownerType: LedgerOwner.vendor,
        ownerId: widget.vendorId,
        limit: 50,
      );
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (!mounted) return;

    await showAdaptiveSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.settlementsTitle, style: AppType.heading(18)),
              const SizedBox(height: AppSpace.md),
              if (history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: EmptyView(
                    message: context.l10n.noTransactionsYet,
                    icon: Icons.receipt_long_outlined,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (_, i) =>
                        SettlementTile(settlement: history[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<WalletSummary>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return const _FinancePanelSkeleton();
        }
        if (snap.hasError) {
          return _FinanceError(
            onRetry: () => setState(
              () => _future = _repository.vendorWallet(widget.vendorId),
            ),
          );
        }
        final wallet = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: MoneyTile(
                    label: l10n.vendorPayableTotal,
                    value: formatMoney(wallet.payable),
                    tone: wallet.payable > 0 ? AppColors.successInk : null,
                    emphasis: true,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: MoneyTile(
                    label: l10n.cashDue,
                    value: formatMoney(wallet.cashDue),
                    tone: wallet.cashDue > 0 ? AppColors.amberInk : null,
                    emphasis: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            _Card(
              children: [
                _row(
                  l10n.totalEarningsLabel,
                  formatMoney(wallet.totalEarnings),
                ),
                _row(
                  l10n.totalSettlementsLabel,
                  formatMoney(wallet.totalSettlements),
                ),
                _row(
                  l10n.lastSettlement,
                  wallet.lastSettlementAt == null
                      ? '—'
                      : '${wallet.lastSettlementAt!.day}/'
                            '${wallet.lastSettlementAt!.month}/'
                            '${wallet.lastSettlementAt!.year}',
                  last: true,
                ),
              ],
            ),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _openHistory,
              icon: const Icon(Icons.history_rounded, size: 17),
              label: Text(l10n.settlementHistory),
            ),
          ],
        );
      },
    );
  }

  // Same two-line row style as the rest of this screen's cards — kept local
  // rather than reaching into `_Body`'s private helpers, which are not
  // reusable across widgets.
  Widget _row(String label, String value, {bool last = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.borderSoft)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _FinancePanelSkeleton extends StatelessWidget {
  const _FinancePanelSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonTheme(
    child: Row(
      children: [
        Expanded(child: Skeleton.box(height: 68, radius: AppRadii.lg)),
        const SizedBox(width: 9),
        Expanded(child: Skeleton.box(height: 68, radius: AppRadii.lg)),
      ],
    ),
  );
}

class _FinanceError extends StatelessWidget {
  const _FinanceError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpace.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(AppRadii.lg),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.errUnknown,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
}
