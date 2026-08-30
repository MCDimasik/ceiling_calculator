import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/project_repository.dart';
import 'models.dart';
import 'project_export.dart';

Future<File> writeExportFile(Project project, {List<Room>? rooms}) async {
  final dir = await getTemporaryDirectory();
  final base = safeExportBasename(
    rooms != null && rooms.length == 1 ? rooms.first.name : project.name,
  );
  final file = File(p.join(dir.path, '$base$fileExtension'));
  await file.writeAsString(encodeProjectFile(project, rooms: rooms), encoding: utf8);
  return file;
}

Future<bool> shareProject(Project project, {List<Room>? rooms}) async {
  final file = await writeExportFile(project, rooms: rooms);
  final result = await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: project.name),
  );
  return result.status != ShareResultStatus.dismissed;
}

Future<Project?> pickAndReadProjectFile() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['ccproj', 'json'],
    allowMultiple: false,
  );
  if (files.isEmpty) return null;
  final f = files.first;
  final bytes = await f.readAsBytes();
  final raw = utf8.decode(bytes);
  return decodeProjectFile(raw);
}

Future<Project?> importProjectFile(ProjectRepository repo) async {
  final project = await pickAndReadProjectFile();
  if (project == null) return null;
  await repo.saveProject(project);
  return project;
}
