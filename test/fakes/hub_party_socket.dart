// Le vrai relais de soiree (services/jam-relay/lib/party/), branche en memoire sur
// le client de l'app : les tests de l'app passent par les memes regles de
// file, de jetons et de droits que le NAS, sans reseau. jam_relay est un
// paquet a part (sa propre CI) ; on importe ses sources directement, elles
// ne dependent que de crypto, deja dans l'app.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// ignore: avoid_relative_lib_imports
import '../../services/jam-relay/lib/party/catalog.dart';
// ignore: avoid_relative_lib_imports
import '../../services/jam-relay/lib/party/party.dart' as relay;
// ignore: avoid_relative_lib_imports
import '../../services/jam-relay/lib/party/party_hub.dart';
// ignore: avoid_relative_lib_imports
import '../../services/jam-relay/lib/party/party_token.dart';
import 'package:vinland/services/party/party_socket.dart';

/// Catalogue Navidrome factice : 's1'..'s20' = « Titre 1 »..« Titre 20 ».
class FakePartyCatalog implements PartyCatalog {
  final songs = <String, relay.PartySong>{
    for (var i = 1; i <= 20; i++)
      's$i': relay.PartySong(
          songId: 's$i', title: 'Titre $i', artist: 'Artiste $i'),
  };
  static const goodToken = 'bon-jeton';

  @override
  Future<List<relay.PartySong>> search(String query, {int limit = 20}) async =>
      songs.values
          .where((s) => s.title.toLowerCase().contains(query.toLowerCase()))
          .take(limit)
          .toList();

  @override
  Future<relay.PartySong?> song(String songId) async => songs[songId];

  @override
  Future<CoverImage?> cover(String coverId, int size) async =>
      CoverImage(Uint8List(0), 'image/jpeg');

  @override
  Future<bool> verifyHost(HostAuth auth) async => auth.token == goodToken;
}

/// Identifiants que le faux Navidrome accepte.
const goodHostAuth = {
  'u': 'thibault',
  't': FakePartyCatalog.goodToken,
  's': 'sel'
};

/// Un relais en memoire et les connexions ouvertes vers lui.
class InMemoryPartyRelay {
  InMemoryPartyRelay({DateTime Function()? now})
      : hub = PartyHub(
          signer: PartyTokenSigner(List.filled(32, 3)),
          catalog: FakePartyCatalog(),
          now: now,
        );

  final PartyHub hub;
  final sockets = <HubPartySocket>[];

  /// Faux si le relais est « eteint » (connexion refusee).
  bool reachable = true;

  Future<PartySocket> connect(String url) async {
    if (!reachable) throw StateError('relais injoignable');
    final socket = HubPartySocket._(this);
    sockets.add(socket);
    return socket;
  }

  /// Coupe toutes les connexions cote relais (Wi-Fi qui saute).
  void dropAll() {
    for (final socket in sockets.toList()) {
      socket.dropFromRelay();
    }
  }
}

/// Connexion vue par l'app ; [_RelaySide] est la meme vue par le relais.
class HubPartySocket implements PartySocket {
  HubPartySocket._(this._relay) {
    _side = _RelaySide(this);
  }

  final InMemoryPartyRelay _relay;
  late final _RelaySide _side;
  final _incoming = StreamController<Map<String, dynamic>>();
  bool _closed = false;

  /// Messages envoyes par l'app, pour les verifications.
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<Map<String, dynamic>> get messages => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) {
    if (_closed) return;
    // Aller-retour JSON : memes types que sur le vrai reseau.
    final raw = jsonEncode(message);
    sent.add(jsonDecode(raw) as Map<String, dynamic>);
    unawaited(_relay.hub.handle(
      _side,
      jsonDecode(raw) as Map<String, dynamic>,
      rawLength: raw.length,
    ));
  }

  @override
  Future<void> close() async => _shutdown();

  /// Coupure cote relais : l'app voit seulement son flux se terminer.
  void dropFromRelay() => _shutdown();

  void _shutdown() {
    if (_closed) return;
    _closed = true;
    _relay.sockets.remove(this);
    _relay.hub.disconnected(_side);
    unawaited(_incoming.close());
  }

  void _deliver(Map<String, dynamic> message) {
    if (_closed) return;
    _incoming.add(jsonDecode(jsonEncode(message)) as Map<String, dynamic>);
  }
}

class _RelaySide implements PartyConnection {
  _RelaySide(this._socket);
  final HubPartySocket _socket;

  @override
  void send(Map<String, dynamic> message) => _socket._deliver(message);

  @override
  void close() => _socket._shutdown();
}
