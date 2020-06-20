part of 'package:moor/moor_web.dart';

typedef FactoryResolver = MoorWebStorageFactory Function(Map<String, dynamic>);

/// Interface to build the storage.
abstract class MoorWebStorageFactory {
  /// Convert the factory to map. Map should include 'type' property
  /// that will be used for deserialization
  Map<String, dynamic> toMap();

  /// Construct web storage
  MoorWebStorage build();

  /// Defines factories that can be returned by executing
  /// [MoorWebStorageFactory.fromMap]
  ///
  /// Note that worker doesn't share [factories] with the app
  static Map<String, FactoryResolver> factories = {
    (_IndexedDbStorageFactory).toString(): (m) =>
        _IndexedDbStorageFactory.fromMap(m),
    (_LocalStorageFactory).toString(): (m) => _LocalStorageFactory.fromMap(m),
  };

  /// Converts map to web storage factory.
  /// Factories should be defined in [factories]
  factory MoorWebStorageFactory.fromMap(Map<String, dynamic> map) {
    final type = map['type'];
    if (factories[type] == null) {
      throw Exception('Factory not found for $type');
    }
    return factories[type](map);
  }

  /// Creates the default storage implementation that uses the local storage
  /// apis.
  ///
  /// The [name] parameter can be used to store multiple databases.
  const factory MoorWebStorageFactory(String name) = _LocalStorageFactory;

  /// An experimental storage implementation that uses IndexedDB.
  ///
  /// This implementation is significantly faster than the default
  /// implementation in local storage. Browsers also tend to allow more data
  /// to be saved in IndexedDB.
  ///
  /// When the [migrateFromLocalStorage] parameter (defaults to `true`) is set,
  /// old data saved using the default [MoorWebStorage] will be migrated to the
  /// IndexedDB based implementation. This parameter can be turned off for
  /// applications that never used the local storage implementation as a small
  /// performance improvement.
  ///
  /// When the [inWebWorker] parameter (defaults to false) is set,
  /// the implementation will use [WorkerGlobalScope] instead of [window] as
  /// it isn't accessible from the worker.
  ///
  /// However, older browsers might not support IndexedDB.
  @experimental
  factory MoorWebStorageFactory.indexedDb(String name,
      {bool migrateFromLocalStorage,
      bool inWebWorker}) = _IndexedDbStorageFactory;

  /// Uses [MoorWebStorage.indexedDb] if the current browser supports it.
  /// Otherwise, falls back to the local storage based implementation.
  factory MoorWebStorageFactory.indexedDbIfSupported(String name,
      {bool inWebWorker = true}) {
    return supportsIndexedDb(inWebWorker: inWebWorker)
        ? MoorWebStorageFactory.indexedDb(name, inWebWorker: inWebWorker)
        : MoorWebStorageFactory(name);
  }

  /// Attempts to check whether the current browser supports the
  /// [MoorWebStorage.indexedDb] storage implementation.
  static bool supportsIndexedDb({bool inWebWorker = false}) {
    var isIndexedDbSupported = false;
    if (inWebWorker && WorkerGlobalScope.instance.indexedDB != null) {
      isIndexedDbSupported = true;
    } else {
      try {
        isIndexedDbSupported = IdbFactory.supported;
      } catch (error) {
        isIndexedDbSupported = false;
      }
    }
    return isIndexedDbSupported && context.hasProperty('FileReader');
  }
}

class _LocalStorageFactory implements MoorWebStorageFactory {
  final String name;
  const _LocalStorageFactory(this.name);

  factory _LocalStorageFactory.fromMap(Map<String, dynamic> map) {
    return _LocalStorageFactory(
      map['name'] as String,
    );
  }

  @override
  MoorWebStorage build() {
    return _LocalStorageImpl(name);
  }

  @override
  Map<String, dynamic> toMap() {
    return {'type': (_LocalStorageFactory).toString(), 'name': name};
  }
}

class _IndexedDbStorageFactory implements MoorWebStorageFactory {
  final String name;
  final bool migrateFromLocalStorage;
  final bool inWebWorker;

  _IndexedDbStorageFactory(
    this.name, {
    this.migrateFromLocalStorage = false,
    this.inWebWorker = false,
  });

  factory _IndexedDbStorageFactory.fromMap(Map<String, dynamic> map) {
    return _IndexedDbStorageFactory(
      map['name'] as String,
      migrateFromLocalStorage: map['migrateFromLocalStorage'] as bool,
      inWebWorker: map['inWebWorker'] as bool,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'type': (_IndexedDbStorageFactory).toString(),
      'name': name,
      'migrateFromLocalStorage': migrateFromLocalStorage,
      'inWebWorker': inWebWorker,
    };
  }

  @override
  _IndexedDbStorage build() {
    return _IndexedDbStorage(
      name,
      migrateFromLocalStorage: migrateFromLocalStorage,
      inWebWorker: inWebWorker,
    );
  }
}
