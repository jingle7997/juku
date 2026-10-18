import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/drama.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = ''});
  final String message;
  final int status;
  final String code;

  bool get needsLogin => code == 'login_required' || status == 401;

  @override
  String toString() => message;
}

/// 短剧库服务端 HTTP 客户端。
///
/// 服务端播放接口会校验 Sec-Fetch-Site / Origin，原生客户端不带这些头即可通过；
/// 但要求 Content-Type 为 application/json，且请求体字段必须完全匹配。
class ApiClient {
  ApiClient({required String baseUrl, http.Client? client})
      : _baseUrl = normalizeBase(baseUrl),
        _client = client ?? http.Client();

  final http.Client _client;
  String _baseUrl;
  String _cookie = '';

  String get baseUrl => _baseUrl;

  set baseUrl(String value) => _baseUrl = normalizeBase(value);

  static String normalizeBase(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  String resolve(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (!path.startsWith('/')) path = '/$path';
    return '$_baseUrl$path';
  }

  void close() => _client.close();

  Future<dynamic> _send(
    String path, {
    String method = 'GET',
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse(resolve(path)).replace(queryParameters: query?.isEmpty == true ? null : query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('连接超时，请检查地址与网络');
    } catch (error) {
      throw ApiException('无法连接服务器：$error');
    }
    _rememberCookie(response);
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    dynamic payload;
    if (text.isNotEmpty) {
      try {
        payload = jsonDecode(text);
      } catch (_) {
        payload = null;
      }
    }
    if (response.statusCode >= 400) {
      final map = payload is Map ? payload.cast<String, dynamic>() : const <String, dynamic>{};
      throw ApiException(
        (map['error'] ?? map['message'] ?? '请求失败（${response.statusCode}）').toString(),
        status: response.statusCode,
        code: (map['code'] ?? '').toString(),
      );
    }
    if (payload == null) throw ApiException('服务器返回了无法解析的内容');
    return payload;
  }

  void _rememberCookie(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final parts = <String>[];
    for (final chunk in raw.split(RegExp(r',(?=[^;]+=)'))) {
      final pair = chunk.split(';').first.trim();
      if (pair.contains('=')) parts.add(pair);
    }
    if (parts.isNotEmpty) _cookie = parts.join('; ');
  }

  // ---------------------------------------------------------------- 探测

  /// 连接测试：config 需要管理员，403/401 也说明服务在线。
  Future<bool> probe() async {
    try {
      await _send('/api/ui/config', timeout: const Duration(seconds: 6));
      return true;
    } on ApiException catch (error) {
      if (error.status == 401 || error.status == 403 || error.code == 'admin_required') return true;
      rethrow;
    }
  }

  // ---------------------------------------------------------------- 剧库

  Future<DramaPage> library({int revision = 0}) async {
    final json = await _send('/api/ui/dramas', query: {'revision': '$revision'});
    final map = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    return DramaPage(
      items: _dramas(map['data']),
      loading: map['loading'] == true,
      revision: (map['revision'] as num?)?.toInt() ?? revision,
    );
  }

  Future<List<Drama>> recommendations() async {
    final json = await _send('/api/ui/recommendations');
    return _dramasFrom(json);
  }

  Future<List<RankingBoard>> rankingBoards() async {
    final json = await _send('/api/ui/rankings');
    final map = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final raw = map['boards'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => RankingBoard.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  /// 拉榜单的一页。服务端带 hasMore / updatedText / warning，别再只取 items。
  Future<RankingPage> rankingItems(String boardId, int page) async {
    final json = await _send('/api/ui/rankings', query: {'board': boardId, 'page': '$page'});
    final map = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    return RankingPage.fromJson(map);
  }

  Future<List<String>> categories(String source) async {
    final json = await _send('/api/ui/categories', query: {'source': source});
    final map = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final raw = map['items'] ?? map['data'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e is Map ? (e['name'] ?? e['title'] ?? e['category'] ?? '').toString() : e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  Future<List<Drama>> search(String keyword) async {
    final json = await _send('/api/ui/search', query: {'q': keyword, 'query': keyword});
    return _dramasFrom(json);
  }

  // ---------------------------------------------------------------- 追剧 / 记录

  Future<List<LibraryEntry>> following() async {
    final json = await _send('/api/ui/following');
    return _entries(json);
  }

  Future<bool> setFollowing(String dramaId, bool saved) async {
    final json = await _send('/api/ui/following', method: 'POST', body: {'dramaId': dramaId, 'saved': saved});
    if (json is Map) {
      final entry = json['entry'];
      if (entry is Map) return entry['saved'] == true || entry['completed'] == true;
    }
    return saved;
  }

  Future<List<LibraryEntry>> history() async {
    final json = await _send('/api/ui/playback/history');
    return _entries(json);
  }

  Future<void> removeHistory({String? dramaId}) async {
    await _send(
      '/api/ui/playback/history/remove',
      method: 'POST',
      body: dramaId == null ? {'all': true} : {'dramaId': dramaId},
    );
  }

  // ---------------------------------------------------------------- 播放

  Future<PlaybackSession> openPlayback(String dramaId, {bool resume = true}) async {
    final json = await _send('/api/ui/playback/open', method: 'POST', body: {
      'dramaId': dramaId,
      'resume': resume,
    });
    return PlaybackSession.fromJson((json as Map).cast<String, dynamic>());
  }

  Future<PlaybackSource> openStream({
    required String session,
    required int episode,
    double start = 0,
    int quality = 0,
    int version = 0,
  }) async {
    final json = await _send('/api/ui/playback/hls/open', method: 'POST', body: {
      'session': session,
      'episode': episode,
      'start': start,
      'quality': quality,
      'version': version,
    });
    return PlaybackSource.fromJson((json as Map).cast<String, dynamic>());
  }

  /// 上报观看进度。
  ///
  /// 服务端 handlePlaybackProgress 的结构是 `{session, progress:{...}}`，
  /// 且解码时开了 DisallowUnknownFields —— 字段必须完全一致，平铺传会被判 400。
  /// sequence 必须**每次上报都递增**，服务端用它丢弃乱序到达的旧进度。
  Future<void> reportProgress({
    required String session,
    required int run,
    required int sequence,
    required int episode,
    required double position,
    required double duration,
    bool completed = false,
  }) async {
    await _send('/api/ui/playback/progress', method: 'POST', body: {
      'session': session,
      'progress': {
        'run': run,
        'sequence': sequence,
        'episode': episode,
        'position': position,
        'duration': duration,
        'completed': completed,
      },
    }, timeout: const Duration(seconds: 8));
  }

  /// 关闭播放会话，可顺带落一次进度。
  ///
  /// progress 里的 run / sequence 必须是真实的，服务端 recordPlaybackProgress
  /// 对 run==0 或 sequence==0 直接判「观看进度无效」，只会白丢一次进度。
  Future<void> closePlayback(
    String session, {
    int run = 0,
    int sequence = 0,
    int? episode,
    double? position,
    double? duration,
    bool completed = false,
  }) async {
    await _send('/api/ui/playback/control', method: 'POST', body: {
      'session': session,
      'action': 'close',
      if (episode != null && position != null && run > 0 && sequence > 0)
        'progress': {
          'run': run,
          'sequence': sequence,
          'episode': episode,
          'position': position,
          'duration': duration ?? 0,
          'completed': completed,
        },
    }, timeout: const Duration(seconds: 8));
  }

  // ---------------------------------------------------------------- 解析辅助

  List<Drama> _dramas(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Drama.fromJson(e.cast<String, dynamic>())).where((e) => e.id.isNotEmpty).toList();
  }

  List<Drama> _dramasFrom(dynamic json) {
    if (json is List) return _dramas(json);
    if (json is Map) {
      for (final key in const ['data', 'items', 'list', 'dramas', 'results']) {
        final value = json[key];
        if (value is List) return _dramas(value);
      }
    }
    return const [];
  }

  List<LibraryEntry> _entries(dynamic json) {
    final raw = json is Map ? json['data'] : json;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LibraryEntry.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.dramaId.isNotEmpty)
        .toList();
  }
}
