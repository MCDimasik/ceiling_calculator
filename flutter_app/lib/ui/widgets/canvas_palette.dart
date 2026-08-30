import 'package:flutter/material.dart';

/// Fixed dark canvas palette (Kivy `_LAYOUT_REDESIGN` / `_EDITOR_REDESIGN`).
/// Layout and room editor always use this, independent of app theme.
abstract final class CanvasPalette {
  static const bg = Color.fromRGBO(31, 33, 33, 1); // 0.12, 0.13, 0.13
  static const wall = Color.fromRGBO(240, 245, 250, 1); // 0.94, 0.96, 0.98
  static const roomFill = Color.fromRGBO(82, 97, 107, 1); // 0.32, 0.38, 0.42
  static const grid = Color.fromRGBO(201, 214, 222, 0.7); // 0.79, 0.84, 0.87, 0.7
  static const fullTile = Color.fromRGBO(230, 230, 230, 0.3);
  static const cutTile = Color.fromRGBO(179, 179, 179, 0.3);
  static const text = Color.fromRGBO(240, 245, 250, 1);
  static const closingLine = Color.fromRGBO(201, 214, 222, 1);
  static const cursor = Color.fromRGBO(240, 245, 250, 1);
  static const light = Color(0xFFFFEB3B);
}
