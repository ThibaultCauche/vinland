import '../domain/replay_gain.dart';
import '../services/subsonic_refs.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  // Pour un titre Navidrome, on ne garde qu'une reference sans jeton
  // (SubsonicRefs.stream/cover : id Subsonic du titre et de sa pochette),
  // jamais l'URL complete : elle contient le jeton d'authentification et
  // finissait sinon dans library_<user>.json. filePath/coverPath
  // reconstruisent l'URL a la demande avec l'URL de serveur et le jeton de
  // la session en cours (plus besoin de les "rafraichir" apres un
  // changement VPN <-> Funnel). Pour un fichier local, c'est simplement son
  // chemin.
  String? _fileRef;
  String? _coverRef;

  String? get filePath => SubsonicRefs.resolve(_fileRef);
  set filePath(String? value) => _fileRef = SubsonicRefs.toStorable(value);

  String? get coverPath => SubsonicRefs.resolve(_coverRef);
  set coverPath(String? value) => _coverRef = SubsonicRefs.toStorable(value);

  /// Id Subsonic du titre (null pour un fichier local).
  String? get subsonicId => SubsonicRefs.streamIdOf(_fileRef);

  /// Id Subsonic de la pochette (null pour un fichier local) : cle stable du
  /// cache d'images, independante du jeton (voir coverImageProvider).
  String? get coverArtId => SubsonicRefs.coverIdOf(_coverRef);
  bool isLiked;
  // Variante visuelle du like (coeur double), purement locale -- pas
  // d'equivalent cote Navidrome/Subsonic, contrairement a isLiked qui se
  // synchronise via star.view. Implique isLiked (voir MusicService.
  // toggleSuperLike) : un titre super-like est toujours aussi like.
  bool superLiked;
  int playCount;
  DateTime? lastPlayed;
  DateTime? dateAdded;
  final String? albumId;
  final String? albumArtist;
  final int? year;
  final DateTime? addedToServerAt;
  final String? genre;

  /// Position dans l'album (tag `track`/`discNumber`) : sert a reconnaitre
  /// deux titres qui s'enchainent sur le disque, pour ne pas les fondre
  /// l'un dans l'autre (voir PlayerController, fondu enchaine).
  final int? trackNumber;
  final int? discNumber;

  /// Null si le fichier n'a pas de tags ReplayGain (ou serveur trop ancien).
  final ReplayGain? replayGain;

  /// Format et debit du fichier sur le NAS (Subsonic `suffix`/`bitRate`).
  final String? suffix;
  final int? bitRate;

  static const _lossySuffixes = {'mp3', 'm4a', 'aac', 'ogg', 'opus'};

  /// URL de lecture. Un fichier deja compresse et leger est lu tel quel :
  /// converti a la volee, le flux n'a ni taille ni reprise possible, et une
  /// reconnexion apres une coupure (autre appli qui prend le son, reseau)
  /// le faisait repartir du debut pendant que le compteur continuait
  /// (retour utilisateur). Le reste (FLAC...) reste converti en 192 kbps
  /// pour la 4G (voir NavidromeService.streamMaxBitRateKbps).
  String? get playbackPath {
    final id = subsonicId;
    final raw = SubsonicRefs.rawStreamUrlBuilder;
    if (id != null &&
        raw != null &&
        _lossySuffixes.contains(suffix?.toLowerCase()) &&
        (bitRate ?? 0) > 0 &&
        bitRate! <= 320) {
      return raw(id);
    }
    return filePath;
  }

  /// Vrai pour un titre "fantome" affiche dans les Titres likes qui n'a pas
  /// ete retrouve dans la bibliotheque NAS lors d'un import CSV (voir
  /// AppState.likedTracksWithMissing) : jamais de fichier reel pour un titre
  /// Navidrome/local, donc ce champ nul sert de marqueur -- illisible,
  /// affiche grise et non cliquable dans TrackTile/DesktopTrackRow.
  bool get isPlaceholder => _fileRef == null;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    String? filePath,
    String? coverPath,
    this.isLiked = false,
    this.superLiked = false,
    this.playCount = 0,
    this.lastPlayed,
    this.dateAdded,
    this.albumId,
    this.albumArtist,
    this.year,
    this.addedToServerAt,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.replayGain,
    this.suffix,
    this.bitRate,
  })  : _fileRef = SubsonicRefs.toStorable(filePath),
        _coverRef = SubsonicRefs.toStorable(coverPath);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration.inMilliseconds,
        // Titre Navidrome : uniquement les ids, jamais d'URL (voir _fileRef).
        if (subsonicId != null) 'subsonicId': subsonicId,
        if (coverArtId != null) 'coverArtId': coverArtId,
        if (!SubsonicRefs.isRef(_fileRef)) 'filePath': _fileRef,
        if (!SubsonicRefs.isRef(_coverRef)) 'coverPath': _coverRef,
        'isLiked': isLiked,
        'superLiked': superLiked,
        'playCount': playCount,
        'lastPlayed': lastPlayed?.toIso8601String(),
        'dateAdded': dateAdded?.toIso8601String(),
        'albumId': albumId,
        'albumArtist': albumArtist,
        'year': year,
        'addedToServerAt': addedToServerAt?.toIso8601String(),
        'genre': genre,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (discNumber != null) 'discNumber': discNumber,
        if (replayGain != null) 'replayGain': replayGain!.toJson(),
        if (suffix != null) 'suffix': suffix,
        if (bitRate != null) 'bitRate': bitRate,
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    final rawDuration = json['duration'];
    int ms = 0;
    if (rawDuration is int) {
      ms = rawDuration;
    } else if (rawDuration is double) {
      ms = rawDuration.toInt();
    } else if (rawDuration is String) {
      ms = int.tryParse(rawDuration) ?? 0;
    }
    if (ms < 0) ms = 0;

    DateTime? parseDate(String? key) {
      if (key == null) return null;
      try {
        return DateTime.parse(json[key]);
      } catch (_) {
        return null;
      }
    }

    final id = json['id']?.toString() ?? '';
    // Titre Navidrome d'un vieux cache synchronise hors connexion (URL vide) :
    // l'id du titre suffit a reconstruire les deux references.
    final navidromeId =
        id.startsWith('navidrome_') ? id.substring('navidrome_'.length) : null;
    String? legacyFile = json['filePath']?.toString();
    String? legacyCover = json['coverPath']?.toString();
    if (navidromeId != null && navidromeId.isNotEmpty) {
      if (SubsonicRefs.streamIdOf(legacyFile) == null) {
        legacyFile = SubsonicRefs.stream(navidromeId);
      }
      if (SubsonicRefs.coverIdOf(legacyCover) == null) {
        legacyCover = SubsonicRefs.cover(navidromeId);
      }
    }

    return Track(
      id: id,
      title: json['title']?.toString() ?? 'Inconnu',
      artist: json['artist']?.toString() ?? 'Inconnu',
      album: json['album']?.toString() ?? 'Inconnu',
      duration: Duration(milliseconds: ms),
      // Format 1.3+ : ids seuls. Avant : URL completes avec jeton, converties
      // en references par le constructeur (SubsonicRefs.toStorable) -- le
      // cache est ainsi assaini des le premier chargement puis la premiere
      // sauvegarde.
      filePath: json['subsonicId'] != null
          ? SubsonicRefs.stream(json['subsonicId'].toString())
          : legacyFile,
      coverPath: json['coverArtId'] != null
          ? SubsonicRefs.cover(json['coverArtId'].toString())
          : legacyCover,
      isLiked: json['isLiked'] == true,
      superLiked: json['superLiked'] == true,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayed: parseDate('lastPlayed'),
      dateAdded: parseDate('dateAdded'),
      albumId: json['albumId']?.toString(),
      albumArtist: json['albumArtist']?.toString(),
      year: (json['year'] as num?)?.toInt(),
      addedToServerAt: json['addedToServerAt'] != null
          ? DateTime.tryParse(json['addedToServerAt'].toString())
          : null,
      genre: json['genre']?.toString(),
      trackNumber: (json['trackNumber'] as num?)?.toInt(),
      discNumber: (json['discNumber'] as num?)?.toInt(),
      replayGain: ReplayGain.fromJson(json['replayGain']),
      suffix: json['suffix']?.toString(),
      bitRate: (json['bitRate'] as num?)?.toInt(),
    );
  }
}
