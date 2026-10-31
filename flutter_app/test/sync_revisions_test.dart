import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ceiling_calculator/domain/sync_revisions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remoteWins: newer or equal UTC wins; older / null remote lose', () {
    final older = DateTime.utc(2026, 1, 1, 12);
    final newer = DateTime.utc(2026, 1, 1, 13);
    expect(SyncRevisions.remoteWins(null, newer), isTrue);
    expect(SyncRevisions.remoteWins(older, newer), isTrue);
    expect(SyncRevisions.remoteWins(newer, older), isFalse);
    expect(SyncRevisions.remoteWins(newer, newer), isTrue);
    expect(SyncRevisions.remoteWins(newer, null), isFalse);
  });

  test('touch is monotonic UTC', () async {
    final a = await SyncRevisions.touch('k');
    final b = await SyncRevisions.touch('k');
    expect(b.isAfter(a) || b.isAtSameMomentAs(a.add(const Duration(milliseconds: 1))),
        isTrue);
    final stored = await SyncRevisions.get('k');
    expect(stored!.isUtc, isTrue);
  });
}
