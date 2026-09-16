import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/discovered_artist.dart';
import '../providers/app_state.dart';
import '../services/discovery_service.dart';
import '../services/matching_service.dart';
import 'cover_image.dart';

/// Photo reelle d'un artiste (recherche Deezer, mise en cache en memoire
/// pour toute la session) -- se rabat sur [fallbackCoverPath] (typiquement
/// la cover d'un de ses albums/titres) tant qu'elle n'est pas trouvee ou en
/// l'absence de match. Partagee entre desktop et mobile : avant cette
/// extraction, seul le desktop l'utilisait (etagere "Artistes du moment",
/// badge artiste d'un album...) -- l'equivalent mobile (badge artiste sous
/// le titre d'un album) affichait juste la cover de l'ALBUM a la place,
/// meme bug deja corrige cote desktop (retour utilisateur : "ce badge
/// montrait la cover de l'album au lieu du compositeur/artiste").
class ArtistAvatar extends StatefulWidget {
  final String artistName;
  final String? fallbackCoverPath;
  final double size;

  const ArtistAvatar({
    super.key,
    required this.artistName,
    required this.fallbackCoverPath,
    required this.size,
  });

  @override
  State<ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<ArtistAvatar> {
  static final Map<String, String?> _photoCache = {};
  String? _photoUrl;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final key = MatchingService.normalize(widget.artistName);
    if (_photoCache.containsKey(key)) {
      _photoUrl = _photoCache[key];
      _loaded = true;
    } else {
      _load(key);
    }
  }

  Future<void> _load(String key) async {
    String? url;
    try {
      final results =
          await DiscoveryService().searchArtists(widget.artistName, limit: 5);
      DiscoveredArtist? match;
      for (final a in results) {
        if (MatchingService.artistsMatch(a.name, widget.artistName)) {
          match = a;
          break;
        }
      }
      url = (match ?? (results.isNotEmpty ? results.first : null))
          ?.pictureBigUrl;
    } catch (_) {
      // ponytail: pas de retry -- l'avatar reste sur la cover de repli, deja
      // un rendu correct.
    }
    _photoCache[key] = url;
    if (mounted) {
      setState(() {
        _photoUrl = url;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _photoUrl;
    if (_loaded && url != null) {
      return ClipOval(
        child: Image.network(
          url,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ClipOval(child: _fallback(context)),
        ),
      );
    }
    return ClipOval(child: _fallback(context));
  }

  Widget _fallback(BuildContext context) {
    final path = widget.fallbackCoverPath;
    final exists = context.read<AppState>().coverExists(path);
    return Container(
      width: widget.size,
      height: widget.size,
      color: const Color(0xFF2A2A2A),
      child: exists && path != null
          ? Image(
              image: coverImageProvider(context,
                  path: path, width: widget.size, height: widget.size),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.person,
                  color: Colors.white54, size: widget.size * 0.5),
            )
          : Icon(Icons.person, color: Colors.white54, size: widget.size * 0.5),
    );
  }
}
