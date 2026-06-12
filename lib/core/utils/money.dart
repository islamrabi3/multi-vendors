import 'package:intl/intl.dart';

final _egp = NumberFormat.currency(symbol: 'EGP ', decimalDigits: 2);

String formatMoney(num amount) => _egp.format(amount);
