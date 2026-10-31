import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:ceiling_calculator/data/app_database.dart';
import 'package:ceiling_calculator/data/project_repository.dart';
import 'package:ceiling_calculator/data/supplier_repository.dart';
import 'package:ceiling_calculator/domain/cost_calculator.dart';
import 'package:ceiling_calculator/domain/local_user_role.dart';
import 'package:ceiling_calculator/domain/offline_device_sync.dart';
import 'package:ceiling_calculator/domain/sync_revisions.dart';
import 'package:ceiling_calculator/domain/work_rates_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    initDatabaseFactory();
  });

  late Database db;
  late ProjectRepository projects;
  late SupplierRepository suppliers;
  late LocalUserController user;
  late OfflineDeviceSyncController offline;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openAppDatabase(inMemory: true);
    projects = ProjectRepository(db);
    suppliers = SupplierRepository(db);
    user = LocalUserController();
    await user.load();
    // Ensure director-capable session for gate (demo profiles seeded in load).
    await user.signIn(
      login: 'director',
      password: kLocalDemoPassword,
    );
    await projects.setActiveOwnerLogin('director');
    offline = OfflineDeviceSyncController(
      projects: projects,
      suppliers: suppliers,
      user: user,
      transfers: null,
    );
    await offline.load();
  });

  tearDown(() async {
    await offline.stopHosting();
    await db.close();
  });

  test('canOfflineDeviceSync only director/admin', () {
    expect(AppUserRole.director.canOfflineDeviceSync, isTrue);
    expect(AppUserRole.superAdmin.canOfflineDeviceSync, isTrue);
    expect(AppUserRole.foreman.canOfflineDeviceSync, isFalse);
    expect(AppUserRole.installer.canOfflineDeviceSync, isFalse);
  });

  test('bundle round-trip merges projects and materials', () async {
    final p = await projects.createProject('Офлайн объект');
    await projects.createRoom(p.id!, 'Кабинет');
    await WorkRatesCatalogStore.save(seedWorkRatesCatalog());
    final s = await suppliers.createSupplier('ОфлайнСклад');
    await suppliers.upsertPrice(
      s.id!,
      SupplierPrice(
        itemKey: 'armstrong_tile',
        productName: 'Плита',
        unitPriceClient: 42,
      ),
    );

    final bundle = await offline.buildBundle();
    expect(bundle['kind'], 'offline_device_bundle');
    expect((bundle['projects'] as List).isNotEmpty, isTrue);

    // Wipe local project list side-effect: apply into fresh owner clone path —
    // delete and re-apply by name merge.
    await projects.deleteProject(p.id!);
    expect((await projects.listProjects()).any((x) => x.name == 'Офлайн объект'),
        isFalse);

    final note = await offline.applyBundle(bundle);
    expect(note.contains('объекты'), isTrue);
    final list = await projects.listProjects();
    expect(list.any((x) => x.name == 'Офлайн объект'), isTrue);

    final prices = await suppliers.listPrices(s.id!);
    expect(
      prices.firstWhere((e) => e.itemKey == 'armstrong_tile').unitPriceClient,
      42,
    );
  });

  test('LWW skips older project payload', () async {
    final p = await projects.createProject('LWW объект');
    await projects.createRoom(p.id!, 'А');
    await SyncRevisions.touch(
      SyncRevisions.projectKey('LWW объект'),
      at: DateTime.utc(2026, 6, 1, 12),
    );

    final stale = await projects.buildProjectSharePayload(p.id!);
    stale['updated_at'] = DateTime.utc(2026, 5, 1).toIso8601String();
    stale['project_name'] = 'LWW объект';

    // Bump local newer than stale remote.
    await SyncRevisions.set(
      SyncRevisions.projectKey('LWW объект'),
      DateTime.utc(2026, 6, 2, 12),
    );

    final note = await offline.applyBundle({
      'kind': 'offline_device_bundle',
      'version': 2,
      'projects': [stale],
      'work_rates': {},
      'kits': [],
      'suppliers': [],
    });
    expect(note.contains('пропуск'), isTrue);
  });
}
