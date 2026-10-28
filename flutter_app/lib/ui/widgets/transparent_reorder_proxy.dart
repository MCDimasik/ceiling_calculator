import 'package:flutter/material.dart';

/// Drag proxy without Material elevation / tint flash.
Widget transparentReorderProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return Material(
    type: MaterialType.transparency,
    color: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    child: child,
  );
}
