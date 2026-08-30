import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const dbFileName = 'ceiling_calculator.db';

bool _ffiInitialized = false;

/// Call once at startup (desktop + tests). Safe to call multiple times.
void initDatabaseFactory() {
  if (_ffiInitialized) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _ffiInitialized = true;
}

Future<String> defaultDatabasePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, dbFileName);
}

Future<Database> openAppDatabase({String? path, bool inMemory = false}) async {
  initDatabaseFactory();
  // Unique in-memory name so parallel/sequential tests never share state.
  final dbPath = inMemory
      ? 'file:mem_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(Object())}?mode=memory&cache=private'
      : (path ?? await defaultDatabasePath());
  return openDatabase(
    dbPath,
    version: 1,
    singleInstance: !inMemory,
    onCreate: (db, version) async {
      await _createSchema(db);
    },
    onOpen: (db) async {
      await _ensureMigrations(db);
    },
  );
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      materials_ceiling TEXT,
      materials_susp TEXT,
      materials_cell TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS rooms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      walls_json TEXT NOT NULL,
      last_position_json TEXT,
      grid_offset_x INTEGER DEFAULT 0,
      grid_offset_y INTEGER DEFAULT 0,
      materials_override INTEGER DEFAULT 0,
      materials_ceiling TEXT,
      materials_susp TEXT,
      materials_cell TEXT,
      light_fixtures_json TEXT,
      FOREIGN KEY (project_id) REFERENCES projects (id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS supplier_prices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      supplier_id INTEGER NOT NULL,
      item_key TEXT NOT NULL,
      product_name TEXT NOT NULL,
      unit_price REAL NOT NULL DEFAULT 0,
      unit_price_cost REAL NOT NULL DEFAULT 0,
      unit_price_client REAL NOT NULL DEFAULT 0,
      receipt_unit TEXT NOT NULL DEFAULT 'piece',
      units_per_pack REAL NOT NULL DEFAULT 1,
      FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE,
      UNIQUE(supplier_id, item_key)
    )
  ''');
}

Future<void> _ensureMigrations(Database db) async {
  const alters = [
    'ALTER TABLE projects ADD COLUMN materials_ceiling TEXT',
    'ALTER TABLE projects ADD COLUMN materials_susp TEXT',
    'ALTER TABLE projects ADD COLUMN materials_cell TEXT',
    'ALTER TABLE rooms ADD COLUMN materials_override INTEGER DEFAULT 0',
    'ALTER TABLE rooms ADD COLUMN materials_ceiling TEXT',
    'ALTER TABLE rooms ADD COLUMN materials_susp TEXT',
    'ALTER TABLE rooms ADD COLUMN materials_cell TEXT',
    'ALTER TABLE rooms ADD COLUMN light_fixtures_json TEXT',
    'ALTER TABLE rooms ADD COLUMN grid_offset_x INTEGER DEFAULT 0',
    'ALTER TABLE rooms ADD COLUMN grid_offset_y INTEGER DEFAULT 0',
    'ALTER TABLE rooms ADD COLUMN layout_view_json TEXT',
    'ALTER TABLE rooms ADD COLUMN ceiling_height_cm REAL DEFAULT 270',
    'ALTER TABLE rooms ADD COLUMN finish_tile_size_cm REAL DEFAULT 60',
    'ALTER TABLE rooms ADD COLUMN finish_tile_width_cm REAL',
    'ALTER TABLE rooms ADD COLUMN finish_tile_height_cm REAL',
    'ALTER TABLE rooms ADD COLUMN floor_grid_offset_x INTEGER DEFAULT 0',
    'ALTER TABLE rooms ADD COLUMN floor_grid_offset_y INTEGER DEFAULT 0',
    'ALTER TABLE rooms ADD COLUMN openings_json TEXT',
    'ALTER TABLE rooms ADD COLUMN wall_finish_layers_json TEXT',
    'ALTER TABLE rooms ADD COLUMN floor_covering_kind TEXT DEFAULT \'tile\'',
    'ALTER TABLE rooms ADD COLUMN floor_laying_pattern TEXT DEFAULT \'straight\'',
    'ALTER TABLE rooms ADD COLUMN floor_layout_rotation_deg INTEGER DEFAULT 0',
    'ALTER TABLE projects ADD COLUMN master_plan_json TEXT',
    'ALTER TABLE rooms ADD COLUMN layout_confirmed INTEGER DEFAULT 0',
    'ALTER TABLE rooms ADD COLUMN ceiling_guides_json TEXT',
    'ALTER TABLE supplier_prices ADD COLUMN unit_price_cost REAL NOT NULL DEFAULT 0',
    'ALTER TABLE supplier_prices ADD COLUMN unit_price_client REAL NOT NULL DEFAULT 0',
    'ALTER TABLE supplier_prices ADD COLUMN receipt_unit TEXT NOT NULL DEFAULT \'piece\'',
    'ALTER TABLE supplier_prices ADD COLUMN units_per_pack REAL NOT NULL DEFAULT 1',
  ];
  for (final ddl in alters) {
    try {
      await db.execute(ddl);
    } catch (_) {}
  }
}
