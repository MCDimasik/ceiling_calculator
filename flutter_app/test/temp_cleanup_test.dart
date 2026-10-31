import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ceiling_calculator/domain/temp_cleanup.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.temp);

  final String temp;

  @override
  Future<String?> getTemporaryPath() async => temp;

  @override
  Future<String?> getApplicationSupportPath() async => temp;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('visota_cleanup_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('purgeVisotaTempFiles removes matching exports, keeps others', () async {
    final kill = File(p.join(tempDir.path, 'visota_offline_x.json'));
    final keep = File(p.join(tempDir.path, 'notes.txt'));
    await kill.writeAsString('{}');
    await keep.writeAsString('hi');

    final n = await purgeVisotaTempFiles();
    expect(n, greaterThanOrEqualTo(1));
    expect(await kill.exists(), isFalse);
    expect(await keep.exists(), isTrue);
  });

  test('purgeOldUpdatePackages keeps only current installer', () async {
    final updates = Directory(p.join(tempDir.path, 'updates'));
    await updates.create(recursive: true);
    final old = File(p.join(updates.path, 'CeilingCalculator-3.0.0.apk'));
    final neu = File(p.join(updates.path, 'CeilingCalculator-3.0.1.apk'));
    await old.writeAsBytes([1]);
    await neu.writeAsBytes([2]);

    final n = await purgeOldUpdatePackages(keepPath: neu.path);
    expect(n, 1);
    expect(await old.exists(), isFalse);
    expect(await neu.exists(), isTrue);
  });
}
