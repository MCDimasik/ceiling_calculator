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

  test('duplicate room copies geometry without checklist', () async {
    final project = await repo.createProject('Этаж 2');
    final source = await repo.createRoom(project.id!, 'Офис 201');
    source.walls = [
      [0, 0, 500, 0],
      [500, 0, 500, 400],
      [500, 400, 0, 400],
      [0, 400, 0, 0],
    ];
    source.layoutConfirmed = true;
    source.documentationChecklistJson = {'accepted': true};
    source.wallFinishLayers = [
      {'kind': 'plaster', 'enabled': true},
    ];
    await repo.updateRoom(source);

    final copy = await repo.duplicateRoom(project.id!, source, 'Офис 202');
    expect(copy.id, isNot(source.id));
    expect(copy.name, 'Офис 202');
    expect(copy.walls.length, 4);
    expect(copy.layoutConfirmed, isTrue);
    expect(copy.wallFinishLayers.length, 1);
    expect(copy.documentationChecklistJson, isNull);

    final loaded = await repo.getProject(project.id!);
    expect(loaded!.rooms.length, 2);
  });

  test('duplicate room bulk creates many rooms', () async {
    final project = await repo.createProject('Этаж 3');
    final source = await repo.createRoom(project.id!, 'Типовая');
    source.walls = [
      [0, 0, 300, 0],
      [300, 0, 300, 300],
      [300, 300, 0, 300],
      [0, 300, 0, 0],
    ];
    await repo.updateRoom(source);
    final copies = await repo.duplicateRoomBulk(
      project.id!,
      source,
      ['Офис 1', 'Офис 2', 'Офис 3'],
    );
    expect(copies.length, 3);
    final loaded = await repo.getProject(project.id!);
    expect(loaded!.rooms.length, 4);
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

  test('share payload snapshot creates project for another owner', () async {
    await repo.setActiveOwnerLogin('director');
    final project = await repo.createProject('Пархоменко 24');
    final r1 = await repo.createRoom(project.id!, 'Кабинет');
    r1.walls = [
      [0, 0, 400, 0],
      [400, 0, 400, 300],
      [400, 300, 0, 300],
      [0, 300, 0, 0],
    ];
    await repo.updateRoom(r1);
    await repo.createRoom(project.id!, 'Коридор');

    final payload = await repo.buildProjectSharePayload(
      project.id!,
      roomIds: [r1.id!],
    );
    expect(payload['room_count'], 1);
    expect(payload['snapshot'], isA<Map>());
    expect((payload['rooms_preview'] as List).length, 1);

    await repo.setActiveOwnerLogin('monter');
    expect(await repo.listProjects(force: true), isEmpty);

    final newId = await repo.applyProjectSharePayload(
      payload,
      createAsName: 'Пархоменко 24',
    );
    final list = await repo.listProjects(force: true);
    expect(list.length, 1);
    expect(list.first.id, newId);
    expect(list.first.name, 'Пархоменко 24');
    final loaded = await repo.getProject(newId);
    expect(loaded!.rooms.length, 1);
    expect(loaded.rooms.first.name, 'Кабинет');
    expect(loaded.rooms.first.walls.length, 4);
  });

  test('share merge into renamed existing project', () async {
    await repo.setActiveOwnerLogin('director');
    final src = await repo.createProject('Объект А');
    final room = await repo.createRoom(src.id!, 'Зал');
    room.walls = [
      [0, 0, 200, 0],
      [200, 0, 200, 200],
      [200, 200, 0, 200],
      [0, 200, 0, 0],
    ];
    await repo.updateRoom(room);
    final payload = await repo.buildProjectSharePayload(src.id!);

    await repo.setActiveOwnerLogin('monter');
    final local = await repo.createProject('Моё имя объекта');
    await repo.createRoom(local.id!, 'Уже было');

    await repo.applyProjectSharePayload(
      payload,
      intoProjectId: local.id,
    );
    final loaded = await repo.getProject(local.id!);
    expect(loaded!.rooms.map((r) => r.name).toSet(), {'Уже было', 'Зал'});
  });
}
