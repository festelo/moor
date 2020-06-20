@JS()
library sql_js_worker;

import 'dart:async';
import 'dart:html';
import 'dart:typed_data';
import 'package:js/js.dart';
import 'package:moor/backends.dart';
import 'connector.dart';
import 'server.dart';

@JS('self')
external DedicatedWorkerGlobalScope get self;

/// Connector to communicate with client
final connector = MoorConnector.fromScope(self);

/// WorkerServer for handling requests
final MoorWorkerServer workerServer =
    MoorWorkerServer(() => connector.exec('storeDb'));

void main() {
  connector.onMessage.listen((e) async {
    final action = e.data['action'];
    final id = e.data['id'] as int;
    log('$id received - $action. ${e.data}');
    final functions = <String, FutureOr<void> Function(int, dynamic)>{
      'setLogging': _setLogging,
      'open': _open,
      'runCustom': _runCustom,
      'runInsert': _runInsert,
      'runSelect': _runSelect,
      'runBatched': _runBatched,
      'close': _close,
      'export': _export,
      'getUserVersion': _getUserVersion,
      'setUserVersion': _setUserVersion,
    };
    if (functions[action] == null) {
      throw Exception('Function for $action not found');
    }
    try {
      await functions[action](id, e.data);
    } catch (e) {
      log('Error when handling message $id');
      rethrow;
    }
  });
}

/// Sends response back
void answer(int id, [dynamic data]) {
  connector.answer(id, data);
}

bool _logging = false;

/// Prints message to console if logging is enabled
void log(String message) {
  if (_logging) {
    print(message);
  }
}

void _setLogging(int id, dynamic data) {
  final enable = data['enable'] as bool;
  _logging = enable;
  answer(id);
}

Future<void> _open(int id, dynamic data) async {
  self.importScripts(data['script'] as String);
  final buffer = data['buffer'] as Uint8List;
  await workerServer.open(buffer);
  answer(id);
}

void _runCustom(int id, dynamic data) {
  final statement = data['statement'] as String;
  final args = data['args'] as List;
  workerServer.runCustom(statement, args);
  answer(id);
}

Future<void> _runInsert(int id, dynamic data) async {
  final statement = data['statement'] as String;
  final args = data['args'] as List;
  final res = await workerServer.runInsert(statement, args);
  answer(id, res);
}

Future<void> _runSelect(int id, dynamic data) async {
  final statement = data['statement'] as String;
  final args = data['args'] as List;
  final res = await workerServer.runSelect(statement, args);
  answer(id, res);
}

Future<void> _runBatched(int id, dynamic data) async {
  final statement = (data['statements'] as List).cast<String>();
  final argsParam = data['args'] as List;
  final args = argsParam
      .map((e) => ArgumentsForBatchedStatement.fromMap((e as Map).cast()))
      .toList();
  await workerServer.runBatched(statement, args);
  answer(id);
}

void _close(int id, dynamic data) {
  workerServer.close();
  answer(id);
}

Future<void> _export(int id, dynamic data) async {
  final data = await workerServer.export();
  answer(id, data);
}

void _getUserVersion(int id, dynamic data) {
  final version = workerServer.userVersion;
  self.postMessage({'id': id, 'res': version});
  answer(id, version);
}

void _setUserVersion(int id, dynamic data) {
  final version = data['version'] as int;
  workerServer.userVersion = version;
  answer(id);
  self.postMessage({'id': id});
}
