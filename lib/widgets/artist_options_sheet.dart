import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/pinned_item.dart';
import '../models/recent_play.dart';
import '../screens/artist_screen.dart';
import '../services/matching_service.dart';
import 'bottom_sheet_common.dart';

/// Quand un champ artiste NAS contient plusieurs noms ("A / B", "A, B"),
/// laisse choisir lequel ouvrir plutot que de forcer le premier -- utilise
/// partout ou on navigue vers un artiste depuis un champ texte brut.
void showArtistPicker(BuildContext context, String artistsField) {
  final artists = artistsField
      .split(RegExp(r'[/&,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (artists.length <= 1) {
    context.read<AppState>().pushOverlay(ArtistScreen(artistName: artistsField));
    return;
  }

  showOptionsSheet(context, builder: (ctx) => [
    const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Selectionner un artiste',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    const Divider(color: Color(0xFF2A2A2A), height: 1),
    ...artists.map((artist) => ListTile(
          leading: const Icon(Icons.person, color: Colors.white),
          title: Text(artist, style: const TextStyle(color: Colors.white)),
          onTap: () {
            Navigator.pop(ctx);
            context.read<AppState>().pushOverlay(ArtistScreen(artistName: artist));
          },
        )),
    const SizedBox(height: 8),
  ]);
}

/// Feuille d'options d'un artiste (clic long sur sa tuile) -- pas d'action
/// "like" (pas de concept de suivi d'artiste dans l'app) ni "lecture" directe
/// (le tap simple ouvre deja sa page), juste ce qui n'existe pas ailleurs :
/// lecture aleatoire rapide, et empiler ses titres dans la file.
void showArtistOptions(BuildContext context, String artistName,
    {String? coverPath}) {
  final state = context.read<AppState>();
  bool artistMatch(String? field) =>
      MatchingService.artistFieldContains(field, artistName);
  final tracks = state.allTracks.where((t) => artistMatch(t.artist)).toList();

  showOptionsSheet(context, builder: (ctx) => [
    BottomSheetHeader(
      coverPath: coverPath,
      title: artistName,
      subtitle: 'Artiste',
      fallbackIcon: Icons.person,
    ),
    const Divider(color: Color(0xFF2A2A2A), height: 1),
    SheetTile(
      icon: state.isPinned(PinnedItemType.artist, artistName)
          ? Icons.push_pin
          : Icons.push_pin_outlined,
      label: state.isPinned(PinnedItemType.artist, artistName)
          ? "Desepingler de l'accueil"
          : "Epingler a l'accueil",
      onTap: () {
        Navigator.pop(ctx);
        state.togglePin(PinnedItem(
          type: PinnedItemType.artist,
          id: artistName,
          title: artistName,
          subtitle: 'Artiste',
        ));
      },
    ),
    SheetTile(
      icon: Icons.shuffle,
      label: 'Lecture aleatoire',
      onTap: () {
        Navigator.pop(ctx);
        if (tracks.isEmpty) return;
        state.recordRecentPlay(RecentPlay(
          type: RecentPlayType.artist,
          id: artistName,
          title: artistName,
          subtitle: 'Artiste',
          coverPath: coverPath,
          playedAt: DateTime.now(),
        ));
        final shuffled = List.of(tracks)..shuffle();
        state.playTrack(shuffled.first, trackList: shuffled);
      },
    ),
    SheetTile(
      icon: Icons.playlist_play,
      label: 'Lire ensuite',
      onTap: () {
        Navigator.pop(ctx);
        for (final t in tracks.reversed) {
          state.playNext(t);
        }
      },
    ),
    SheetTile(
      icon: Icons.playlist_add,
      label: "Ajouter a la file d'attente",
      onTap: () {
        Navigator.pop(ctx);
        for (final t in tracks) {
          state.addToQueue(t);
        }
      },
    ),
    const SizedBox(height: 8),
  ]);
}
