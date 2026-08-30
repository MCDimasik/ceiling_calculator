import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:ceiling_calculator/data/app_database.dart';
import 'package:ceiling_calculator/data/project_repository.dart';
import 'package:ceiling_calculator/domain/models.dart';

void main() {
  setUpAll(() {
    initDatabaseFactory();
  });

  late Database db;
  late ProjectRepository repo;

  setUp(() async {
    db = await openAppDatabase(inMemory: true);
    repo = ProjectRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('create and list projects', () async {
    await repo.createProject('Офис А');
    await repo.createProject('Склад');
    final list = await repo.listProjects();
    expect(list.length, 2);
    expect(list.map((p) => p.name).toSet(), {'Офис А', 'Склад'});
  });

  test('rooms CRUD and walls round-trip', () async {
    final project = await repo.createProject('Дом');
    final room = await repo.createRoom(project.id!, 'Кухня');
    expect(room.id, isNotNull);

    room.walls = [
      [0, 0, 400, 0],
      [400, 0, 400, 300],
      [400, 300, 0, 300],
      [0, 300, 0, 0],
    ];
    room.gridOffsetX = 10;
    room.gridOffsetY = 20;
    room.lightFixtures = [
      [1, 2],
      [3, 4],
    ];
    await repo.updateRoom(room);

    final loaded = await repo.getProject(project.id!);
    expect(loaded, isNotNull);
    expect(loaded!.rooms.length, 1);
    final r = loaded.rooms.first;
    expect(r.name, 'Кухня');
    expect(r.walls.length, 4);
    expect(r.walls[0][2], 400);
    expect(r.gridOffsetX, 10);
    expect(r.gridOffsetY, 20);
    expect(r.lightFixtures, [
      [1, 2],
      [3, 4],
    ]);
    expect(r.hasLayout, isTrue);

    await repo.renameRoom(r.id!, 'Гостиная');
    await repo.deleteRoom(project.id!, r.id!);
    final after = await repo.getProject(project.id!);
    expect(after!.rooms, isEmpty);
  });

  test('delete project removes rooms', () async {
    final project = await repo.createProject('Временный');
    await repo.createRoom(project.id!, 'R1');
    await repo.createRoom(project.id!, 'R2');
    await repo.deleteProject(project.id!);
    expect(await repo.getProject(project.id!), isNull);
    expect(await repo.listProjects(), isEmpty);
  });

  test('saveProject replaces rooms like Python', () async {
    final project = await repo.createProject('Пакет');
    await repo.createRoom(project.id!, 'A');
    final full = await repo.getProject(project.id!);
    full!.rooms = [Room(name: 'Only', projectId: full.id)];
    await repo.saveProject(full);
    final again = await repo.getProject(project.id!);
    expect(again!.rooms.length, 1);
    expect(again.rooms.first.name, 'Only');
  });
}
