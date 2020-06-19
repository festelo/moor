@JS()
library sql_js_worker;

import 'dart:html';
import 'dart:typed_data';
import 'package:js/js.dart';

import 'sql_js.dart';

@JS('self')
external DedicatedWorkerGlobalScope get self;

SqlJsDatabase _database;

Future<void> main() async {
  await for (final e in self.onMessage) {
    final action = e.data['action'];
    final id = e.data['id'] as int;
    if (action == 'create') {
      final module = await initSqlJs();
      final buffer = e.data['buffer'] as Uint8List;
      _database = module.createDatabase(buffer);
      continue;
    }
    if (_database == null) {
      throw Exception('Database should be created first');
    }
    final functions = {
      'close': _close,
      'export': _export,
      'getUserVersion': _getUserVersion,
      'setUserVersion': _setUserVersion,
      'lastInsertId': _lastInsertId,
      'lastModifiedRows': _lastModifiedRows,
      'prepare': _prepare,
      'run': _run,
      'runWithArgs': _runWithArgs,
      'executeWith': _executeWith,
      'step': _step,
      'currentRow': _currentRow,
      'columnNames': _columnNames,
      'free': _free,
    };
    if (functions[action] == null) {
      throw Exception('Function for $action not found');
    }
    functions[action](id, e.data);
  }
}

void _close(int id, dynamic data) {
  _database.close();
  self.postMessage({'id': id});
}

void _export(int id, dynamic data) {
  final data = _database.export();
  try {
    self.postMessage({'id': id, 'res': data}, data);
  } catch (_) {
    self.postMessage({'id': id, 'res': data});
  }
}

void _getUserVersion(int id, dynamic data) {
  final version = _database.getUserVersion();
  self.postMessage({'id': id, 'res': version});
}

void _setUserVersion(int id, dynamic data) {
  final version = data['version'];
  _database.setUserVersion(version as int);
  self.postMessage({'id': id});
}

void _lastInsertId(int id, dynamic data) {
  final res = _database.lastInsertId();
  self.postMessage({'id': id, 'res': res});
}

void _lastModifiedRows(int id, dynamic data) {
  final res = _database.lastModifiedRows();
  self.postMessage({'id': id, 'res': res});
}

int _prepareCounter = -1;
Map<int, PreparedStatement> _preparedMap = {};
void _prepare(int id, dynamic data) {
  final prepareId = _prepareCounter++;
  final prepared = _database.prepare(data['sql'] as String);
  _preparedMap[prepareId] = prepared;
  self.postMessage({'id': id, 'res': prepareId});
}

void _run(int id, dynamic data) {
  _database.run(data['sql'] as String);
  self.postMessage({'id': id});
}

void _runWithArgs(int id, dynamic data) {
  _database.runWithArgs(data['sql'] as String, data['args'] as List);
  self.postMessage({'id': id});
}

// statement part

PreparedStatement _getStatement(int statementId) {
  final statement = _preparedMap[statementId];
  if (statement == null) {
    throw Exception('Statement not found, unknown id passed $statementId');
  }
  return statement;
}

void _executeWith(int id, dynamic data) {
  final statement = _getStatement(data['statementId'] as int);
  statement.executeWith(data['args'] as List);
  self.postMessage({'id': id});
}

void _step(int id, dynamic data) {
  final statement = _getStatement(data['statementId'] as int);
  final res = statement.step();
  self.postMessage({'id': id, 'res': res});
}

void _currentRow(int id, dynamic data) {
  final statement = _getStatement(data['statementId'] as int);
  final res = statement.currentRow();
  self.postMessage({'id': id, 'res': res});
}

void _columnNames(int id, dynamic data) {
  final statement = _getStatement(data['statementId'] as int);
  final res = statement.columnNames();
  self.postMessage({'id': id, 'res': res});
}

void _free(int id, dynamic data) {
  final statementId = data['statementId'] as int;
  final statement = _getStatement(statementId);
  statement.free();
  _preparedMap.remove(statementId);
  self.postMessage({'id': id});
}
