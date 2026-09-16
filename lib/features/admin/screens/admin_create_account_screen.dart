import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/account_onboarding_repository.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/location_picker.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;

/// Which kind of account the admin is creating.
enum NewAccountKind { vendor, driver }

/// An admin creates a store or a driver in one go: the email and password
/// they will sign in with, and everything the account needs to start working
/// — the details the owner would otherwise fill in during onboarding.
///
/// Returns true when an account was created, so the list behind can reload.
class AdminCreateAccountScreen extends StatefulWidget {
  const AdminCreateAccountScreen({super.key, required this.kind});

  final NewAccountKind kind;

  static Future<bool?> open(BuildContext context, NewAccountKind kind) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AdminCreateAccountScreen(kind: kind),
        ),
      );

  @override
  State<AdminCreateAccountScreen> createState() =>
      _AdminCreateAccountScreenState();
}

class _AdminCreateAccountScreenState extends State<AdminCreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = AccountOnboardingRepository();

  // Login
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  bool _showPassword = true;

  // Store
  final _storeName = TextEditingController();
  final _description = TextEditingController();
  final _storePhone = TextEditingController();
  final _address = TextEditingController();
  final _minOrder = TextEditingController(text: '0');
  final _prep = TextEditingController(text: '20');
  final _deliveryFee = TextEditingController(text: '0');
  final _radius = TextEditingController(text: '10');
  final _commission = TextEditingController(text: '10');
  final _subscription = TextEditingController(text: '0');
  String _billing = 'commission';
  String? _categoryId;
  List<VendorCategory> _categories = const [];
  LatLng? _pin;
  PickedImage? _logo;
  PickedImage? _cover;

  // Driver
  final _documents = <String, PickedImage>{};

  bool _approve = true;
  bool _saving = false;

  bool get _isVendor => widget.kind == NewAccountKind.vendor;

  @override
  void initState() {
    super.initState();
    if (_isVendor) {
      CatalogRepository()
          .fetchVendorCategories()
          .then((list) {
            if (mounted) setState(() => _categories = list);
          })
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _email,
      _password,
      _username,
      _phone,
      _storeName,
      _description,
      _storePhone,
      _address,
      _minOrder,
      _prep,
      _deliveryFee,
      _radius,
      _commission,
      _subscription,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Ten characters from a set with no look-alikes (no 0/O, 1/l/I), so it can
  /// be read out over the phone.
  void _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    setState(() {
      _password.text = List.generate(
        10,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      _showPassword = true;
    });
  }

  Future<PickedImage?> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return null;
      return (name: file.name, bytes: await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickLocation() async {
    final picked = await showLocationPicker(
      context,
      initial: _pin,
      title: context.l10n.storeLocationOnMap,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pin = picked.point;
      final resolved = picked.address?.trim() ?? '';
      if (_address.text.trim().isEmpty && resolved.isNotEmpty) {
        _address.text = resolved;
      }
    });
  }

  double _number(TextEditingController c, double fallback) =>
      double.tryParse(c.text.trim()) ?? fallback;

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;
    if (_isVendor && _pin == null) {
      showSnack(context, l10n.pickStoreLocationFirst, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isVendor) {
        await _repo.createVendorAccount(
          email: _email.text,
          password: _password.text,
          fullName: _fullName.text,
          phone: _phone.text,
          username: _username.text,
          approve: _approve,
          logo: _logo,
          cover: _cover,
          store: {
            'name': _storeName.text.trim(),
            'description': _description.text.trim(),
            'category_id': _categoryId,
            'phone': _storePhone.text.trim(),
            'address_text': _address.text.trim(),
            'lat': _pin!.latitude,
            'lng': _pin!.longitude,
            'min_order_amount': _number(_minOrder, 0),
            'avg_prep_minutes': _number(_prep, 20).round(),
            'delivery_fee': _number(_deliveryFee, 0),
            'delivery_radius_km': _number(_radius, 10),
            'billing_model': _billing,
            'commission_rate': _number(_commission, 10),
            'subscription_fee': _number(_subscription, 0),
          },
        );
      } else {
        await _repo.createDriverAccount(
          email: _email.text,
          password: _password.text,
          fullName: _fullName.text,
          phone: _phone.text,
          username: _username.text,
          approve: _approve,
          documents: _documents,
        );
      }
      if (!mounted) return;
      await _showCredentials();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showFailure(context, error);
      }
    }
  }

  /// The one moment the password is visible to anyone but the admin who typed
  /// it — so it is shown once, with a copy button, before the form goes away.
  Future<void> _showCredentials() {
    final l10n = context.l10n;
    final text =
        '${l10n.email}: ${_email.text.trim().toLowerCase()}\n'
        '${l10n.password}: ${_password.text}';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: AppColors.successInk,
          size: 40,
        ),
        title: Text(l10n.accountCreatedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.accountCreatedHint,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                text,
                textDirection: TextDirection.ltr,
                style: AppType.mono(13.5, color: AppColors.ink),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(SnackBar(content: Text(l10n.copiedLabel)));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l10n.copyLoginDetails),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? context.l10n.required : null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_isVendor ? l10n.newStoreAccount : l10n.newDriverAccount),
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.md,
                AppSpace.gutter,
                AppSpace.xl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _Section(
                  icon: Icons.lock_person_rounded,
                  title: l10n.loginDetailsSection,
                  children: [
                    TextFormField(
                      controller: _fullName,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: _isVendor ? l10n.ownerName : l10n.fullName,
                      ),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      decoration: InputDecoration(labelText: l10n.email),
                      validator: (v) =>
                          (v == null ||
                              !RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim()))
                          ? l10n.enterValidEmail
                          : null,
                    ),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        helperText: l10n.passwordMin8,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.generatePassword,
                              icon: const Icon(Icons.casino_outlined, size: 20),
                              onPressed: _generatePassword,
                            ),
                            IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                            ),
                          ],
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 8)
                          ? l10n.passwordMin8
                          : null,
                    ),
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: l10n.usernameLabel,
                        helperText: l10n.usernameHint,
                        helperMaxLines: 2,
                      ),
                      validator: (v) {
                        final name = v?.trim() ?? '';
                        // Optional here: an admin creating a store in a hurry
                        // can leave the account signing in with its email.
                        if (name.isEmpty) return null;
                        return RegExp(r'^[A-Za-z0-9._]{3,20}$').hasMatch(name)
                            ? null
                            : l10n.usernameInvalid;
                      },
                    ),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: l10n.phoneNumber),
                      validator: _isVendor ? null : _required,
                    ),
                  ],
                ),
                if (_isVendor) ...[
                  _Section(
                    icon: Icons.storefront_rounded,
                    title: l10n.storeDetailsSection,
                    children: [
                      TextFormField(
                        controller: _storeName,
                        decoration: InputDecoration(labelText: l10n.storeName),
                        validator: _required,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l10n.category),
                        items: [
                          for (final c in _categories)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.isTopLevel
                                    ? c.label(language)
                                    : '   · ${c.label(language)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                        validator: (v) => v == null ? l10n.required : null,
                      ),
                      TextFormField(
                        controller: _description,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: l10n.description,
                        ),
                      ),
                      TextFormField(
                        controller: _storePhone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(labelText: l10n.storePhone),
                      ),
                      TextFormField(
                        controller: _address,
                        decoration: InputDecoration(
                          labelText: l10n.storeAddress,
                        ),
                        validator: _required,
                      ),
                      _LocationTile(pin: _pin, onTap: _pickLocation),
                      Row(
                        children: [
                          Expanded(
                            child: _NumberField(
                              controller: _minOrder,
                              label: l10n.minOrderEgp,
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: _NumberField(
                              controller: _prep,
                              label: l10n.averagePrepTimeMinutes,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _Section(
                    icon: Icons.handshake_rounded,
                    title: l10n.platformTermsSection,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _NumberField(
                              controller: _deliveryFee,
                              label: l10n.deliveryFee,
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: _NumberField(
                              controller: _radius,
                              label: '${l10n.deliveryRadius} (km)',
                            ),
                          ),
                        ],
                      ),
                      SegmentedButton<String>(
                        expandedInsets: EdgeInsets.zero,
                        segments: [
                          ButtonSegment(
                            value: 'commission',
                            label: Text(l10n.billingCommission),
                          ),
                          ButtonSegment(
                            value: 'subscription',
                            label: Text(l10n.billingSubscription),
                          ),
                        ],
                        selected: {_billing},
                        onSelectionChanged: (s) =>
                            setState(() => _billing = s.first),
                      ),
                      if (_billing == 'commission')
                        _NumberField(
                          controller: _commission,
                          label: l10n.commissionRate,
                          suffix: '%',
                        )
                      else
                        _NumberField(
                          controller: _subscription,
                          label: l10n.subscriptionFee,
                        ),
                    ],
                  ),
                  _Section(
                    icon: Icons.photo_library_rounded,
                    title: l10n.storePhotosSection,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ImageSlot(
                              label: l10n.storeLogoLabel,
                              image: _logo,
                              onPick: () async {
                                final picked = await _pickImage();
                                if (picked != null) {
                                  setState(() => _logo = picked);
                                }
                              },
                              onClear: () => setState(() => _logo = null),
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            flex: 2,
                            child: _ImageSlot(
                              label: l10n.storeCoverLabel,
                              image: _cover,
                              onPick: () async {
                                final picked = await _pickImage();
                                if (picked != null) {
                                  setState(() => _cover = picked);
                                }
                              },
                              onClear: () => setState(() => _cover = null),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else
                  _Section(
                    icon: Icons.badge_rounded,
                    title: l10n.driverDocumentsOptional,
                    children: [
                      for (final row in [
                        [
                          ('id_card_url', l10n.idFront),
                          ('id_card_back_url', l10n.idBack),
                        ],
                        [
                          ('license_url', l10n.licenseFront),
                          ('license_back_url', l10n.licenseBack),
                        ],
                      ])
                        Row(
                          children: [
                            for (final (i, (column, label)) in row.indexed) ...[
                              if (i > 0) const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: _ImageSlot(
                                  label: label,
                                  image: _documents[column],
                                  onPick: () async {
                                    final picked = await _pickImage();
                                    if (picked != null) {
                                      setState(
                                        () => _documents[column] = picked,
                                      );
                                    }
                                  },
                                  onClear: () =>
                                      setState(() => _documents.remove(column)),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpace.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SwitchListTile(
                    value: _approve,
                    onChanged: (v) => setState(() => _approve = v),
                    title: Text(
                      l10n.approveNow,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _approve ? l10n.approveNowOnHint : l10n.approveNowOffHint,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const ButtonSpinner(size: 18)
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(
                    _isVendor
                        ? l10n.createStoreAccount
                        : l10n.createDriverAccount,
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

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.lg),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.warmFill,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(title, style: AppType.heading(15.5))),
            ],
          ),
          for (final child in children) ...[
            const SizedBox(height: AppSpace.md),
            child,
          ],
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (v) {
        final value = double.tryParse(v?.trim() ?? '');
        return value == null || value < 0 ? context.l10n.required : null;
      },
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.pin, required this.onTap});

  final LatLng? pin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSet = pin != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(labelText: l10n.storeLocationOnMap),
        child: Row(
          children: [
            Icon(
              isSet ? Icons.location_on : Icons.add_location_alt_outlined,
              size: 20,
              color: isSet ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                isSet
                    ? '${pin!.latitude.toStringAsFixed(5)}, '
                          '${pin!.longitude.toStringAsFixed(5)}'
                    : l10n.pickOnMap,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isSet ? AppColors.ink : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({
    required this.label,
    required this.image,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final PickedImage? image;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bytes = image?.bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: Material(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadii.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPick,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(bytes, fit: BoxFit.cover)
                  else
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                  if (bytes != null)
                    PositionedDirectional(
                      top: 4,
                      end: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onClear,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
