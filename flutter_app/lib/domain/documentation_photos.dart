import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pick a photo (camera on mobile, file on desktop) and store under app docs.
Future<String?> pickAndStoreDocumentationPhoto({
  required int projectId,
  required int roomId,
  required String stepId,
  bool preferCamera = true,
}) async {
  String? sourcePath;

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && preferCamera) {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      sourcePath = x?.path;
    } catch (_) {
      sourcePath = null;
    }
  }

  sourcePath ??= await _pickImageFile();

  if (sourcePath == null) return null;

  final dir = await getApplicationDocumentsDirectory();
  final destDir = Directory(
    p.join(dir.path, 'doc_photos', '$projectId', '$roomId', stepId),
  );
  await destDir.create(recursive: true);
  final name = '${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}';
  final dest = File(p.join(destDir.path, name));
  await File(sourcePath).copy(dest.path);
  return dest.path;
}

Future<String?> _pickImageFile() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    allowMultiple: false,
  );
  if (files.isEmpty) return null;
  return files.first.path;
}

/// Remove stored photo file and return updated path list.
Future<List<String>> removeDocumentationPhoto(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
  return [];
}

String photoCaptionFromPath(String path) {
  final name = p.basename(path);
  final match = RegExp(r'^(\d+)').firstMatch(name);
  if (match != null) {
    final ms = int.tryParse(match.group(1)!);
    if (ms != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
  return name;
}
