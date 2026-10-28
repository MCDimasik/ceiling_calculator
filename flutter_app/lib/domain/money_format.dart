// Display helpers for ruble amounts (space thousand separators).

/// Formats [value] with space as thousands separator, e.g. `1 000 000` or `10 000,50`.
String formatMoney(num value, {int fractionDigits = 0}) {
  final n = value.toDouble();
  final neg = n < 0;
  final abs = n.abs();
  final fixed = abs.toStringAsFixed(fractionDigits);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final fromEnd = intPart.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write(' ');
    buf.write(intPart[i]);
  }
  var out = buf.toString();
  if (fractionDigits > 0 && parts.length > 1) {
    out = '$out,${parts[1]}';
  }
  return neg ? '-$out' : out;
}

/// Same as [formatMoney] with ` ₽` suffix.
String formatRub(num value, {int fractionDigits = 0}) =>
    '${formatMoney(value, fractionDigits: fractionDigits)} ₽';
