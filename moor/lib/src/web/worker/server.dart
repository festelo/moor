import 'dart:typed_data';

import 'package:moor/backends.dart';
import 'package:moor/moor.dart';
import 'package:moor/moor_web.dart';
import 'package:moor/src/web/worker/connector.dart';
import '../sql_js.dart';

class MoorWorkerServer {
  SqlJsDatabase _db;
  MoorWebStorage storage;
  final MoorConnector _client;
  MoorWorkerServer(this._client);

  Future<void> open(
    MoorWebStorageFactory storageFactory,
  ) async {
    storage = storageFactory.build();
    await storage.open();
    var restored = await storage.restore();

    if (restored == null) {
      restored = await _client.exec<Uint8List>('init');
      if (restored != null) {
        await storage.store(restored);
      }
    }

    final module = await initSqlJs();
    _db = module.createDatabase(restored);
  }

  Future<void> runBatched(List<String> statements,
      List<ArgumentsForBatchedStatement> arguments) async {
    final preparedStatements = [
      for (final stmt in statements) _db.prepare(stmt),
    ];

    for (final application in arguments) {
      final stmt = preparedStatements[application.statementIndex];

      stmt
        ..executeWith(application.arguments)
        ..step();
    }

    for (final prepared in preparedStatements) {
      prepared.free();
    }
    return _handlePotentialUpdate();
  }

  void runCustom(String statement, List args) {
    _db.runWithArgs(statement, args);
  }

  Future<int> runInsert(String statement, List args) async {
    _db.runWithArgs(statement, args);
    final insertId = _db.lastInsertId();
    await _handlePotentialUpdate();
    return insertId;
  }

  Future<List<Map<String, dynamic>>> runSelect(
      String statement, List args) async {
    // todo at least for stream queries we should cache prepared statements.
    final stmt = _db.prepare(statement)..executeWith(args);

    List<String> columnNames;
    final rows = <List<dynamic>>[];

    while (stmt.step()) {
      columnNames ??= stmt.columnNames();
      rows.add(stmt.currentRow());
    }

    columnNames ??= []; // assume no column names when there were no rows

    stmt.free();
    final res = QueryResult(columnNames, rows);
    return res.asMap.toList();
  }

  Future<int> runUpdate(String statement, List args) async {
    _db.runWithArgs(statement, args);
    return _handlePotentialUpdate();
  }

  Future<void> close() async {
    await storeDb();
    _db?.close();
    await storage.close();
  }

  /// Saves the database if the last statement changed rows. As a side-effect,
  /// saving the database resets the `last_insert_id` counter in sqlite.
  Future<int> _handlePotentialUpdate() async {
    final modified = _db.lastModifiedRows();
    if (modified > 0) {
      await storeDb();
    }
    return modified;
  }

  Future<Uint8List> export() async {
    return _db.export();
  }

  Future<void> storeDb() async {
    await storage.store(_db.export());
  }

  int get schemaVersion {
    final storage = this.storage;
    int version;
    if (storage is CustomSchemaVersionSave) {
      version = storage.schemaVersion;
    }

    return version ?? _db.userVersion;
  }

  set schemaVersion(int version) {
    final storage = this.storage;
    if (storage is CustomSchemaVersionSave) {
      storage.schemaVersion = version;
    }

    _db.userVersion = version;
  }
}