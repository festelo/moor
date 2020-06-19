import 'dart:async';
import 'dart:html';

import 'dart:typed_data';

import 'sql_js.dart';

// We write our own mapping code to js instead of depending on package:js
// This way, projects using moor can run on flutter as long as they don't import
// this file.

/// Calls the `initSqlJs` function from the native sql.js library.
SqlJsModuleBase initSqlJsWorker(String path) {
  return SqlJsWorkerModule._(Worker(path));
}

/// `sql.js` module from the underlying library
class SqlJsWorkerModule implements SqlJsModuleBase {
  final Worker _obj;
  SqlJsWorkerModule._(this._obj);

  /// Constructs a new [SqlJsDatabase], optionally from the [data] blob.
  @override
  Future<SqlJsDatabaseBase> createDatabase([Uint8List data]) async {
    final worker = await _createDbInternally(data);
    return SqlJsWorkerDatabase._(worker);
  }

  Future<_SqlWorkerConnector> _createDbInternally(Uint8List data) async {
    final worker = _SqlWorkerConnector(_obj);
    if (data != null) {
      await worker.exec('create', {'buffer': data});
    } else {
      await worker.exec('create');
    }
    return worker;
  }
}

class _SqlWorkerConnector {
  final Worker _worker;
  StreamSubscription _messageSubscription;
  StreamSubscription _errorSubscription;
  _SqlWorkerConnector(this._worker) {
    _messageSubscription = _worker.onMessage.listen(_onMessage);
    _errorSubscription = _worker.onError.listen(_onError);
  }

  Map<int, Completer> _awaitedMessages;
  int _idCounter = -1;
  int _getFreeId() {
    return _idCounter++;
  }

  void _onError(dynamic e) {
    throw Exception('Unknown error received from worker: $e');
  }

  void _onMessage(MessageEvent event) {
    final id = event.data['id'] as int;
    if (!_awaitedMessages.containsKey(id) || _awaitedMessages[id].isCompleted) {
      throw Exception('Response for $id already received or not requested');
    }
    _awaitedMessages[id].complete(event.data);
  }

  /// Executes action and awaits it
  Future<dynamic> exec(String action,
      [Map<String, dynamic> params = const {}]) async {
    final messageId = _getFreeId();
    final completer = Completer();
    _awaitedMessages[messageId] = completer;
    _worker.postMessage({'id': messageId, 'action': action, ...params});
    _awaitedMessages.remove(messageId);
    return await completer.future;
  }

  Future<void> close() async {
    await _messageSubscription.cancel();
    await _errorSubscription.cancel();
    _worker.terminate();
  }
}

/// Dart wrapper around a sql database provided by the sql.js library,
/// inside a web worker.
class SqlJsWorkerDatabase implements SqlJsDatabaseBase {
  final _SqlWorkerConnector _worker;
  SqlJsWorkerDatabase._(this._worker);

  /// Returns the `user_version` pragma from sqlite.
  @override
  Future<int> getUserVersion() async {
    final response = await _worker.exec('getUserVersion');
    final userVersion = response['res'] as int;
    return userVersion;
  }

  /// Sets sqlite's `user_version` pragma to the specified [version].
  @override
  Future<void> setUserVersion(int version) async {
    await _worker.exec('setUserVersion', {'version': version});
  }

  /// Calls `prepare` on the underlying js api
  @override
  Future<PreparedStatementBase> prepare(String sql) async {
    final response = await _worker.exec('prepare', {'sql': sql});
    final id = response['res'] as int;
    return PreparedStatementWorker._(_worker, id);
  }

  /// Returns the amount of rows affected by the most recent INSERT, UPDATE or
  /// DELETE statement.
  @override
  Future<int> lastModifiedRows() async {
    final response = await _worker.exec('lastModifiedRows');
    return response['res'] as int;
  }

  /// The row id of the last inserted row. This counter is reset when calling
  /// [export].
  @override
  Future<int> lastInsertId() async {
    final response = await _worker.exec('lastInsertId');
    return response['res'] as int;
  }

  @override
  Future<void> run(String sql) async {
    await _worker.exec('run', {'sql': sql});
  }

  @override
  Future<void> runWithArgs(String sql, List args) async {
    await _worker.exec('runWithArgs', {'sql': sql, 'args': args});
  }

  /// Runs `export` on the underlying js api
  @override
  Future<Uint8List> export() async {
    final response = await _worker.exec('export');
    return response['res'] as Uint8List;
  }

  /// Runs `close` on the underlying js api and closes worker
  @override
  Future<void> close() async {
    await _worker.exec('close');
    await _worker.close();
  }
}

/// Dart api wrapping an underlying prepared statement object from the sql.js
/// library.
class PreparedStatementWorker implements PreparedStatementBase {
  final _SqlWorkerConnector _connector;
  final int _statementId;
  PreparedStatementWorker._(this._connector, this._statementId);

  /// Executes this statement with the bound [args].
  @override
  Future<void> executeWith(List<dynamic> args) async {
    await _connector
        .exec('executeWith', {'statementId': _statementId, 'args': args});
  }

  /// Performs `step` on the underlying js api
  @override
  Future<bool> step() async {
    final response =
        await _connector.exec('step', {'statementId': _statementId});
    return response['res'] as bool;
  }

  /// Reads the current from the underlying js api
  @override
  Future<List<dynamic>> currentRow() async {
    final response =
        await _connector.exec('currentRow', {'statementId': _statementId});
    return response['res'] as List<dynamic>;
  }

  /// The columns returned by this statement. This will only be available after
  /// [step] has been called once.
  @override
  Future<List<String>> columnNames() async {
    final response =
        await _connector.exec('columnNames', {'statementId': _statementId});
    return (response['res'] as List<dynamic>).cast<String>();
  }

  /// Calls `free` on the underlying js api
  @override
  Future<void> free() async {
    await _connector.exec('free', {'statementId': _statementId});
  }
}
