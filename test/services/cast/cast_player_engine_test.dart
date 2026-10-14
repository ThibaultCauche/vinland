import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/services/cast/cast_channel.dart';
import 'package:vinland/services/cast/cast_player_engine.dart';
import 'package:vinland/services/player_engine.dart';

import '../../fakes/fake_cast_receiver.dart';

const _track = PlayerQueueItem(
  path: 'http://nas:30043/rest/stream.view?id=42',
  isRemote: true,
  title: 'Get Lucky',
  artist: 'Daft Punk',
  album: 'Random Access Memories',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('lance le lecteur media par defaut et s\'y connecte', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    expect(
        receiver.types, containsAllInOrder(['CONNECT', 'LAUNCH', 'CONNECT']));
    expect(receiver.received.last.destinationId, FakeCastReceiver.transportId);
    expect(engine.deviceVolume, 0.4);
    await engine.disconnect(stopReceiver: false);
  });

  test('refuse si la Chromecast ne lance pas le lecteur', () async {
    final receiver = FakeCastReceiver(refuseLaunch: true);
    expect(CastPlayerEngine.launch(receiver.channel), throwsStateError);
  });

  test('charge le titre avec sa fiche, puis lecture et pause', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    final playing = <bool>[];
    engine.playingStream.listen(playing.add);

    await engine.setAudioSources([_track], initialIndex: 0);
    final load = receiver.received.firstWhere((m) => m.type == 'LOAD').json!;
    final media = load['media'] as Map;
    expect(media['contentId'], _track.path);
    expect((media['metadata'] as Map)['title'], 'Get Lucky');
    expect((media['metadata'] as Map)['artist'], 'Daft Punk');
    expect(load['autoplay'], isFalse);
    expect(engine.hasSource, isTrue);
    await _settle();
    expect(engine.duration, const Duration(seconds: 200));

    await engine.play();
    await _settle();
    expect(engine.playing, isTrue);
    expect(receiver.types, contains('PLAY'));

    await engine.pause();
    await _settle();
    expect(engine.playing, isFalse);
    expect(playing, [true, false]);
    await engine.disconnect(stopReceiver: false);
  });

  test('la fin du titre sur la tele fait avancer la file, une seule fois',
      () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    var completed = 0;
    engine.completedStream.listen((_) => completed++);
    await engine.setAudioSources([_track], initialIndex: 0);
    await engine.play();

    receiver.mediaStatus('IDLE', idleReason: 'FINISHED');
    receiver.mediaStatus('IDLE', idleReason: 'FINISHED');
    await _settle();
    expect(completed, 1);
    expect(engine.processingState, AudioProcessingState.completed);

    // Etat en retard du titre precedent apres un nouveau chargement.
    await engine.setAudioSources([_track], initialIndex: 0);
    receiver.mediaStatus('IDLE', idleReason: 'FINISHED', session: 1);
    await _settle();
    expect(completed, 1);
    await engine.disconnect(stopReceiver: false);
  });

  test('un titre refuse fait echouer le chargement', () async {
    final receiver = FakeCastReceiver(failLoad: true);
    final engine = await CastPlayerEngine.launch(receiver.channel);
    await expectLater(
      engine.setAudioSources([_track], initialIndex: 0),
      throwsStateError,
    );
    await engine.disconnect(stopReceiver: false);
  });

  test('un fichier local n\'est pas envoye a la Chromecast', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    await expectLater(
      engine.setAudioSources(
        [const PlayerQueueItem(path: '/music/a.mp3', isRemote: false)],
        initialIndex: 0,
      ),
      throwsStateError,
    );
    expect(receiver.types, isNot(contains('LOAD')));
    await engine.disconnect(stopReceiver: false);
  });

  test(
      'un titre telecharge passe sur la Chromecast par son adresse sur le '
      'serveur (sinon le blind test coupait la diffusion)', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    await engine.setAudioSources(
      [
        const PlayerQueueItem(
          path: '/offline/a.mp3',
          isRemote: false,
          streamUrl: 'http://nas:4533/rest/stream?id=a',
        ),
      ],
      initialIndex: 0,
    );
    final load = receiver.received.lastWhere((m) => m.type == 'LOAD').json!;
    expect((load['media'] as Map)['contentId'],
        'http://nas:4533/rest/stream?id=a');
    expect(engine.hasSource, isTrue);
    await engine.disconnect(stopReceiver: false);
  });

  test('seek et volume partent vers la Chromecast', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    await engine.setAudioSources([_track], initialIndex: 0);
    await engine.seek(const Duration(seconds: 90));
    expect(engine.position, const Duration(seconds: 90));
    final seek = receiver.received.lastWhere((m) => m.type == 'SEEK').json!;
    expect(seek['currentTime'], 90);
    expect(seek['mediaSessionId'], receiver.mediaSessionId);

    await engine.setVolume(0.7);
    await _settle();
    expect(receiver.volume, 0.7);
    expect(engine.deviceVolume, 0.7);
    await engine.disconnect(stopReceiver: false);
  });

  test('la tele qui ferme le lecteur termine la diffusion', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    final ended = Completer<void>();
    engine.ended.listen((_) => ended.complete());
    receiver.closeApp();
    await ended.future.timeout(const Duration(seconds: 1));
    expect(engine.isEnded, isTrue);
    await engine.disconnect();
  });

  test('une connexion perdue termine la diffusion', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    await receiver.disconnectSocket();
    await receiver.channel.done;
    await _settle();
    expect(engine.isEnded, isTrue);
  });

  test('deconnecter arrete le lecteur sur la tele', () async {
    final receiver = FakeCastReceiver();
    final engine = await CastPlayerEngine.launch(receiver.channel);
    unawaited(engine.disconnect());
    await _settle();
    final stop = receiver.received.lastWhere(
        (m) => m.namespace == CastNamespace.receiver && m.type == 'STOP');
    expect(stop.json?['sessionId'], FakeCastReceiver.sessionId);
  });

  test('la Chromecast reçoit un PONG a chaque PING', () async {
    final receiver = FakeCastReceiver();
    receiver.send(CastNamespace.heartbeat, 'receiver-0', {'type': 'PING'});
    await _settle();
    expect(receiver.types, contains('PONG'));
    await receiver.channel.close();
  });
}
