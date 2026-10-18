import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/prefs.dart';
import '../models/drama.dart';

const Map<String, String> kSourceLabels = {
  'huangguo': '黄果',
  'huangdou': '黄豆',
  'hongguo': '红果',
  'juguo': '剧果',
  'yeguo': '野果',
  'diguo': '帝果',
  'yaguo': '芽果',
  'maoguo': '猫果',
  'fanguo': '饭果',
  'guanguo': '观果',
  'heguo': '河果',
  'xingguo': '星果',
  'huaguo': '花果',
  'niuguo': '牛果',
  'wangguo': '网果',
  'faguo': '发果',
  'piguo': '皮果',
  'wuguo': '伍果',
};

String sourceLabel(String key) => kSourceLabels[key] ?? (key.isEmpty ? '剧库' : key);

class AppState extends ChangeNotifier {
  AppState(this.prefs);

  final AppPrefs prefs;

  ApiClient? api;
  String serverUrl = '';
  String? lastError;

  List<Drama> library = const [];
  List<Drama> recommendations = const [];
  List<LibraryEntry> following = const [];
  List<LibraryEntry> history = const [];

  bool loadingLibrary = false;
  bool loadingFollowing = false;
  bool loadingHistory = false;

  String themeMode = 'dark';

  /// 当前站源，空字符串表示全部站源
  String selectedSource = '';

  final Map<String, Drama> _byId = {};

  bool get connected => api != null && serverUrl.isNotEmpty;

  /// 剧库里实际出现过的站源，按内置顺序排列
  List<String> get availableSources {
    final keys = <String>{};
    for (final drama in library) {
      if (drama.source.isNotEmpty) keys.add(drama.source);
    }
    final ordered = kSourceLabels.keys.where(keys.contains).toList();
    ordered.addAll(keys.where((key) => !kSourceLabels.containsKey(key)).toList()..sort());
    return ordered;
  }

  /// 按当前站源过滤后的剧库
  List<Drama> get visibleLibrary {
    if (selectedSource.isEmpty) return library;
    return library.where((drama) => drama.source == selectedSource).toList();
  }

  /// 当前站源的展示名
  String get selectedSourceLabel => selectedSource.isEmpty ? '全部站源' : sourceLabel(selectedSource);

  Future<void> setSource(String key) async {
    if (selectedSource == key) return;
    selectedSource = key;
    prefs.source = key;
    notifyListeners();
  }

  ThemeMode get resolvedTheme => switch (themeMode) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  /// 剧集可能只存在于追剧/记录里，本地先按 id 建索引方便展示。
  Drama? dramaById(String id) => _byId[id];

  Future<void> bootstrap() async {
    themeMode = prefs.themeMode;
    selectedSource = prefs.source;
    final cached = prefs.readLibraryCache();
    if (cached != null) {
      final raw = cached['data'];
      if (raw is List) {
        library = raw
            .whereType<Map>()
            .map((e) => Drama.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.id.isNotEmpty)
            .toList();
        _reindex();
      }
    }
    final saved = prefs.serverUrl;
    if (saved.isNotEmpty) {
      serverUrl = saved;
      api = ApiClient(baseUrl: saved);
      notifyListeners();
      // 后台静默刷新，失败也不清空缓存
      refreshAll(silent: true);
    }
  }

  Future<void> connect(String rawUrl) async {
    final normalized = ApiClient.normalizeBase(rawUrl);
    if (normalized.isEmpty) throw ApiException('请填写服务器地址');
    final client = ApiClient(baseUrl: normalized);
    await client.probe();
    api?.close();
    api = client;
    serverUrl = normalized;
    lastError = null;
    await prefs.pushRecentServer(normalized);
    prefs.serverUrl = normalized;
    notifyListeners();
    await refreshAll();
  }

  void disconnect() {
    api?.close();
    api = null;
    serverUrl = '';
    library = const [];
    recommendations = const [];
    following = const [];
    history = const [];
    _byId.clear();
    prefs.clearAll();
    notifyListeners();
  }

  Future<void> refreshAll({bool silent = false}) async {
    await Future.wait([
      loadLibrary(silent: silent),
      loadRecommendations(silent: silent),
      loadFollowing(silent: silent),
      loadHistory(silent: silent),
    ]);
  }

  Future<void> loadLibrary({bool silent = false}) async {
    final client = api;
    if (client == null) return;
    loadingLibrary = true;
    if (!silent) notifyListeners();
    try {
      final page = await client.library();
      library = page.items;
      _reindex();
      lastError = null;
      await prefs.writeLibraryCache({
        'data': library
            .map((e) => {
                  'id': e.id,
                  'title': e.title,
                  'cover': e.cover,
                  'desc': e.desc,
                  'source': e.source,
                  'episodeCount': e.episodeCount,
                  'category': e.category,
                  'tags': e.tags,
                  'score': e.score,
                  'heat': e.heat,
                  'releaseStatus': e.releaseStatus,
                  'vip': e.vip,
                })
            .toList(),
      });
    } on ApiException catch (error) {
      lastError = error.message;
    } finally {
      loadingLibrary = false;
      notifyListeners();
    }
  }

  Future<void> loadRecommendations({bool silent = false}) async {
    final client = api;
    if (client == null) return;
    try {
      recommendations = await client.recommendations();
      _reindex();
    } on ApiException catch (error) {
      if (!silent) lastError = error.message;
    }
    notifyListeners();
  }

  Future<void> loadFollowing({bool silent = false}) async {
    final client = api;
    if (client == null) return;
    loadingFollowing = true;
    if (!silent) notifyListeners();
    try {
      following = await client.following();
      _reindex();
    } on ApiException catch (error) {
      if (!silent) lastError = error.message;
    } finally {
      loadingFollowing = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory({bool silent = false}) async {
    final client = api;
    if (client == null) return;
    loadingHistory = true;
    if (!silent) notifyListeners();
    try {
      history = await client.history();
      _reindex();
    } on ApiException catch (error) {
      if (!silent) lastError = error.message;
    } finally {
      loadingHistory = false;
      notifyListeners();
    }
  }

  bool isFollowing(String dramaId) => following.any((entry) => entry.dramaId == dramaId);

  Future<void> toggleFollowing(Drama drama) async {
    final client = api;
    if (client == null) return;
    final saved = !isFollowing(drama.id);
    final placeholder = LibraryEntry(
      dramaId: drama.id,
      drama: drama,
      episode: 0,
      position: 0,
      duration: 0,
      updatedAt: DateTime.now(),
      completed: false,
    );
    following = saved
        ? [placeholder, ...following.where((e) => e.dramaId != drama.id)]
        : following.where((e) => e.dramaId != drama.id).toList();
    notifyListeners();
    try {
      await client.setFollowing(drama.id, saved);
    } catch (_) {
      // 回滚
      following = saved
          ? following.where((e) => e.dramaId != drama.id).toList()
          : [placeholder, ...following];
      notifyListeners();
      rethrow;
    }
  }

  Future<void> clearHistory({String? dramaId}) async {
    final client = api;
    if (client == null) return;
    await client.removeHistory(dramaId: dramaId);
    history = dramaId == null ? const [] : history.where((e) => e.dramaId != dramaId).toList();
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    prefs.themeMode = mode;
    notifyListeners();
  }

  void _reindex() {
    for (final drama in [...library, ...recommendations]) {
      _byId[drama.id] = drama;
    }
    for (final entry in [...following, ...history]) {
      final drama = entry.drama;
      if (drama != null && drama.id.isNotEmpty) _byId[drama.id] = drama;
    }
  }

  @override
  void dispose() {
    api?.close();
    super.dispose();
  }
}
