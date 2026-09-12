// Relais WebSocket pour l'ecoute synchronisee ("Jam") de Vinland.
//
// Volontairement "bete" : ce service ne connait rien de Navidrome, de la
// musique ou des comptes utilisateurs. Il ne fait que rediffuser, a tous les
// participants d'une session, l'etat de lecture envoye par l'hote de cette
// session (modele hote-autoritaire : un seul appareil pilote play/pause/
// seek/changement de titre, les autres suivent en miroir cote client).
//
// Le sessionId (genere aleatoirement cote app, voir lib/services/
// jam_service.dart) sert de secret partage : quiconque le connait peut
// rejoindre. Pas d'autre authentification -- coherent avec un usage
// "cercle proche" ou le sessionId est partage directement entre amis.
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Session {
  final String id;
  WebSocketChannel? host;
  final Set<WebSocketChannel> participants = {};

  _Session(this.id);

  int get participantCount => participants.length;
}

final Map<String, _Session> _sessions = {};

void main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8765;

  final handler = webSocketHandler((WebSocketChannel channel, String? _) {
    _handleConnection(channel);
  });

  final server = await shelf_io.serve(
    // Un seul chemin ("/jam") : c'est celui que tailscale serve doit router
    // vers ce service, sur le meme hostname Funnel que Navidrome.
    (Request request) {
      if (request.url.path == 'jam' || request.url.path == '') {
        return handler(request);
      }
      return Response.notFound('not found');
    },
    InternetAddress.anyIPv4,
    port,
  );
  stderr.writeln('jam_relay: en ecoute sur :${server.port}');
}

void _handleConnection(WebSocketChannel channel) {
  String? sessionId;
  bool isHost = false;

  channel.stream.listen(
    (raw) {
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(raw as String) as Map<String, dynamic>;
      } catch (_) {
        return;
      }

      switch (msg['type']) {
        case 'host':
          {
            final id = msg['sessionId']?.toString();
            if (id == null || id.isEmpty) {
              _sendError(channel, 'sessionId manquant');
              return;
            }
            final session = _sessions.putIfAbsent(id, () => _Session(id));
            session.host = channel;
            sessionId = id;
            isHost = true;
            _send(channel, {'type': 'joined', 'sessionId': id, 'role': 'host'});
            break;
          }

        case 'join':
          {
            final id = msg['sessionId']?.toString();
            final session = id == null ? null : _sessions[id];
            if (session == null) {
              _sendError(channel, 'session introuvable');
              return;
            }
            session.participants.add(channel);
            sessionId = id;
            isHost = false;
            _send(channel,
                {'type': 'joined', 'sessionId': id, 'role': 'participant'});
            _notifyParticipantCount(session);
            break;
          }

        case 'state':
          {
            final id = sessionId;
            if (id == null || !isHost) return;
            final session = _sessions[id];
            if (session == null) return;
            // Rediffuse tel quel (trackId/positionMs/isPlaying/ts) a tous
            // les participants -- aucune interpretation cote relais.
            for (final participant in session.participants) {
              _send(participant, msg);
            }
            break;
          }

        case 'leave':
          channel.sink.close();
          break;
      }
    },
    onDone: () => _handleDisconnect(sessionId, isHost, channel),
    onError: (_) => _handleDisconnect(sessionId, isHost, channel),
    cancelOnError: true,
  );
}

void _handleDisconnect(String? sessionId, bool isHost, WebSocketChannel channel) {
  if (sessionId == null) return;
  final session = _sessions[sessionId];
  if (session == null) return;

  if (isHost) {
    for (final participant in session.participants) {
      _send(participant, {'type': 'host_left'});
    }
    _sessions.remove(sessionId);
  } else {
    session.participants.remove(channel);
    _notifyParticipantCount(session);
  }
}

void _notifyParticipantCount(_Session session) {
  final host = session.host;
  if (host == null) return;
  _send(host, {'type': 'participant_count', 'count': session.participantCount});
}

void _sendError(WebSocketChannel channel, String message) {
  _send(channel, {'type': 'error', 'message': message});
}

void _send(WebSocketChannel channel, Map<String, dynamic> message) {
  try {
    channel.sink.add(jsonEncode(message));
  } catch (_) {
    // Connexion deja fermee entre-temps -- ignore, onDone/onError nettoiera.
  }
}
