import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

/// What tapping an ad does.
enum AdDestinationKind { none, store, page, link }

/// The ad's tap target, as the composer edits it and the row stores it:
/// a store goes in `vendor_id`, a page or a link in `link_url`.
class AdDestination {
  const AdDestination.none()
    : kind = AdDestinationKind.none,
      vendorId = null,
      vendorName = null,
      route = null;
  const AdDestination.store(this.vendorId, this.vendorName)
    : kind = AdDestinationKind.store,
      route = null;
  const AdDestination.page(this.route)
    : kind = AdDestinationKind.page,
      vendorId = null,
      vendorName = null;
  const AdDestination.link(this.route)
    : kind = AdDestinationKind.link,
      vendorId = null,
      vendorName = null;

  final AdDestinationKind kind;
  final String? vendorId;
  final String? vendorName;

  /// In-app path for [AdDestinationKind.page], URL for
  /// [AdDestinationKind.link].
  final String? route;

  factory AdDestination.fromAd({String? vendorId, String? linkUrl}) {
    if (vendorId != null && vendorId.isNotEmpty) {
      return AdDestination.store(vendorId, null);
    }
    final link = linkUrl?.trim() ?? '';
    if (link.isEmpty) return const AdDestination.none();
    if (link.startsWith('/')) return AdDestination.page(link);
    return AdDestination.link(link);
  }

  String? get vendorIdToSave =>
      kind == AdDestinationKind.store ? vendorId : null;

  String? get linkToSave =>
      kind == AdDestinationKind.page || kind == AdDestinationKind.link
      ? route
      : null;

  /// Null when complete; otherwise the message to show.
  String? validate(BuildContext context) {
    final l10n = context.l10n;
    switch (kind) {
      case AdDestinationKind.none:
        return null;
      case AdDestinationKind.store:
        return vendorId == null ? l10n.adPickStoreRequired : null;
      case AdDestinationKind.page:
        return (route ?? '').isEmpty ? l10n.adPickPageRequired : null;
      case AdDestinationKind.link:
        final uri = Uri.tryParse(route ?? '');
        final ok =
            uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty;
        return ok ? null : l10n.adLinkInvalid;
    }
  }
}

/// The fixed in-app pages an ad can open. Categories are listed after these.
List<(String, String, IconData)> _pages(BuildContext context) {
  final l10n = context.l10n;
  return [
    ('/home', l10n.home, Icons.home_rounded),
    ('/search', l10n.searchPageLabel, Icons.search_rounded),
    ('/cart', l10n.cartPageLabel, Icons.shopping_cart_rounded),
    ('/orders', l10n.orders, Icons.receipt_long_rounded),
    ('/favorites', l10n.favorites, Icons.favorite_rounded),
    ('/messages', l10n.messagesTitle, Icons.chat_bubble_rounded),
    ('/profile', l10n.profile, Icons.person_rounded),
  ];
}

class AdDestinationField extends StatefulWidget {
  const AdDestinationField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AdDestination value;
  final ValueChanged<AdDestination> onChanged;

  @override
  State<AdDestinationField> createState() => _AdDestinationFieldState();
}

class _AdDestinationFieldState extends State<AdDestinationField> {
  final _admin = AdminRepository();
  late final _link = TextEditingController(
    text: widget.value.kind == AdDestinationKind.link ? widget.value.route : '',
  );
  List<VendorCategory> _categories = const [];

  /// The store's name and logo, looked up when an existing ad is opened.
  Vendor? _vendor;

