import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地偏好：服务器地址、主题、最近连接记录。
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppPrefs> load() async => AppPrefs(await SharedPreferences.getInstance());

  String get serverUrl => _prefs.getString('serverUrl') ?? '';

  set serverUrl(String value) => _prefs.setString('serverUrl', value);

  String get themeMode => _prefs.getString('themeMode') ?? 'dark';

  set themeMode(String value) => _prefs.setString('themeMode', value);

  /// 当前站源，空字符串表示「全部站源」
  String get source => _prefs.getString('source') ?? '';

  set source(String value) => _prefs.setString('source', value);

  List<String> get recentServers => _prefs.getStringList('recentServers') ?? const [];

  Future<void> pushRecentServer(String value) async {
    final list = List<String>.from(recentServers)..remove(value);
    list.insert(0, value);
    await _prefs.setStringList('recentServers', list.take(6).toList());
  }

  Future<void> removeRecentServer(String value) async {
    final list = List<String>.from(recentServers)..remove(value);
    await _prefs.setStringList('recentServers', list);
  }

  /// 缓存首页数据，冷启动先显示上次的内容，避免白屏。
  Map<String, dynamic>? readLibraryCache() {
    final raw = _prefs.getString('libraryCache');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLibraryCache(Map<String, dynamic> value) async {
    await _prefs.setString('libraryCache', jsonEncode(value));
  }

  Future<void> clearAll() async {
    await _prefs.remove('serverUrl');
    await _prefs.remove('libraryCache');
  }
}
