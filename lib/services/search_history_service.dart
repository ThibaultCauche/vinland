import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/search_history_item.dart';

class SearchHistoryService {
  static final SearchHistoryService _instance =
      SearchHistoryService._internal();
  factory SearchHistoryService() => _instance;
  SearchHistoryService._internal();

  List<SearchHistoryItem> _history = [];
  bool _loaded = false;

  List<SearchHistoryItem> get history => List.unmodifiable(_history);
  String? _currentUserId;
  void setCurrentUser(String? userId) {
    _currentUserId = userId;
    _loaded = false;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _load();
    _loaded = true;
  }

  Future<String> _getFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = _currentUserId != null
        ? 'search_history_$_currentUserId.json'
        : 'search_history_v2.json';
    return p.join(appDir.path, fileName);
  }

  Future<void> _load() async {
    final path = await _getFilePath();
    final file = File(path);
    if (!await file.exists()) {
      await _migrateFromOldFormat();
      return;
    }
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      _history = data
          .map((e) => SearchHistoryItem.fromJson(e as Map<String, dynamic>))
          .where(
              (item) => item.type != 'query') // ignore anciennes entrées texte
          .toList();
    } catch (e) {
      _history = [];
    }
  }

  Future<void> _migrateFromOldFormat() async {
    final appDir = await getApplicationDocumentsDirectory();
    final oldPath = p.join(appDir.path, 'search_history.json');
    final oldFile = File(oldPath);
    if (await oldFile.exists()) {
      try {
        await oldFile.delete();
      } catch (_) {}
    }
    _history = [];
  }

  Future<void> _save() async {
    final path = await _getFilePath();
    final file = File(path);
    await file
        .writeAsString(jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  Future<void> add(SearchHistoryItem item) async {
    await ensureLoaded();
    if (item.type == 'query')
      return; // on n'enregistre plus les requêtes brutes
    _history.removeWhere((h) => h == item);
    _history.insert(0, item);
    if (_history.length > 20) _history = _history.sublist(0, 20);
    await _save();
  }

  Future<void> addArtist(String name, String id,
      {String? query, String? imageUrl}) async {
    await add(
        SearchHistoryItem.artist(name, id, query: query, imageUrl: imageUrl));
  }

  Future<void> addAlbum(String title, String id, String artistName,
      {String? query, String? imageUrl}) async {
    await add(SearchHistoryItem.album(title, id, artistName,
        query: query, imageUrl: imageUrl));
  }

  Future<void> addTrack(String title, String id, String artistName,
      {String? query, String? imageUrl}) async {
    await add(SearchHistoryItem.track(title, id, artistName,
        query: query, imageUrl: imageUrl));
  }

  Future<void> remove(SearchHistoryItem item) async {
    await ensureLoaded();
    _history.removeWhere((h) => h == item);
    await _save();
  }

  Future<void> clear() async {
    await ensureLoaded();
    _history.clear();
    await _save();
  }
}
