import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/data/subsonic/subsonic_mappers.dart';
import 'package:vinland/domain/replay_gain.dart';
import 'package:vinland/models/track.dart';

void main() {
  group('volume ReplayGain', () {
    const loudMaster = ReplayGain(trackGain: -8, albumGain: -6);

    test('desactive : volume inchange', () {
      expect(replayGainVolume(loudMaster, ReplayGainMode.off), 1.0);
    });

    test('titre trop fort baisse de son gain (dB -> lineaire)', () {
      expect(replayGainVolume(loudMaster, ReplayGainMode.track),
          closeTo(0.398, 0.001));
      expect(replayGainVolume(loudMaster, ReplayGainMode.album),
          closeTo(0.501, 0.001));
    });

    test('gain manquant : on prend l\'autre', () {
      const albumOnly = ReplayGain(albumGain: -6);
      expect(replayGainVolume(albumOnly, ReplayGainMode.track),
          closeTo(0.501, 0.001));
    });

    test('titre calme : jamais au-dela de 1 (pas de saturation)', () {
      const quiet = ReplayGain(trackGain: 4);
      expect(replayGainVolume(quiet, ReplayGainMode.track), 1.0);
    });

    test('crete connue : le gain ne la pousse pas au-dela de 0 dBFS', () {
      const peaky = ReplayGain(trackGain: -1, trackPeak: 1.25);
      expect(replayGainVolume(peaky, ReplayGainMode.track), 0.8);
    });

    test('titre sans tags : non touche', () {
      expect(replayGainVolume(null, ReplayGainMode.track), 1.0);
    });

    test('gain de base (Opus R128) ajoute au gain du titre', () {
      const opus = ReplayGain(trackGain: -2, baseGain: -4);
      expect(
          replayGainVolume(opus, ReplayGainMode.track), closeTo(0.501, 0.001));
    });
  });

  group('tags lus depuis Navidrome', () {
    test('replayGain, numero de piste et de disque lus et gardes en cache', () {
      final track = trackFromSubsonic({
        'id': 'tr-1',
        'title': 'Enemy',
        'track': 3,
        'discNumber': '2',
        'replayGain': {'trackGain': -7.5, 'albumGain': -6.1, 'trackPeak': 0.98},
      });
      expect(track.trackNumber, 3);
      expect(track.discNumber, 2);
      expect(track.replayGain?.trackGain, -7.5);

      final cached = Track.fromJson(track.toJson());
      expect(cached.trackNumber, 3);
      expect(cached.discNumber, 2);
      expect(cached.replayGain?.albumGain, -6.1);
      expect(cached.replayGain?.trackPeak, 0.98);
    });

    test('vieux serveur ou vieux cache sans ces champs : rien d\'invente', () {
      final track = trackFromSubsonic({'id': 'tr-1', 'replayGain': {}});
      expect(track.replayGain, isNull);
      expect(track.trackNumber, isNull);
      final cached = Track.fromJson({'id': 'x', 'title': 't'});
      expect(cached.replayGain, isNull);
      expect(cached.toJson().containsKey('replayGain'), isFalse);
    });
  });
}
