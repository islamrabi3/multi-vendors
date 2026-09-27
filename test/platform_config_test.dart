import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/platform_config.dart';
import 'package:multi_vendor/core/services/platform_config_service.dart';
import 'package:multi_vendor/core/utils/money.dart';

void main() {
  group('DeliveryFeeRule mirrors compute_delivery_fee', () {
    const rule = DeliveryFeeRule(
      mode: DeliveryFeeRule.distanceMode,
      baseFee: 20,
      baseKm: 10,
      perKmFee: 3,
    );

    test('store mode charges the store fee whatever the distance', () {
      const store = DeliveryFeeRule();
      expect(store.feeFor(storeFee: 25, km: 40), 25);
    });

    test('inside the base distance costs the base fee', () {
      expect(rule.feeFor(storeFee: 99, km: 0), 20);
      expect(rule.feeFor(storeFee: 99, km: 10), 20);
    });

    test('every started kilometre past it counts', () {
      expect(rule.feeFor(storeFee: 99, km: 10.2), 23);
      expect(rule.feeFor(storeFee: 99, km: 13.34), 32);
    });

    test('no pin charges the base fee', () {
      expect(rule.feeFor(storeFee: 99), 20);
    });

    test('the starting fee is what a store card can promise', () {
      expect(rule.startingFee(99), 20);
      expect(const DeliveryFeeRule().startingFee(25), 25);
    });
  });

  test('distanceKm agrees with the server within a metre', () {
    // Same pair the server reported as 13.34 km.
    expect(distanceKm(30.0, 31.2, 30.12, 31.2), closeTo(13.34, 0.01));
  });

  group('money follows the platform currency', () {
    tearDown(
      () =>
          PlatformConfigService.instance.config.value = const PlatformConfig(),
    );

    test('EGP by default', () {
      expect(formatMoney(12.5), 'EGP 12.50');
    });

    test('an admin-chosen currency and its decimals', () {
      PlatformConfigService.instance.config.value = const PlatformConfig(
        currency: AppCurrency(
          code: 'KWD',
          name: 'Kuwaiti Dinar',
          symbol: 'KWD',
          decimals: 3,
        ),
      );
      expect(formatMoney(1.5), 'KWD 1.500');
      expect(formatMoneyCompact(2), 'KWD 2');
    });
  });
}
