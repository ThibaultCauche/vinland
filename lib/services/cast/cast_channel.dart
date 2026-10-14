import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cast_message.dart';

/// Espaces de noms du protocole Cast utilises par Vinland.
abstract final class CastNamespace {
  static const connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const receiver = 'urn:x-cast:com.google.cast.receiver';
  static const media = 'urn:x-cast:com.google.cast.media';
}

/// La connexion a une Chromecast : messages entrants, envoi, requetes avec
/// reponse, et le battement de coeur sans lequel la Chromecast coupe au
/// bout de quelques secondes.
///
/// Independante de la socket ([input] / [write]) pour etre testee contre un
/// faux recepteur ; [connect] ouvre la vraie (TLS, port 8009).
class CastChannel {
  CastChannel(
    Stream<List<int>> input,
    this._write, {
    Future<void> Function()? close,
    Duration heartbeat = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 15),
  }) : _close = close {
    _sub = input.listen(
      (chunk) {
        try {
          for (final message in _decoder.add(chunk)) {
            _onMessage(message);
          }
        } on FormatException {
          _finish();
        }
      },
      onError: (Object _) => _finish(),
      onDone: _finish,
      cancelOnError: true,
    );
    _heartbeat = Timer.periodic(heartbeat, (_) {
      send(CastNamespace.heartbeat, 'receiver-0', {'type': 'PING'});
    });
  }

  /// La Chromecast presente un certificat auto-signe propre a l'appareil :
  /// il ne prouve rien sur un reseau local, on l'accepte donc tel quel.
  static Future<CastChannel> connect(String host, int port) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
      onBadCertificate: (_) => true,
    );
    return CastChannel(
      socket,
      socket.add,
      close: () async => socket.destroy(),
    );
  }

  final void Function(List<int> bytes) _write;
  final Future<void> Function()? _close;
  final Duration requestTimeout;
  final _decoder = CastFrameDecoder();
  // Synchrone : les ecouteurs voient une reponse avant que la requete qui
  // l'attendait ne reprenne (sinon l'etat de la reponse arriverait apres,
  // par exemple apres un seek fait juste derriere un chargement).
  final _messages = StreamController<CastMessage>.broadcast(sync: true);
  final _pending = <int, Completer<CastMessage>>{};
  final _done = Completer<void>();
  late final StreamSubscription<List<int>> _sub;
  late final Timer _heartbeat;
  var _nextRequestId = 1;

  Stream<CastMessage> get messages => _messages.stream;

  /// Se termine quand la connexion est fermee (par nous ou la Chromecast).
  Future<void> get done => _done.future;
  bool get isClosed => _done.isCompleted;

  void _onMessage(CastMessage message) {
    if (message.namespace == CastNamespace.heartbeat &&
        message.type == 'PING') {
      send(CastNamespace.heartbeat, message.sourceId, {'type': 'PONG'});
      return;
    }
    _messages.add(message);
    final requestId = message.json?['requestId'];
    if (requestId is int && requestId > 0) {
      final pending = _pending.remove(requestId);
      if (pending != null && !pending.isCompleted) pending.complete(message);
    }
  }

  void send(
    String namespace,
    String destination,
    Map<String, Object?> payload,
  ) {
    if (isClosed) return;
    try {
      _write(CastMessage(
        namespace: namespace,
        destinationId: destination,
        payload: jsonEncode(payload),
      ).toFrame());
    } catch (_) {
      _finish();
    }
  }

  /// Envoie [payload] avec un requestId et attend la reponse qui le reprend.
  Future<CastMessage> request(
    String namespace,
    String destination,
    Map<String, Object?> payload,
  ) {
    if (isClosed) {
      return Future.error(const SocketException('Chromecast deconnectee'));
    }
    final id = _nextRequestId++;
    final completer = Completer<CastMessage>();
    _pending[id] = completer;
    send(namespace, destination, {...payload, 'requestId': id});
    return completer.future.timeout(requestTimeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('Pas de reponse de la Chromecast');
    });
  }

  void _finish() {
    if (_done.isCompleted) return;
    _heartbeat.cancel();
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const SocketException('Chromecast deconnectee'));
      }
    }
    _pending.clear();
    _done.complete();
    unawaited(_messages.close());
  }

  Future<void> close() async {
    if (isClosed) return;
    _finish();
    await _sub.cancel();
    await _close?.call();
  }
}
