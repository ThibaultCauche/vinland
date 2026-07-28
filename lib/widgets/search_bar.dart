import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
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
          children: [
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
                  prefixIcon:
                      const Icon(Icons.search, color: Colors.white54, size: 20),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.white54, size: 18),
                          onPressed: () {
                            _controller.clear();
                            state.clearSearch();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (value) {
                  // Ne sauvegarde PAS dans l'historique à chaque frappe
                  state.searchQuery = value;
                  state.showSearchResults = value.isNotEmpty;
                  state.notifyListeners();
                },
                onSubmitted: (value) {
                  // Sauvegarde SEULEMENT quand on appuie sur Entrée
                  if (value.isNotEmpty) {
                    state.setSearchQuery(value);
                  }
                },
              ),
            ),
            // Affiche les résultats de recherche si on a tapé quelque chose
            if (state.showSearchResults && _controller.text.isNotEmpty)
              _buildSearchResults(state)
            // Affiche l'historique UNIQUEMENT si le champ est focus ET vide
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
    final tracks = state.searchResults;

    // Cherche aussi les artistes correspondants
    final artists = <String>{};
    for (final track in tracks) {
      artists.add(track.artist);
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: tracks.isEmpty && artists.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aucun résultat',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                // Section Artistes
                if (artists.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Artistes',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ...artists.take(3).map((artist) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.person,
                            color: Colors.white54, size: 20),
                        title: Text(
                          artist,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white38, size: 20),
                        onTap: () {
                          _openArtistPage(context, artist);
                          _controller.clear();
                          state.clearSearch();
                          _focusNode.unfocus();
                        },
                      )),
                ],
                // Section Titres
                if (tracks.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Titres',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ...tracks.take(10).map((track) => TrackTile(
                        track: track,
                        onTap: () {
                          state.playTrack(track);
                          // Sauvegarde la recherche complète quand on clique sur un titre
                          if (_controller.text.isNotEmpty) {
                            state.addSearchQuery(_controller.text);
                          }
                          _controller.clear();
                          state.clearSearch();
                          _focusNode.unfocus();
                        },
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
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Recherches récentes',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ...state.searchHistory.take(5).map((query) => ListTile(
                dense: true,
                leading:
                    const Icon(Icons.history, color: Colors.white38, size: 20),
                title: Text(
                  query,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                onTap: () {
                  _controller.text = query;
                  state.setSearchQuery(query);
                },
              )),
        ],
      ),
    );
  }

  void _openArtistPage(BuildContext context, String artistName) {
    final state = context.read<AppState>();
    final artistTracks =
        state.allTracks.where((t) => t.artist == artistName).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            title:
                Text(artistName, style: const TextStyle(color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView.builder(
            itemCount: artistTracks.length,
            itemBuilder: (context, index) => TrackTile(
              track: artistTracks[index],
              onTap: () =>
                  state.playTrack(artistTracks[index], trackList: artistTracks),
              onLike: () => state.toggleLike(artistTracks[index].id),
            ),
          ),
        ),
      ),
    );
  }
}
