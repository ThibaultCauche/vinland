import 'package:flutter/foundation.dart';

import '../../models/album.dart';
import '../../models/recent_play.dart';
import '../../models/track.dart';

/// Ce dont les view-models d'ecran (lib/features/) ont besoin de l'app, et
/// rien de plus : la bibliotheque NAS, son etat de synchro, la lecture et
/// l'historique "Recemment ecoute". AppState l'implemente ; les tests
/// fournissent une fausse bibliotheque en memoire (test/fakes/) sans
/// lecteur audio ni NAS.
abstract class LibraryPort implements Listenable {
  List<Track> get allTracks;
  List<Album> get albums;
  bool get isSyncing;

  /// Fait apparaitre un titre tout juste telecharge par le worker NAS.
  Future<void> handleTrackDownloaded(String artist, String title);

  void recordRecentPlay(RecentPlay entry);

  Future<void> playTrack(Track track, {List<Track>? trackList});
}
