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
        _normalizeSource();
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
    // 换了服务器，旧的剧集索引必须清掉，否则 dramaById 会返回上一台服务器的数据
    _byId.clear();
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
      // 服务端第一次抓源时 loading=true 且 data 为空，这时候不能拿空列表
      // 覆盖已有数据，否则首页会闪空、还会把本地缓存写成空
      final stillFetching = page.loading && page.items.isEmpty && library.isNotEmpty;
      if (!stillFetching) {
        library = page.items;
        _reindex();
        _normalizeSource();
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
      }
      lastError = null;
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
    // 保存整个列表快照：失败时原样恢复。
    // 之前用 placeholder 回滚，会把该剧原有的观看进度（episode/position）冲成 0。
    final previous = following;
    final placeholder = LibraryEntry(
      dramaId: drama.id,
      drama: drama,
      episode: 0,
      position: 0,
      duration: 0,
      updatedAt: DateTime.now(),
      completed: false,
      title: drama.title,
      total: drama.episodeCount,
    );
    following = saved
        ? [placeholder, ...following.where((e) => e.dramaId != drama.id)]
        : following.where((e) => e.dramaId != drama.id).toList();
    notifyListeners();
    try {
      await client.setFollowing(drama.id, saved);
    } catch (_) {
      following = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// 取消追剧。直接按 id 操作，不依赖本地剧库里有这部剧 ——
  /// 原来从 dramaById 取，取不到就静默什么都不做。
  Future<void> unfollow(String dramaId) async {
    final client = api;
    if (client == null) return;
    final previous = following;
    following = following.where((e) => e.dramaId != dramaId).toList();
    notifyListeners();
    try {
      await client.setFollowing(dramaId, false);
    } catch (_) {
      following = previous;
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

  /// 选中的站源在剧库里已经不存在时（换了服务器、或剧库刷新后这个源没了），
  /// 自动退回「全部站源」。否则首页会一直空白，而换源面板里看不出原因。
  void _normalizeSource() {
    if (selectedSource.isEmpty || library.isEmpty) return;
    if (availableSources.contains(selectedSource)) return;
    selectedSource = '';
    prefs.source = '';
  }

  @override
  void dispose() {
    api?.close();
    super.dispose();
  }
}
