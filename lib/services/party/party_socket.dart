import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'party_models.dart';

/// Connexion au relais vue par PartyController : une interface pour que le
/// controleur se teste avec un faux relais en memoire (voir
/// test/fakes/fake_party_relay.dart).
abstract class PartySocket {
  /// Messages JSON recus ; le flux se termine quand la connexion tombe.
  Stream<Map<String, dynamic>> get messages;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

typedef PartySocketConnector = Future<PartySocket> Function(String url);

/// Connexion dediee a la soiree, a part de celle du Jam : plus simple a
/// fermer proprement (voir docs/soiree-protocole.md).
class WebSocketPartySocket implements PartySocket {
  WebSocketPartySocket._(this._channel);
  final WebSocketChannel _channel;

  static Future<PartySocket> connect(String url) async {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    await channel.ready.timeout(const Duration(seconds: 8));
    return WebSocketPartySocket._(channel);
  }

  @override
  Stream<Map<String, dynamic>> get messages =>
      _channel.stream.transform(StreamTransformer.fromHandlers(
        handleData: (raw, sink) {
          if (raw is! String) return;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) sink.add(decoded.cast<String, dynamic>());
          } catch (_) {
            // Message illisible : ignore, comme le relais le fait.
          }
        },
        // Une erreur reseau = connexion perdue : le controleur le voit a la
        // fin du flux et tente de revenir avec son jeton.
        handleError: (_, __, sink) => sink.close(),
      ));

  @override
  void send(Map<String, dynamic> message) =>
      _channel.sink.add(jsonEncode(message));

  @override
  Future<void> close() async {
    try {
      await _channel.sink.close();
    } catch (_) {}
  }
}

/// Place gardee pour revenir dans la soiree apres une coupure ou un
/// redemarrage de l'app (le telephone de l'hote qui s'eteint en pleine
/// soiree, par exemple).
class PartySeat {
  final String relayUrl;
  final String token;
  final PartyRole role;
  final String partyName;
  final DateTime expiresAt;

  const PartySeat({
    required this.relayUrl,
    required this.token,
    required this.role,
    required this.partyName,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'relayUrl': relayUrl,
        'token': token,
        'role': role.name,
        'partyName': partyName,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };

  static PartySeat? fromJson(Object? json) {
    if (json is! Map) return null;
    final relay = json['relayUrl'], token = json['token'];
    final expires = json['expiresAt'];
    if (relay is! String || token is! String || expires is! int) return null;
    return PartySeat(
      relayUrl: relay,
      token: token,
      role: json['role'] == 'host' ? PartyRole.host : PartyRole.guest,
      partyName: json['partyName'] is String ? json['partyName'] as String : '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires),
    );
  }
}

abstract class PartySeatStore {
  Future<PartySeat?> load();
  Future<void> save(PartySeat? seat);
}

/// Le jeton ne vaut que pour une soiree, jusqu'a sa fin (6 h par defaut) :
/// les preferences suffisent, pas besoin du coffre securise.
class PrefsPartySeatStore implements PartySeatStore {
  static const _key = 'vinland_party_seat';

  @override
  Future<PartySeat?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return PartySeat.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PartySeat? seat) async {
    final prefs = await SharedPreferences.getInstance();
    if (seat == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(seat.toJson()));
    }
  }
}
