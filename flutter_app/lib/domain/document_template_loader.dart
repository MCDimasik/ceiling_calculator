import 'dart:io';

import 'package:flutter/services.dart';

import 'act_export.dart';
import 'document_templates.dart';
import 'documentation_model.dart';
import 'models.dart';

String? _roomTemplatePath(Room? room, String key) {
  if (room == null) return null;
  final t = RoomExportTemplates.fromChecklistJson(room.documentationChecklistJson);
  return switch (key) {
    'ks2' => t.ks2TemplatePath,
    'act_hidden' => t.actHiddenTemplatePath,
    'vedomost' => t.vedomostTemplatePath,
    _ => null,
  };
}

Future<String> _readFileOrNull(String? path) async {
  if (path == null || path.isEmpty) return '';
  final file = File(path);
  if (!file.existsSync()) return '';
  return file.readAsString();
}

/// Load KS-2 template JSON (room override → project file → bundled asset).
Future<String> loadKs2TemplateJson(
  ProjectDocumentation doc, {
  Room? room,
}) async {
  final roomJson = await _readFileOrNull(_roomTemplatePath(room, 'ks2'));
  if (roomJson.isNotEmpty) return roomJson;
  final projectJson = await _readFileOrNull(doc.ks2TemplatePath);
  if (projectJson.isNotEmpty) return projectJson;
  return rootBundle.loadString(bundledKs2TemplateAsset);
}

/// Load KS-3 template JSON (project file → bundled asset).
Future<String> loadKs3TemplateJson(ProjectDocumentation doc) async {
  final projectJson = await _readFileOrNull(doc.ks3TemplatePath);
  if (projectJson.isNotEmpty) return projectJson;
  return rootBundle.loadString(bundledKs3TemplateAsset);
}

/// Load hidden-works act template JSON (room → project → bundled).
Future<String> loadActHiddenTemplateJson(
  ProjectDocumentation doc, {
  Room? room,
}) async {
  final roomJson = await _readFileOrNull(_roomTemplatePath(room, 'act_hidden'));
  if (roomJson.isNotEmpty) return roomJson;
  final projectJson = await _readFileOrNull(doc.actHiddenTemplatePath);
  if (projectJson.isNotEmpty) return projectJson;
  return rootBundle.loadString(bundledActHiddenTemplateAsset);
}

/// Load vedomost template JSON if configured (room → project), else null.
Future<String?> loadVedomostTemplateJson(
  ProjectDocumentation doc, {
  Room? room,
}) async {
  final roomJson = await _readFileOrNull(_roomTemplatePath(room, 'vedomost'));
  if (roomJson.isNotEmpty) return roomJson;
  return _readFileOrNull(doc.vedomostTemplatePath).then(
    (s) => s.isEmpty ? null : s,
  );
}
