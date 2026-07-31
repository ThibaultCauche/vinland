import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../screens/artist_screen.dart';
import 'track_tile.dart';

class SearchBarWidget extends StatefulWidget {
  const SearchBarWidget({super.key});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Barre de recherche
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Rechercher',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white54,
                    size: 20,
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.white54,
                            size: 18,
                          ),
                          onPressed: () {
                            _controller.clear();
                            state.clearSearch();
                            _focusNode.requestFocus(); // ← Garde le focus !
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (value) {
                  state.searchQuery = value;
                  state.showSearchResults = value.isNotEmpty;
                  state.notifyListeners();
                },
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    state.setSearchQuery(value);
                  }
                },
              ),
            ),

            // Résultats de recherche
            if (state.showSearchResults && _controller.text.isNotEmpty)
              _buildSearchResults(state)

            // Historique (focus + champ vide + historique non vide)
            else if (_isFocused &&
                _controller.text.isEmpty &&
                state.searchHistory.isNotEmpty)
              _buildSearchHistory(state),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(AppState state) {
    final query = _controller.text.toLowerCase();
    final tracks = state.searchResults;

    // Artistes qui correspondent
    final matchingArtists = <String>{};
    for (final track in state.allTracks) {
      if (track.artist.toLowerCase().contains(query)) {
        matchingArtists.add(track.artist);
      }
    }

    // Albums qui correspondent
    final matchingAlbums = state.albums
        .where((a) =>
            a.title.toLowerCase().contains(query) ||
            a.artist.toLowerCase().contains(query))
        .toList();

    final matchingTracks = state.allTracks
        .where((t) => t.title.toLowerCase().contains(query))
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: tracks.isEmpty && matchingArtists.isEmpty && matchingAlbums.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aucun résultat',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Section Artistes
                if (matchingArtists.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Artistes',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...matchingArtists.take(5).map((artist) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFF3E3E3E),
                          child: Text(
                            artist.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          artist,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onTap: () => _openArtistPage(context, artist),
                      )),
                ],

                // Section Albums
                if (matchingAlbums.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Albums',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...matchingAlbums.take(5).map((album) => ListTile(
                        dense: true,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3E3E3E),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.album,
                            color: Colors.white54,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          album.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${album.artist} · ${album.trackCount} titre${album.trackCount > 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.white38,
                          size: 20,
                        ),
                        onTap: () => _openAlbumPage(context, album),
                      )),
                ],

                // Section Titres
                if (matchingTracks.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Titres',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...matchingTracks.take(10).map((track) => TrackTile(
                        track: track,
                        onTap: () {
                          state.playTrack(track);
                          if (_controller.text.isNotEmpty) {
                            state.setSearchQuery(_controller.text);
                          }
                          _controller.clear();
                          state.clearSearch();
                          _focusNode.unfocus();
                        },
                        onLike: () => state.toggleLike(track.id),
                      )),
                ],
              ],
            ),
    );
  }

  Widget _buildSearchHistory(AppState state) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header avec bouton "Effacer"
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recherches récentes',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                TextButton(
                  onPressed: () => state.clearSearchHistory(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Effacer',
                    style: TextStyle(
                      color: Color(0xFF1DB954),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1, indent: 16),
          ...state.searchHistory.take(8).map((query) => InkWell(
                onTap: () {
                  _controller.text = query;
                  _controller.selection = TextSelection.collapsed(
                    offset: query.length,
                  );
                  state.setSearchQuery(query);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history,
                        color: Colors.white38,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          query,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => state.removeSearchQuery(query),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: Colors.white38,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  void _openArtistPage(BuildContext context, String artistName) {
    _controller.clear();
    context.read<AppState>().clearSearch();
    _focusNode.unfocus();
    context.read<AppState>().pushOverlay(
          ArtistScreen(artistName: artistName),
        );
  }

  void _openAlbumPage(BuildContext context, dynamic album) {
    final state = context.read<AppState>();
    final albumTracks =
        state.allTracks.where((t) => t.album == album.title).toList();

    _controller.clear();
    state.clearSearch();
    _focusNode.unfocus();

    state.pushOverlay(
      Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF121212),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => state.popOverlay(),
          ),
          title: Text(
            album.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: albumTracks.length,
          itemBuilder: (context, index) => TrackTile(
            track: albumTracks[index],
            onTap: () => state.playTrack(
              albumTracks[index],
              trackList: albumTracks,
            ),
            onLike: () => state.toggleLike(albumTracks[index].id),
          ),
        ),
      ),
    );
  }
}
