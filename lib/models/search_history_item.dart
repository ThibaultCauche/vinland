import '../services/subsonic_refs.dart';

class SearchHistoryItem {
  final String query;
  final String type; // 'artist' | 'album' | 'track'
  final String? id;
  final String? name;
  final String? subtitle;
  // Reference sans jeton si l'image vient de Navidrome (voir SubsonicRefs) ;
  // imageUrl rend l'URL de la session en cours.
  final String? _imageRef;
  String? get imageUrl => SubsonicRefs.resolve(_imageRef);
  final int timestamp;

  SearchHistoryItem({
    required this.query,
    required this.type,
    this.id,
    this.name,
    this.subtitle,
    String? imageUrl,
    int? timestamp,
  })  : _imageRef = SubsonicRefs.toStorable(imageUrl),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory SearchHistoryItem.artist(
    String name,
    String id, {
    String? query,
    String? imageUrl,
  }) =>
      SearchHistoryItem(
        query: query ?? name,
        type: 'artist',
        id: id,
        name: name,
        imageUrl: imageUrl,
      );

  factory SearchHistoryItem.album(
    String title,
    String id,
    String artistName, {
    String? query,
    String? imageUrl,
  }) =>
      SearchHistoryItem(
        query: query ?? '$title $artistName',
        type: 'album',
        id: id,
        name: title,
        subtitle: artistName,
        imageUrl: imageUrl,
      );

  factory SearchHistoryItem.track(
    String title,
    String id,
    String artistName, {
    String? query,
    String? imageUrl,
  }) =>
      SearchHistoryItem(
        query: query ?? '$title $artistName',
        type: 'track',
        id: id,
        name: title,
        subtitle: artistName,
        imageUrl: imageUrl,
      );

  Map<String, dynamic> toJson() => {
        'query': query,
        'type': type,
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'imageUrl': _imageRef,
        'timestamp': timestamp,
      };

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) =>
      SearchHistoryItem(
        query: json['query']?.toString() ?? '',
        type: json['type']?.toString() ?? 'track',
        id: json['id']?.toString(),
        name: json['name']?.toString(),
        subtitle: json['subtitle']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        timestamp: json['timestamp'] is int
            ? json['timestamp']
            : DateTime.now().millisecondsSinceEpoch,
      );

  String get displayName => name ?? query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchHistoryItem &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          id == other.id;

  @override
  int get hashCode => type.hashCode ^ id.hashCode;
}
