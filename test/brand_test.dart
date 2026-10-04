import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/tokens.dart';
import 'package:multi_vendor/core/config/app_config.dart';
import 'package:multi_vendor/core/config/brand.dart';
import 'package:multi_vendor/firebase_options.dart';

/// A build with no client file must still be Kitchen IN, exactly as it was
/// before the app could be built for anybody else.
void main() {
  test('with no client file, the build is Kitchen IN', () {
    expect(Brand.id, 'kitchenin');
    expect(Brand.name, 'KitchenIN');
    expect(Brand.displayName, 'Kitchen IN');
    expect('${Brand.wordmarkLead}${Brand.wordmarkAccent}', 'KitchenIN');
    expect(Brand.hasLogoAsset, isFalse);
    expect(Brand.linkOrigin, 'https://multi-rest-app.web.app');

    expect(AppColors.primary, const Color(0xFF5C2340));
    expect(AppColors.primaryDark, const Color(0xFF431829));
    expect(AppColors.primaryLight, const Color(0xFF8F4468));
    expect(AppColors.pistachio, const Color(0xFF9DBE3F));
    expect(AppColors.onDarkPistachio, const Color(0xFFC3DE84));

    expect(AppConfig.supabaseUrl, 'https://dvfbeaafekqdcwxogbqc.supabase.co');
    expect(DefaultFirebaseOptions.web.projectId, 'multi-rest-app');
    expect(DefaultFirebaseOptions.android.projectId, 'multi-rest-app');
    expect(DefaultFirebaseOptions.ios.iosBundleId, 'com.kitchenin.app');
  });
}
