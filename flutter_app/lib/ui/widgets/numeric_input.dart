import 'package:flutter/services.dart';

/// Shared keyboard + filters: digits for sizes, text for names.
abstract final class NumericInput {
  static const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);
  static const integerKeyboard = TextInputType.number;
  static const textKeyboard = TextInputType.text;

  /// Allows digits and one decimal separator (`.` or `,`).
  static final decimalFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  static final integerFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
  ];
}