  @override
  void initState() {
    super.initState();
    _admin.fetchVendorCategories().then((list) {
      if (mounted) setState(() => _categories = list);
    }, onError: (_) {});
    final id = widget.value.vendorId;
    if (id != null) {
      _admin.fetchVendor(id).then((v) {
        if (mounted) setState(() => _vendor = v);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickStore() async {
    final picked = await pickActiveStore(context);
    if (picked == null) return;
    setState(() => _vendor = picked);
    widget.onChanged(AdDestination.store(picked.id, picked.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = widget.value;
    final language = Localizations.localeOf(context).languageCode;
    final pages = _pages(context);

    final kinds = [
      (AdDestinationKind.none, l10n.adTapNothing, Icons.block_rounded),
      (AdDestinationKind.store, l10n.store, Icons.storefront_rounded),
      (AdDestinationKind.page, l10n.adTapAppPage, Icons.phone_iphone_rounded),
      (
        AdDestinationKind.link,
        l10n.adTapExternalLink,
        Icons.open_in_new_rounded,
      ),
    ];

    final Widget detail;
    switch (value.kind) {
      case AdDestinationKind.none:
        detail = Text(
          l10n.adTapNothingHint,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        );
      case AdDestinationKind.store:
        detail = InkWell(
          onTap: _pickStore,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                if (_vendor != null)
                  AppNetworkImage(
                    url: _vendor!.logoUrl,
                    width: 40,
                    height: 40,
                    borderRadius: BorderRadius.circular(10),
                  )
                else
                  const Icon(Icons.search_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _vendor?.name ?? value.vendorName ?? l10n.adPickStore,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _vendor == null
                          ? AppColors.textMuted
                          : AppColors.ink,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textFaint,
                ),
              ],
            ),
          ),
        );
      case AdDestinationKind.page:
        final known =
            pages.any((p) => p.$1 == value.route) ||
            _categories.any((c) => '/categories/${c.id}' == value.route);
        detail = DropdownButtonFormField<String>(
          key: ValueKey('page-${_categories.length}'),
          initialValue: value.route,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.adTapAppPage),
          items: [
            for (final (route, label, icon) in pages)
              DropdownMenuItem(
                value: route,
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Text(label),
                  ],
                ),
              ),
            for (final c in _categories)
              DropdownMenuItem(
                value: '/categories/${c.id}',
                child: Row(
                  children: [
                    const Icon(
                      Icons.category_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${l10n.categoriesTab}: ${c.label(language)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // An older ad may point at a path not in the list; keep it.
            if (value.route != null && !known)
              DropdownMenuItem(value: value.route, child: Text(value.route!)),
          ],
          onChanged: (route) {
            if (route != null) widget.onChanged(AdDestination.page(route));
          },
        );
      case AdDestinationKind.link:
        detail = TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: l10n.adTapExternalLink,
            hintText: 'https://',
            prefixIcon: const Icon(Icons.link_rounded),
          ),
          onChanged: (v) => widget.onChanged(AdDestination.link(v.trim())),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.adWhenTapped,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kind, label, icon) in kinds)
              ChoiceChip(
                avatar: Icon(
                  icon,
                  size: 16,
                  color: value.kind == kind
                      ? Colors.white
                      : AppColors.textMuted,
                ),
                label: Text(label),
                selected: value.kind == kind,
                showCheckmark: false,
                onSelected: (_) {
                  switch (kind) {
                    case AdDestinationKind.none:
                      widget.onChanged(const AdDestination.none());
                    case AdDestinationKind.store:
                      widget.onChanged(
                        AdDestination.store(_vendor?.id, _vendor?.name),
                      );
                      if (_vendor == null) _pickStore();
                    case AdDestinationKind.page:
                      widget.onChanged(const AdDestination.page('/home'));
                    case AdDestinationKind.link:
                      widget.onChanged(AdDestination.link(_link.text.trim()));
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        detail,
      ],
    );
  }
}

/// Search every active store by name and pick one.
/// Searches active stores by name and returns the one tapped. Shared by the
/// ad and promo forms so both pick a store the same way.
Future<Vendor?> pickActiveStore(BuildContext context) =>
    showAdaptiveSheet<Vendor>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      maxWidth: 520,
      builder: (_) => const _StorePicker(),
    );

class _StorePicker extends StatefulWidget {
  const _StorePicker();

  @override
  State<_StorePicker> createState() => _StorePickerState();
}

class _StorePickerState extends State<_StorePicker> {
  final _admin = AdminRepository();
  final _search = TextEditingController();
  Timer? _debounce;
  List<Vendor>? _results;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String query) async {
    try {
      final list = await _admin.fetchVendorsPage(
        limit: 30,
        offset: 0,
        status: 'active',
        search: query,
      );
      if (mounted && _search.text == query) setState(() => _results = list);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: l10n.adSearchStoreHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: results == null
                  ? const LoadingView()
                  : results.isEmpty
                  ? EmptyView(
                      message: l10n.noResultsFor(_search.text),
                      icon: Icons.storefront_outlined,
                    )
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        indent: 72,
                        color: AppColors.borderSoft,
                      ),
                      itemBuilder: (context, i) {
                        final v = results[i];
                        return ListTile(
                          leading: AppNetworkImage(
                            url: v.logoUrl,
                            width: 44,
                            height: 44,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          title: Text(
                            v.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: v.addressText == null
                              ? null
                              : Text(
                                  v.addressText!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(context, v),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
