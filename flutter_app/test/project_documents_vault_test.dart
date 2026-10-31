import 'package:ceiling_calculator/domain/documentation_model.dart';
import 'package:ceiling_calculator/domain/local_user_role.dart';
import 'package:ceiling_calculator/domain/project_documents_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vault JSON round-trip and role feed', () {
    final doc = ProjectDocumentation(
      certificates: [
        MaterialCertificate(
          materialKey: 'all',
          label: 'Сертификат общий',
          localPath: r'C:\tmp\cert.pdf',
          uploadedAt: DateTime(2026, 1, 1),
        ),
      ],
      vault: [
        ProjectVaultEntry(
          id: 'v1',
          category: DocumentVaultCategory.ks2,
          name: 'КС-2 № 1',
          relativePath: 'documents/1/ks2.pdf',
          createdAt: DateTime(2026, 10, 29),
          source: DocumentVaultSource.export,
        ),
        ProjectVaultEntry(
          id: 'v2',
          category: DocumentVaultCategory.smeta,
          name: 'Ведомость',
          relativePath: 'documents/1/smeta.pdf',
          createdAt: DateTime(2026, 10, 28),
          source: DocumentVaultSource.export,
        ),
      ],
    );

    final back = ProjectDocumentation.fromJson(doc.toJson());
    expect(back.vault.length, 2);
    expect(back.certificates.length, 1);

    final directorFeed = buildVaultFeed(doc, AppUserRole.director);
    expect(directorFeed.length, 3);

    final foremanFeed = buildVaultFeed(doc, AppUserRole.foreman);
    expect(foremanFeed.length, 2);
    expect(
      foremanFeed.every(
        (e) =>
            e.category == DocumentVaultCategory.smeta ||
            e.category == DocumentVaultCategory.certificate,
      ),
      isTrue,
    );
  });
}
