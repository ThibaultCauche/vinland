import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinland/desktop/taskbar_controls.dart';

class _FakePlayback extends ChangeNotifier implements TaskbarPlayback {
  @override
  bool hasTrack = false;
  @override
  bool isPlaying = false;
  final calls = <String>[];

  void set({bool? track, bool? playing}) {
    hasTrack = track ?? hasTrack;
    isPlaying = playing ?? isPlaying;
    notifyListeners();
  }

  @override
  void togglePlayPause() => calls.add('playPause');
  @override
  Future<void> nextTrack() async => calls.add('next');
  @override
  Future<void> previousTrack() async => calls.add('previous');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vinland/taskbar');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> sent;

  setUp(() {
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  String describe(MethodCall c) => '${c.method}:${c.arguments}';

  test('boutons grises sans titre, puis icone lecture/pause a jour', () {
    final playback = _FakePlayback();
    final controls = TaskbarControls(playback);
    expect(sent.map(describe), ['setEnabled:false', 'setPlaying:false']);

    sent.clear();
    playback.set(track: true);
    playback.set(playing: true);
    expect(sent.map(describe), ['setEnabled:true', 'setPlaying:true']);

    // Une notification sans changement ne renvoie rien au natif.
    sent.clear();
    playback.set(playing: true);
    expect(sent, isEmpty);
    controls.dispose();
  });

  test('les clics natifs pilotent la lecture', () async {
    final playback = _FakePlayback();
    final controls = TaskbarControls(playback);
    for (final button in ['previous', 'playPause', 'next', 'inconnu']) {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('onButton', button)),
        (_) {},
      );
    }
    expect(playback.calls, ['previous', 'playPause', 'next']);
    controls.dispose();
  });
}
