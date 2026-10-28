import 'package:flutter/material.dart';

import '../../domain/ks2_room_closure_status.dart';

/// Compact legend for room closure glyphs on dashboard and KS-2 screens.
class Ks2ClosureLegend extends StatelessWidget {
  const Ks2ClosureLegend({super.key, this.padding = const EdgeInsets.fromLTRB(4, 4, 4, 0)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        roomClosureStatusLegend(),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
