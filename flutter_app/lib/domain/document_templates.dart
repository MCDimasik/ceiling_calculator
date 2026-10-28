import 'act_export.dart';

/// Bundled JSON template assets (customizable per project via file copy).
const bundledVedomostTemplateAsset =
    'assets/document_templates/_example.vedomost.template.json';

const bundledKs2TemplateAsset = defaultKs2TemplateAsset;
const bundledKs3TemplateAsset = defaultKs3TemplateAsset;
const bundledActHiddenTemplateAsset = defaultActHiddenTemplateAsset;

const bundledKs2ReferenceAsset =
    'assets/document_templates/avangard.ks2.reference.xls';
const bundledKs3ReferenceAsset =
    'assets/document_templates/avangard.ks3.reference.xls';

/// OOXML blanks for exact Avangard form fill (converted from reference .xls).
const bundledKs2BlankAsset =
    'assets/document_templates/avangard.ks2.blank.xlsx';
const bundledKs3BlankAsset =
    'assets/document_templates/avangard.ks3.blank.xlsx';

/// Resolves template JSON: project path if set, otherwise bundled asset via [loadBundled].
Future<String> resolveTemplateJson({
  required String? projectPath,
  required String bundledAsset,
  required Future<String> Function(String asset) loadBundled,
}) async {
  if (projectPath != null && projectPath.isNotEmpty) {
    return loadBundled(projectPath);
  }
  return loadBundled(bundledAsset);
}
