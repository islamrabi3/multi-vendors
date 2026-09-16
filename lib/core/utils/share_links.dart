import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vendor.dart';
import 'l10n_extension.dart';

/// Where shared links point. The same address opens the web app in a browser
/// and, on a phone with the app installed, opens the app itself (Android App
/// Links / iOS Universal Links, verified by the files in `web/.well-known`).
const appLinkOrigin = 'https://multi-rest-app.web.app';

Uri vendorShareUri(String vendorId) =>
    Uri.parse('$appLinkOrigin/vendors/$vendorId');

/// Opens the system share sheet with a link to [vendor]'s page.
Future<void> shareVendor(BuildContext context, Vendor vendor) async {
  final l10n = context.l10n;
  // iPad presents the sheet as a popover and needs an anchor.
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final link = vendorShareUri(vendor.id);
  await SharePlus.instance.share(
    ShareParams(
      text: '${l10n.shareVendorMessage(vendor.name)}\n$link',
      subject: vendor.name,
      sharePositionOrigin: origin,
    ),
  );
}
