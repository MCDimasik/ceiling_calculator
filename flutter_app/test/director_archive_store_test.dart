import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ceiling_calculator/domain/director_archive_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DirectorArchiveStore.clearCache();
  });

  test('add category persists in meta', () async {
    final cat = await DirectorArchiveStore.addCategory('КС-тесты');
    expect(cat.title, 'КС-тесты');
    final meta = await DirectorArchiveStore.categoriesMeta();
    expect(meta.any((m) => m['title'] == 'КС-тесты'), isTrue);
  });
}
