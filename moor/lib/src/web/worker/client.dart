part of 'package:moor/moor_web.dart';

class MoorWorkerClient extends DatabaseDelegate {
  final MoorWebStorageFactory storageFactory;
  final CreateWebDatabase initializer;
  final MoorConnector _worker;
  StreamSubscription<MessageEvent> _connectorSubscription;
  final String _sqlJsPath;
  bool _isOpen = false;
  final bool enableLogging;

  /// Client for web database executed in `worker`
  MoorWorkerClient.fromConnector(
    this._worker,
    this._sqlJsPath,
    this.storageFactory,
    this.initializer, {
    this.enableLogging = false,
  }) {
    _connectorSubscription = _worker.onMessage.listen((e) async {
      if (e.data['action'] == 'init') {
        final data = await initializer();
        _worker.answer(e.data['id'] as int, data);
      }
    });
  }

  /// Creates web database client for server in worker
  /// Server should be placed as script at `path`
  factory MoorWorkerClient(
    String workerPath,
    String sqlJsPath,
    MoorWebStorageFactory storageFactory, {
    CreateWebDatabase initializer,
    bool enableLogging = false,
  }) {
    final worker = MoorConnector(workerPath);
    return MoorWorkerClient.fromConnector(
      worker,
      sqlJsPath,
      storageFactory,
      initializer,
      enableLogging: enableLogging,
    );
  }

  @override
  bool get isOpen => _isOpen;

  bool _inTransaction = false;

  @override
  set isInTransaction(bool value) {
    _inTransaction = value;

    if (!_inTransaction) {
      // _storeDb(); TODO: Reimplement transactions
    }
  }

  @override
  bool get isInTransaction => _inTransaction;

  @override
  Future<void> open(QueryExecutorUser db) async {
    final dbVersion = db.schemaVersion;
    assert(dbVersion >= 1, 'Database schema version needs to be at least 1');

    if (enableLogging) {
      await _worker.exec('setLogging', {'enable': true});
    }

    await _worker.exec(
      'open',
      {
        'script': _sqlJsPath,
        'factory': storageFactory.toMap(),
      },
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
    return QueryResult.fromRows(
        (res as List).map((a) => Map<String, dynamic>.from(a as Map)).toList());
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
      'args': statements.arguments.map((e) => e.toMap()).toList(),
    });
  }

  @override
  Future<int> runUpdate(String statement, List args) async {
    return await _worker
        .exec('runUpdate', {'statement': statement, 'args': args});
  }

  @override
  Future<void> close() async {
    await _worker.exec('close');
    await _worker.close();
    await _connectorSubscription.cancel();
  }

  Future<int> _getSchemaVersion() async {
    return await _worker.exec('getSchemaVersion');
  }

  Future<void> _setSchemaVersion(int version) async {
    await _worker.exec('setSchemaVersion', {'version': version});
  }

  @override
  TransactionDelegate get transactionDelegate => const NoTransactionDelegate();

  @override
  DbVersionDelegate get versionDelegate => _MoorWorkerVersionDelegate(this);

  Future<void> _storeDb() async {
    if (!isInTransaction) {
      await _worker.exec('storeDb');
    }
  }
}

class _MoorWorkerVersionDelegate extends DynamicVersionDelegate {
  final MoorWorkerClient client;
  _MoorWorkerVersionDelegate(this.client);
  // Note: Earlier moor versions used to store the database version in a special
  // field in local storage (moor_db_version_<name>). Since 2.3, we instead use
  // the user_version pragma, but still need to keep backwards compatibility.

  @override
  Future<int> get schemaVersion async {
    return await client._getSchemaVersion();
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    return await client._setSchemaVersion(version);
  }
}
