import 'dart:async';
import 'dart:convert';

import 'package:vinland/services/cast/cast_channel.dart';
import 'package:vinland/services/cast/cast_message.dart';

/// Fausse Chromecast au bout d'un CastChannel : repond au lancement du
/// lecteur et aux chargements comme le recepteur media par defaut, et
/// laisse le test envoyer ses propres etats.
class FakeCastReceiver {
  FakeCastReceiver({
    this.failLoad = false,
    this.refuseLaunch = false,
    this.apps = const {'CC1AD845'},
  }) {
    channel = CastChannel(
      _toSender.stream,
      _onSenderBytes,
      heartbeat: const Duration(hours: 1),
      requestTimeout: const Duration(seconds: 2),
    );
  }

  bool failLoad;
  bool refuseLaunch;

  /// Recepteurs que cette Chromecast sait lancer (les autres : LAUNCH_ERROR,
  /// comme un recepteur pas encore autorise sur l'appareil).
  final Set<String> apps;
  String _runningApp = 'CC1AD845';
  late final CastChannel channel;
  final _toSender = StreamController<List<int>>();
  final _decoder = CastFrameDecoder();

  /// Tout ce que l'app a envoye, decode.
  final List<CastMessage> received = [];
  List<String> get types => [for (final m in received) m.type ?? '?'];

  static const transportId = 'web-7';
  static const sessionId = 'session-1';
  int mediaSessionId = 0;
  double volume = 0.4;

  /// Etat du titre renvoye a une demande d'etat (reprise de session).
  String playerState = 'PAUSED';

  void _onSenderBytes(List<int> bytes) {
    for (final message in _decoder.add(bytes)) {
      received.add(message);
      final payload = message.json ?? const {};
      final requestId = payload['requestId'] as int? ?? 0;
      switch (payload['type']) {
        case 'LAUNCH' when !apps.contains(payload['appId']):
          send(CastNamespace.receiver, 'receiver-0', {
            'type': 'LAUNCH_ERROR',
            'requestId': requestId,
            'reason': 'NOT_FOUND',
          });
        case 'LAUNCH':
          _runningApp = payload['appId'] as String;
          send(CastNamespace.receiver, 'receiver-0', {
            'type': 'RECEIVER_STATUS',
            'requestId': requestId,
            'status': {
              'applications': [
                if (!refuseLaunch)
                  {
                    'appId': _runningApp,
                    'transportId': transportId,
                    'sessionId': sessionId,
                  },
              ],
              'volume': {'level': volume},
            },
          });
        case 'GET_STATUS' when message.namespace == CastNamespace.receiver:
          send(CastNamespace.receiver, 'receiver-0', {
            'type': 'RECEIVER_STATUS',
            'requestId': requestId,
            'status': {
              'applications': [
                {
                  'appId': _runningApp,
                  'transportId': transportId,
                  'sessionId': sessionId,
                },
              ],
              'volume': {'level': volume},
            },
          });
        case 'GET_STATUS' when message.namespace == CastNamespace.media:
          mediaStatus(playerState,
              requestId: requestId, time: 42, duration: 200);
        case 'LOAD':
          if (failLoad) {
            send(CastNamespace.media, transportId, {
              'type': 'LOAD_FAILED',
              'requestId': requestId,
            });
          } else {
            mediaSessionId++;
            mediaStatus('PAUSED', requestId: requestId, duration: 200);
          }
        case 'PLAY':
          mediaStatus('PLAYING', requestId: requestId);
        case 'PAUSE':
          mediaStatus('PAUSED', requestId: requestId);
        case 'SEEK':
          mediaStatus('PAUSED',
              requestId: requestId, time: payload['currentTime'] as num);
        case 'STOP' when message.namespace == CastNamespace.receiver:
          send(CastNamespace.receiver, 'receiver-0', {
            'type': 'RECEIVER_STATUS',
            'requestId': requestId,
            'status': {'applications': <Object>[]},
          });
        case 'SET_VOLUME':
          volume = ((payload['volume'] as Map)['level'] as num).toDouble();
      }
    }
  }

  void send(String namespace, String source, Map<String, Object?> payload) {
    _toSender.add(CastMessage(
      namespace: namespace,
      sourceId: source,
      destinationId: 'sender-0',
      payload: jsonEncode(payload),
    ).toFrame());
  }

  void mediaStatus(
    String state, {
    int requestId = 0,
    String? idleReason,
    num time = 0,
    num? duration,
    int? session,
  }) {
    send(CastNamespace.media, transportId, {
      'type': 'MEDIA_STATUS',
      'requestId': requestId,
      'status': [
        {
          'mediaSessionId': session ?? mediaSessionId,
          'playerState': state,
          'currentTime': time,
          if (idleReason != null) 'idleReason': idleReason,
          if (duration != null) 'media': {'duration': duration},
        },
      ],
    });
  }

  /// La tele passe sur une autre appli : notre lecteur est ferme.
  void closeApp() => send(CastNamespace.connection, transportId, {
        'type': 'CLOSE',
      });

  Future<void> disconnectSocket() => _toSender.close();
}
