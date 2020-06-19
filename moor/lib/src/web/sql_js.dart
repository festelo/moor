import 'dart:async';
import 'dart:js';

import 'dart:typed_data';

// We write our own mapping code to js instead of depending on package:js
// This way, projects using moor can run on flutter as long as they don't import
// this file.

Completer<SqlJsModule> _moduleCompleter;

/// Calls the `initSqlJs` function from the native sql.js library.
Future<SqlJsModule> initSqlJs() {
  if (_moduleCompleter != null) {
    return _moduleCompleter.future;
  }

  _moduleCompleter = Completer();
  if (!context.hasProperty('initSqlJs')) {
    return Future.error(
        UnsupportedError('Could not access the sql.js javascript library. '
            'The moor documentation contains instructions on how to setup moor '
            'the web, which might help you fix this.'));
  }

  (context.callMethod('initSqlJs') as JsObject)
      .callMethod('then', [_handleModuleResolved]);

  return _moduleCompleter.future;
}

// We're extracting this into its own method so that we don't have to call
// [allowInterop] on this method or a lambda.
// todo figure out why dart2js generates invalid js when wrapping this in
// allowInterop
void _handleModuleResolved(dynamic module) {
  _moduleCompleter.complete(SqlJsModule._(module as JsObject));
}

/// `sql.js` module from the underlying library abstraction
abstract class SqlJsModuleBase {
  /// Constructs a new [SqlJsDatabase], optionally from the [data] blob.
  FutureOr<SqlJsDatabaseBase> createDatabase([Uint8List data]);
}

/// `sql.js` module from the underlying library
class SqlJsModule implements SqlJsModuleBase {
  final JsObject _obj;
  SqlJsModule._(this._obj);

  @override
  SqlJsDatabase createDatabase([Uint8List data]) {
    final dbObj = _createInternally(data);
    assert(() {
      // set the window.db variable to make debugging easier
      context['db'] = dbObj;
      return true;
    }());

    return SqlJsDatabase._(dbObj);
  }

  JsObject _createInternally(Uint8List data) {
    final constructor = _obj['Database'] as JsFunction;

    if (data != null) {
      return JsObject(constructor, [data]);
    } else {
      return JsObject(constructor);
    }
  }
}

/// Dart wrapper around a sql database provided by the sql.js library 
/// abstraction.
abstract class SqlJsDatabaseBase {
  /// Returns the `user_version` pragma from sqlite.
  FutureOr<int> getUserVersion();
  /// Sets sqlite's `user_version` pragma to the specified [version].
  FutureOr<void> setUserVersion(int version);
  /// Calls `prepare` on the underlying js api
  FutureOr<PreparedStatementBase> prepare(String sql);
  /// Calls `run(sql)` on the underlying js api
  FutureOr<void> run(String sql);
  /// Calls `run(sql, args)` on the underlying js api
  FutureOr<void> runWithArgs(String sql, List<dynamic> args);
  /// Returns the amount of rows affected by the most recent INSERT, UPDATE or
  /// DELETE statement.
  FutureOr<int> lastModifiedRows();
  /// The row id of the last inserted row. This counter is reset when calling
  /// [export].
  FutureOr<int> lastInsertId();
  /// Runs `export` on the underlying js api
  FutureOr<Uint8List> export();
  /// Runs `close` on the underlying js api
  FutureOr<void> close();
}

/// Dart wrapper around a sql database provided by the sql.js library.
class SqlJsDatabase implements SqlJsDatabaseBase {
  final JsObject _obj;
  SqlJsDatabase._(this._obj);

  /// Returns the `user_version` pragma from sqlite.
  @override
  int getUserVersion() {
    return _selectSingleRowAndColumn('PRAGMA user_version;') as int;
  }

  /// Sets sqlite's `user_version` pragma to the specified [version].
  @override
  void setUserVersion(int version) {
    run('PRAGMA user_version = $version');
  }

  /// Calls `prepare` on the underlying js api
  @override
  PreparedStatement prepare(String sql) {
    final obj = _obj.callMethod('prepare', [sql]) as JsObject;
    return PreparedStatement._(obj);
  }

  /// Calls `run(sql)` on the underlying js api
  @override
  void run(String sql) {
    _obj.callMethod('run', [sql]);
  }

  /// Calls `run(sql, args)` on the underlying js api
  @override
  void runWithArgs(String sql, List<dynamic> args) {
    final ar = JsArray.from(args);
    _obj.callMethod('run', [sql, ar]);
  }

  /// Returns the amount of rows affected by the most recent INSERT, UPDATE or
  /// DELETE statement.
  @override
  int lastModifiedRows() {
    return _obj.callMethod('getRowsModified') as int;
  }

  /// The row id of the last inserted row. This counter is reset when calling
  /// [export].
  @override
  int lastInsertId() {
    // load insert id. Will return [{columns: [...], values: [[id]]}]
    return _selectSingleRowAndColumn('SELECT last_insert_rowid();') as int;
  }

  dynamic _selectSingleRowAndColumn(String sql) {
    final results = _obj.callMethod('exec', [sql]) as JsArray;
    final row = results.first as JsObject;
    final data = (row['values'] as JsArray).first as JsArray;
    return data.first;
  }

  /// Runs `export` on the underlying js api
  @override
  Uint8List export() {
    return _obj.callMethod('export') as Uint8List;
  }

  /// Runs `close` on the underlying js api
  @override
  void close() {
    _obj.callMethod('close');
  }
}

/// Dart api wrapping an underlying prepared statement object from the sql.js
/// library.
abstract class PreparedStatementBase {
  /// Executes this statement with the bound [args].
  FutureOr<void> executeWith(List<dynamic> args);
  /// Performs `step` on the underlying js api
  FutureOr<bool> step();
  /// Reads the current from the underlying js 
  FutureOr<List<dynamic>> currentRow();
  /// The columns returned by this statement. This will only be available after
  /// [step] has been called once.
  FutureOr<List<String>> columnNames();
  /// Calls `free` on the underlying js api
  FutureOr<void> free();
}

/// Dart api wrapping an underlying prepared statement object from the sql.js
/// library.
class PreparedStatement implements PreparedStatementBase {
  final JsObject _obj;
  PreparedStatement._(this._obj);

  /// Executes this statement with the bound [args].
  @override
  void executeWith(List<dynamic> args) {
    _obj.callMethod('bind', [JsArray.from(args)]);
  }

  /// Performs `step` on the underlying js api
  @override
  bool step() {
    return _obj.callMethod('step') as bool;
  }

  /// Reads the current from the underlying js api
  @override
  List<dynamic> currentRow() {
    return _obj.callMethod('get') as JsArray;
  }

  /// The columns returned by this statement. This will only be available after
  /// [step] has been called once.
  @override
  List<String> columnNames() {
    return (_obj.callMethod('getColumnNames') as JsArray).cast<String>();
  }

  /// Calls `free` on the underlying js api
  @override
  void free() {
    _obj.callMethod('free');
  }
}
