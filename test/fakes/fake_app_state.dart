import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vinland/models/album.dart';
import 'package:vinland/models/pinned_item.dart';
import 'package:vinland/models/playlist.dart';
import 'package:vinland/models/recent_play.dart';
import 'package:vinland/models/track.dart';
import 'package:vinland/providers/app_state.dart';
import 'package:vinland/services/discovery_service.dart';

import 'fake_screen_deps.dart';

/// AppState minimal pour les tests de rendu des ecrans : la bibliotheque
/// vient d'une FakeLibrary, tout le reste (lecteur, Jam, NAS) est absent.
/// Seuls les membres lus au premier rendu des ecrans sont definis.
class FakeAppState extends ChangeNotifier implements AppState {
  FakeAppState(this.lib);

  final FakeLibrary lib;
  final overlays = <Widget>[];

  @override
  List<Track> get allTracks => lib.allTracks;
  @override
  List<Album> get albums => lib.albums;
  @override
  bool get isSyncing => lib.isSyncing;
  @override
  Track? get displayTrack => null;
  @override
  Track? get currentTrack => null;
  @override
  bool get displayIsPlaying => false;
  @override
  bool get isJamActive => false;
  @override
  String? get jamSessionId => null;
  @override
  String? get currentUserId => 'thibault';
  @override
  List<Playlist> get playlists => const [];
  @override
  bool areTracksOffline(List<Track> tracks) => false;
  @override
  bool coverExists(String? path) => false;
  @override
  bool isPinned(PinnedItemType type, String id) => false;
  @override
  void pushOverlay(Widget screen) => overlays.add(screen);
  @override
  void popOverlay() {}
  @override
  Future<void> playTrack(Track track, {List<Track>? trackList}) =>
      lib.playTrack(track, trackList: trackList);
  @override
  void recordRecentPlay(RecentPlay entry) => lib.recordRecentPlay(entry);
  @override
  Future<void> handleTrackDownloaded(String artist, String title,
          {int albumCount = 5}) =>
      lib.handleTrackDownloaded(artist, title);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Monte [screen] comme dans l'app mobile (fond sombre, providers).
Widget hostScreen(Widget screen,
    {required FakeAppState state, required FakeDiscovery discovery}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: state),
      Provider<DiscoveryService>.value(value: discovery),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Material(color: Colors.black, child: screen),
    ),
  );
}
