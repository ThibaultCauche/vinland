import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/party/party_link.dart';
import 'package:vinland/services/party/party_models.dart';

void main() {
  group('invitation (QR code)', () {
    test('aller-retour du lien vinland://soiree', () {
      const invite =
          PartyInvite(relayUrl: 'wss://nas.example.ts.net/jam', code: 'K7QX2M');
      final parsed = PartyInvite.tryParse(invite.toString());
      expect(parsed?.relayUrl, 'wss://nas.example.ts.net/jam');
      expect(parsed?.code, 'K7QX2M');
    });

    test("un QR d'une autre appli n'est pas une invitation", () {
      expect(PartyInvite.tryParse('https://exemple.fr/?code=K7QX2M'), isNull);
      expect(PartyInvite.tryParse('vinland://track/42'), isNull);
      expect(PartyInvite.tryParse('bonjour'), isNull);
    });

    test(
        'un relais qui ne parle pas WebSocket ou cache des identifiants '
        'est refuse', () {
      expect(
          PartyInvite.tryParse(
              'vinland://soiree?relay=https://nas/jam&code=K7QX2M'),
          isNull);
      expect(
          PartyInvite.tryParse(
              'vinland://soiree?relay=wss://moi:secret@nas/jam&code=K7QX2M'),
          isNull);
    });
  });

  group('code tape a la main', () {
    test('minuscules, espaces et tirets sont acceptes', () {
      expect(normalizePartyCode(' k7q-x2m '), 'K7QX2M');
    });

    test('0, O, 1, I et L ne sont jamais dans un code', () {
      expect(normalizePartyCode('K7QX20'), isNull);
      expect(normalizePartyCode('K7QXIL'), isNull);
      expect(normalizePartyCode('K7QX2'), isNull);
    });
  });

  test('adresse du relais deduite du serveur Navidrome', () {
    expect(relayUrlFromServer('https://nas.example.ts.net'),
        'wss://nas.example.ts.net/jam');
    expect(relayUrlFromServer('http://192.168.1.10:4533'),
        'ws://192.168.1.10:4533/jam');
    expect(relayUrlFromServer(null), isNull);
  });

  test('pochette servie par le relais, en https derriere wss', () {
    final uri = partyCoverUri('wss://nas.example.ts.net/jam', 'al-7', size: 96);
    expect(uri.toString(),
        'https://nas.example.ts.net/jam/party/cover/al-7?size=96');
  });

  group('lecture tolerante des messages', () {
    test('un queue_state avec des champs manquants ne plante pas', () {
      final state = PartyQueueState.fromJson({
        'items': [
          {'id': 'i1', 'songId': 's1'},
          'pas un objet',
        ],
      });
      expect(state.items.single.song.title, '?');
      expect(state.items.single.score, 0);
      expect(state.hostOnline, isTrue);
    });

    test('un relais de la session 16 (sans votesEnabled) garde les votes', () {
      expect(
          PartyRules.fromJson({'maxPendingPerGuest': 2}).votesEnabled, isTrue);
    });
  });

  group('recap', () {
    test('la playlist porte la date du debut de soiree', () {
      expect(partyRecapName(DateTime(2026, 10, 17, 21, 30)), 'Soirée du 17/10');
    });

    test('une soiree commencee apres minuit compte pour la veille', () {
      expect(partyRecapName(DateTime(2026, 11, 1, 1, 15)), 'Soirée du 31/10');
    });

    test('description : les invites du plus au moins actif, puis hote et radio',
        () {
      PartyPlayed p(String by) => PartyPlayed(
          song: const PartySong(songId: 's', title: 't'),
          by: by,
          at: DateTime(2026));
      expect(
          partyRecapComment([p('Tom'), p(''), p('Léa'), p('Radio'), p('Léa')]),
          "Proposé par : Léa (2), Tom (1), l'hôte (1), la radio (1)");
      expect(partyRecapComment([]), '');
    });

    test('un recap enregistre se relit tel quel', () {
      final played = PartyPlayed(
        song: const PartySong(
            songId: 's1', title: 'One', artist: 'U2', coverId: 'al-1'),
        by: 'Léa',
        at: DateTime(2026, 10, 17, 22),
      );
      final back = PartyPlayed.fromJson(played.toJson())!;
      expect(back.song.coverId, 'al-1');
      expect(back.by, 'Léa');
      expect(back.at, played.at);
      expect(PartyPlayed.fromJson({'title': 'sans id'}), isNull);
    });
  });
}
