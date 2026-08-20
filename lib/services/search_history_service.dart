import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SearchHistoryService {
  static final SearchHistoryService _instance =
      SearchHistoryService._internal();
  factory SearchHistoryService() => _instance;
  SearchHistoryService._internal();

  List<String> _history = [];
  bool _loaded = false;

  List<String> get history => List.unmodifiable(_history);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _load();
    _loaded = true;
  }

  Future<String> _getFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'search_history.json');
  }

  Future<void> _load() async {
    final path = await _getFilePath();
    final file = File(path);
    if (!await file.exists()) {
      _history = [];
      return;
    }
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      _history = data.map((e) => e.toString()).toList();
    } catch (e) {
      _history = [];
    }
  }

  Future<void> _save() async {
    final path = await _getFilePath();
    final file = File(path);
    await file.writeAsString(jsonEncode(_history));
  }

  Future<void> add(String query) async {
    await ensureLoaded();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _history.remove(trimmed);
    _history.insert(0, trimmed);
    if (_history.length > 10) _history = _history.sublist(0, 10);
    await _save();
  }

  Future<void> remove(String query) async {
    await ensureLoaded();
    _history.remove(query);
    await _save();
  }

  Future<void> clear() async {
    await ensureLoaded();
    _history.clear();
    await _save();
  }
}
