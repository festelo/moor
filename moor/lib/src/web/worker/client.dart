part of 'package:moor/moor_web.dart';

class MoorWorkerClient extends DatabaseDelegate {
  final MoorWebStorage storage;
  final CreateWebDatabase initializer;
  final MoorConnector _worker;
  StreamSubscription<MessageEvent> _connectorSubscription;
  final String _sqlJsPath;
  bool _isOpen = false;

  /// Client for web database executed in `worker`
  MoorWorkerClient.fromConnector(
      this._worker, this._sqlJsPath, this.storage, this.initializer) {
    _connectorSubscription = _worker.onMessage.listen((e) async {
      if (e.data['action'] == 'storeDb') {
        await _storeDb();
        _worker.answer(e.data['id'] as int);
      }
    });
  }

  /// Creates web database client for server in worker
  /// Server should be placed as script at `path`
  factory MoorWorkerClient(
    String workerPath,
    String sqlJsPath,
    MoorWebStorage storage,
    CreateWebDatabase initializer,
  ) {
    final worker = MoorConnector(workerPath);
    return MoorWorkerClient.fromConnector(
        worker, sqlJsPath, storage, initializer);
  }

  @override
  bool get isOpen => _isOpen;

  bool _inTransaction = false;

  @override
  set isInTransaction(bool value) {
    _inTransaction = value;

    if (!_inTransaction) {
      _storeDb();
    }
  }

  @override
  bool get isInTransaction => _inTransaction;

  @override
  Future<void> open(QueryExecutorUser db) async {
    final dbVersion = db.schemaVersion;
    assert(dbVersion >= 1, 'Database schema version needs to be at least 1');

    await storage.open();
    var restored = await storage.restore();

    if (restored == null && initializer != null) {
      restored = await initializer();
      await storage.store(restored);
    }

    await _worker.exec(
      'open',
      {'script': _sqlJsPath, if (restored != null) 'buffer': restored},
    );
    _isOpen = true;
  }

  @override
  Future<void> runCustom(String statement, List args) async {
    await _worker.exec('runCustom', {'statement': statement, 'args': args});
  }

  @override
  Future<int> runInsert(String statement, List args) async {
    return await _worker
        .exec('runInsert', {'statement': statement, 'args': args});
  }

  @override
  Future<QueryResult> runSelect(String statement, List args) async {
    final res =
        await _worker.exec('runSelect', {'statement': statement, 'args': args});
    return QueryResult.fromRows(res as List<Map<String, dynamic>>);
  }

  @override
  void notifyDatabaseOpened(OpeningDetails details) {
    if (details.hadUpgrade || details.wasCreated) {
      _storeDb();
    }
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    await _worker.exec('runBatched', {
      'statements': statements.statements,
      'arguments': statements.arguments,
    });
  }

  @override
  Future<int> runUpdate(String statement, List args) async {
    return await _worker
        .exec('runUpdate', {'statement': statement, 'args': args});
  }

  @override
  Future<void> close() async {
    await _storeDb();
    await _worker.exec('close');
    await _worker.close();
    await storage.close();
    await _connectorSubscription.cancel();
  }

  Future<int> _getUserVersion() async {
    return await _worker.exec('getUserVersion');
  }

  Future<void> _setUserVersion(int version) async {
    await _worker.exec('setUserVersion', {'version': version});
  }

  @override
  TransactionDelegate get transactionDelegate => const NoTransactionDelegate();

  @override
  DbVersionDelegate get versionDelegate => _MoorWorkerVersionDelegate(this);

  Future<void> _storeDb() async {
    if (!isInTransaction) {
      final data = await _worker.exec<Uint8List>('export');
      await storage.store(data);
    }
  }
}

class _MoorWorkerVersionDelegate implements DbVersionDelegate {
  final MoorWorkerClient client;
  _MoorWorkerVersionDelegate(this.client);
  // Note: Earlier moor versions used to store the database version in a special
  // field in local storage (moor_db_version_<name>). Since 2.3, we instead use
  // the user_version pragma, but still need to keep backwards compatibility.

  @override
  Future<int> get schemaVersion async {
    final storage = client.storage;
    int version;
    if (storage is _CustomSchemaVersionSave) {
      version = storage.schemaVersion;
    }

    return version ?? await client._getUserVersion();
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    final storage = client.storage;

    if (storage is _CustomSchemaVersionSave) {
      storage.schemaVersion = version;
    }

    await client._setUserVersion(version);
  }
}
