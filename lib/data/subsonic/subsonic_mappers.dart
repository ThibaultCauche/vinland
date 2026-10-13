import '../../domain/replay_gain.dart';
import '../../models/track.dart';
import '../../services/subsonic_refs.dart';

/// Convertit un titre Subsonic (`child` JSON) en [Track].
///
/// [albumArtist] et [albumId] priment sur ce que dit le titre quand
/// l'appelant les connait deja (ex : l'album d'ou vient le titre).
Track trackFromSubsonic(Map<String, dynamic> json,
    {String? albumArtist, String? albumId}) {
  final id = json['id']?.toString() ?? '';
  final durationSec = json['duration'] ?? 180;
  return Track(
    id: 'navidrome_$id',
    title: json['title']?.toString() ?? 'Inconnu',
    artist: json['artist']?.toString() ?? 'Inconnu',
    album: json['album']?.toString() ?? 'Inconnu',
    duration: Duration(
        seconds: durationSec is int
            ? durationSec
            : int.tryParse(durationSec.toString()) ?? 180),
    // References sans jeton : l'URL est construite a la demande (voir
    // SubsonicRefs). La pochette suit l'id coverArt du serveur quand il
    // est fourni (partage entre les titres d'un album), sinon l'id du
    // titre comme avant.
    filePath: SubsonicRefs.stream(id),
    coverPath: SubsonicRefs.cover(json['coverArt']?.toString() ?? id),
    isLiked: json['starred'] != null,
    // json['parent'] est l'ID du dossier physique sur le NAS, pas l'ID
    // d'album ID3 attendu par star.view/getStarred2 (cause du bug "liker un
    // album ne marche pas") : on prend d'abord l'albumId connu de
    // l'appelant, puis celui du titre, et le dossier seulement en dernier.
    albumId:
        albumId ?? json['albumId']?.toString() ?? json['parent']?.toString(),
    albumArtist: albumArtist ??
        json['displayAlbumArtist']?.toString() ??
        json['albumArtist']?.toString(),
    year: json['year'] is int
        ? json['year'] as int
        : int.tryParse(json['year']?.toString() ?? ''),
    addedToServerAt: json['created'] != null
        ? DateTime.tryParse(json['created'].toString())
        : null,
    genre: json['genre']?.toString(),
    trackNumber: _intOrNull(json['track']),
    discNumber: _intOrNull(json['discNumber']),
    // Extension OpenSubsonic (Navidrome 0.53+) : absent sur un vieux serveur.
    replayGain: ReplayGain.fromJson(json['replayGain']),
    suffix: json['suffix']?.toString(),
    bitRate: _intOrNull(json['bitRate']),
  );
}

int? _intOrNull(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '');

/// Resume d'un album tel que l'utilise MusicService.
Map<String, dynamic> albumSummaryFromSubsonic(Map<String, dynamic> album) => {
      'id': album['id'],
      'name': album['name'],
      'artist': album['artist'],
      'coverArt': album['coverArt'],
      'songCount': album['songCount'],
      'duration': album['duration'],
      'year': album['year'],
      'genre': album['genre'],
    };

/// Resume d'une playlist tel que l'utilise MusicService.
Map<String, dynamic> playlistSummaryFromSubsonic(Map<String, dynamic> pl) => {
      'id': pl['id']?.toString() ?? '',
      'name': pl['name']?.toString() ?? '',
      'owner': pl['owner']?.toString() ?? '',
      'public': pl['public'] == true,
      'comment': pl['comment']?.toString() ?? '',
      'songCount': pl['songCount'] ?? 0,
      'changed': pl['changed']?.toString() ?? '',
    };
