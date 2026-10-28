import 'dart:typed_data';

import 'as_built_export.dart';
import 'documentation_model.dart';
import 'export_stamp_overlay.dart';
import 'floor_as_built_export.dart';
import 'models.dart';
import 'wall_as_built_export.dart';

/// Renders scheme PNG with documentation stamp band.
Future<Uint8List> renderStampedSchemePng({
  required Room room,
  required DocumentationStamp stamp,
  required AsBuiltSchemeKind scheme,
  AsBuiltExportOptions options = const AsBuiltExportOptions(),
}) async {
  final filled = stamp.withDefaults(projectName: '', roomName: room.name);
  final raw = switch (scheme) {
    AsBuiltSchemeKind.ceiling => await renderAsBuiltPng(room, options: options),
    AsBuiltSchemeKind.floor =>
      await renderFloorPlanPng(room, showWallDims: options.showWallDims),
    AsBuiltSchemeKind.walls => await renderWallFinishPng(room),
    AsBuiltSchemeKind.combined => await renderCombinedAsBuiltPng(room, options: options),
  };
  if (raw.isEmpty) return raw;
  return applyExportStamp(
    pngBytes: raw,
    stamp: filled,
    roomName: room.name,
  );
}
