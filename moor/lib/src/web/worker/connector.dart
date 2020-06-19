import 'dart:async';
import 'dart:html';

abstract class _MoorConnectable {
  Stream<MessageEvent> get onMessage;
  Stream<Event> get onError;
  void postMessage(dynamic message);
  void terminate();
}

class _WorkerConnectable extends _MoorConnectable {
  @override
  Stream<MessageEvent> get onMessage => worker.onMessage;
  @override
  Stream<Event> get onError => worker.onError;
  @override
  void postMessage(dynamic message) => worker.postMessage(message);
  @override
  void terminate() => worker.terminate();
  final Worker worker;
  _WorkerConnectable(this.worker);
}

class _WorkerScopeConnectable extends _MoorConnectable {
  @override
  Stream<MessageEvent> get onMessage => worker.onMessage;
  @override
  Stream<Event> get onError => worker.onError;
  @override
  void postMessage(dynamic message) => worker.postMessage(message);
  @override
  void terminate() => throw UnsupportedError('Unsupported on scope');
  final DedicatedWorkerGlobalScope worker;
  _WorkerScopeConnectable(this.worker);
}

/// Class responsible for web db worker managing -
/// creation, communication and termination
class MoorConnector {
  final _MoorConnectable _worker;
  StreamSubscription _messageSubscription;
  StreamSubscription _errorSubscription;
  final _onMessageController = StreamController<MessageEvent>.broadcast();

  /// Stream for events sent by server
  Stream<MessageEvent> get onMessage => _onMessageController.stream;

  MoorConnector.fromConnectable(this._worker) {
    _messageSubscription = _worker.onMessage.listen(_onMessageHandler);
    _errorSubscription = _worker.onError.listen(_onError);
  }

  factory MoorConnector(String workerPath) {
    final worker = Worker(workerPath);
    final connectable = _WorkerConnectable(worker);
    return MoorConnector.fromConnectable(connectable);
  }

  factory MoorConnector.fromScope(DedicatedWorkerGlobalScope scope) {
    final connectable = _WorkerScopeConnectable(scope);
    return MoorConnector.fromConnectable(connectable);
  }

  final Map<int, Completer> _awaitedMessages = {};
  int _idCounter = -1;
  int _getFreeId() {
    return _idCounter++;
  }

  void _onError(dynamic e) {
    if (e is ErrorEvent) {
      throw Exception('Error received from worker: ${e.message}');
    }
    throw Exception('Unknown error received from worker: $e');
  }

  void _onMessageHandler(MessageEvent event) {
    if (event.data['type'] == 'response') {
      final id = event.data['id'] as int;
      if (!_awaitedMessages.containsKey(id) ||
          _awaitedMessages[id].isCompleted) {
        throw Exception('Response for $id already received or not requested');
      }
      _awaitedMessages[id].complete(event.data);
    } else {
      _onMessageController.add(event);
    }
  }

  /// Executes action and awaits it
  Future<T> exec<T>(String action,
      [Map<String, dynamic> params = const {}]) async {
    final messageId = _getFreeId();
    final completer = Completer();
    _awaitedMessages[messageId] = completer;
    _worker.postMessage({'id': messageId, 'action': action, ...params});
    final response = await completer.future;
    _awaitedMessages.remove(messageId);
    return response['res'] as T;
  }

  /// Answer on message with ID
  void answer(int id, [dynamic data]) {
    _worker.postMessage(
        {'id': id, 'type': 'response', if (data != null) 'res': data});
  }

  /// Cancels all subscriptions and terminates worker
  Future<void> close() async {
    await _messageSubscription.cancel();
    await _errorSubscription.cancel();
    await _onMessageController.close();
    _worker.terminate();
  }
}
