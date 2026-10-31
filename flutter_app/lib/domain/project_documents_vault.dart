import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/project_repository.dart';
import 'documentation_model.dart';
import 'local_user_role.dart';
import 'models.dart';

extension DocumentVaultCategoryAccess on DocumentVaultCategory {
  /// Foreman: ведомости / схемы / сертификаты / прочее (без полного док-пака).
  bool visibleFor(AppUserRole role) {
    if (role.canDocumentation) return true;
    return switch (this) {
      DocumentVaultCategory.smeta ||
      DocumentVaultCategory.scheme ||
      DocumentVaultCategory.certificate ||
      DocumentVaultCategory.other =>
        role.canFinishVedomost,
      _ => false,
    };
  }
}

Future<Directory> projectVaultDir(int projectId) async {
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(root.path, 'documents', '$projectId'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<String> resolveVaultAbsolutePath(ProjectVaultEntry entry) async {
  if (entry.absolutePathHint != null &&
      File(entry.absolutePathHint!).existsSync()) {
    return entry.absolutePathHint!;
  }
  if (p.isAbsolute(entry.relativePath) &&
      File(entry.relativePath).existsSync()) {
    return entry.relativePath;
  }
  final root = await getApplicationDocumentsDirectory();
  return p.join(root.path, entry.relativePath);
}

String _newVaultId() {
  final r = Random();
  return '${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(1 << 20)}';
}

/// Copy/write bytes into vault folder and append entry to [doc.vault].
Future<ProjectVaultEntry> appendVaultBytes({
  required ProjectDocumentation doc,
  required int projectId,
  required DocumentVaultCategory category,
  required String displayName,
  required List<int> bytes,
  String extension = '.pdf',
  DocumentVaultSource source = DocumentVaultSource.export,
  int? roomId,
}) async {
  final dir = await projectVaultDir(projectId);
  final safeExt = extension.startsWith('.') ? extension : '.$extension';
  final fileName =
      '${category.name}_${DateTime.now().millisecondsSinceEpoch}$safeExt';
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  final relative = p.join('documents', '$projectId', fileName);
  final entry = ProjectVaultEntry(
    id: _newVaultId(),
    category: category,
    name: displayName,
    relativePath: relative.replaceAll('\\', '/'),
    createdAt: DateTime.now(),
    source: source,
    roomId: roomId,
    absolutePathHint: file.path,
  );
  doc.vault = [...doc.vault, entry];
  return entry;
}

/// Copy an existing file into the vault (e.g. after temp export).
Future<ProjectVaultEntry> appendVaultFile({
  required ProjectDocumentation doc,
  required int projectId,
  required DocumentVaultCategory category,
  required String displayName,
  required String sourcePath,
  DocumentVaultSource source = DocumentVaultSource.export,
  int? roomId,
}) async {
  final bytes = await File(sourcePath).readAsBytes();
  final ext = p.extension(sourcePath);
  return appendVaultBytes(
    doc: doc,
    projectId: projectId,
    category: category,
    displayName: displayName,
    bytes: bytes,
    extension: ext.isEmpty ? '.bin' : ext,
    source: source,
    roomId: roomId,
  );
}

/// Persist vault entry after export and save documentation JSON.
Future<ProjectVaultEntry?> registerExportInVault({
  required ProjectRepository projects,
  required Project project,
  required DocumentVaultCategory category,
  required String displayName,
  required String sourcePath,
  int? roomId,
}) async {
  final id = project.id;
  if (id == null) return null;
  if (!File(sourcePath).existsSync()) return null;
  final doc = ProjectDocumentation.fromJson(project.documentationJson);
  final entry = await appendVaultFile(
    doc: doc,
    projectId: id,
    category: category,
    displayName: displayName,
    sourcePath: sourcePath,
    source: DocumentVaultSource.export,
    roomId: roomId,
  );
  project.documentationJson = doc.toJson();
  await projects.updateProjectDocumentation(id, documentationJson: doc.toJson());
  return entry;
}

/// Certificates as vault feed rows (virtual — files stay at cert paths).
List<ProjectVaultEntry> certificateVaultRows(ProjectDocumentation doc) {
  return [
    for (final c in doc.certificates)
      ProjectVaultEntry(
        id: 'cert_${c.materialKey}_${c.localPath.hashCode}',
        category: DocumentVaultCategory.certificate,
        name: c.label.isEmpty ? c.materialKey : c.label,
        relativePath: c.localPath,
        createdAt: c.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        source: DocumentVaultSource.certificate,
        absolutePathHint: c.localPath,
      ),
  ];
}

/// Merged feed: vault files + certificates, newest first, role-filtered.
List<ProjectVaultEntry> buildVaultFeed(
  ProjectDocumentation doc,
  AppUserRole role,
) {
  final all = [...doc.vault, ...certificateVaultRows(doc)];
  final filtered = all.where((e) => e.category.visibleFor(role)).toList();
  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return filtered;
}
