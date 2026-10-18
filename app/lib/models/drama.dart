// 服务端返回的字段命名并不统一（历史原因有驼峰与下划线两套），
// 这里统一做一次宽松解析，只保留 App 真正用到的信息。

class Drama {
  Drama({
    required this.id,
    required this.title,
    required this.cover,
    required this.desc,
    required this.source,
    required this.episodeCount,
    required this.category,
    required this.tags,
    required this.score,
    required this.heat,
    required this.releaseStatus,
    required this.vip,
  });

  final String id;
  final String title;
  final String cover;
  final String desc;
  final String source;
  final int episodeCount;
  final String category;
  final List<String> tags;
  final String score;
  final String heat;
  final String releaseStatus;
  final bool vip;

  factory Drama.fromJson(Map<String, dynamic> json) {
    return Drama(
      id: _str(json['id'] ?? json['dramaId'] ?? json['sourceId']),
      title: _str(json['title'] ?? json['name']),
      cover: _str(_first(json, const [
        'cover',
        'coverUrl',
        'cover_url',
        'image',
        'imageUrl',
        'image_url',
        'img',
        'pic',
        'picture',
        'poster',
        'thumb',
        'thumbnail',
      ])),
      desc: _str(json['desc'] ?? json['intro'] ?? json['remark']),
      source: _str(json['source']),
      episodeCount: _int(_first(json, const [
        'totalEpisode',
        'total_episode',
        'chapterCount',
        'chapter_count',
        'episodeCount',
        'episode_count',
        'total',
      ])),
      category: _str(json['categoryName'] ?? json['category_name'] ?? json['typeName'] ?? json['category']),
      tags: (json['tags'] is List) ? (json['tags'] as List).map(_str).where((e) => e.isNotEmpty).toList() : const [],
      score: _str(json['score']),
      heat: _str(json['heat'] ?? json['views']),
      releaseStatus: _str(json['releaseStatus']),
      vip: json['vip'] == true,
    );
  }

  String get subtitle {
    final parts = <String>[];
    if (category.isNotEmpty) parts.add(category);
    if (episodeCount > 0) parts.add('$episodeCount 集');
    if (releaseStatus == 'finished') {
      parts.add('已完结');
    } else if (releaseStatus == 'ongoing') {
      parts.add('连载中');
    }
    return parts.join(' · ');
  }

  static String _str(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num) return value.toString();
    return '';
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return 0;
  }

  static Object? _first(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return null;
  }
}

/// 首页/发现页的分页容器
class DramaPage {
  const DramaPage({required this.items, required this.loading, required this.revision});
  final List<Drama> items;
  final bool loading;
  final int revision;
}

class RankingBoard {
  const RankingBoard({required this.id, required this.name, required this.source});
  final String id;
  final String name;
  final String source;

  factory RankingBoard.fromJson(Map<String, dynamic> json) {
    return RankingBoard(
      id: (json['id'] ?? json['boardId'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? '榜单').toString(),
      source: (json['source'] ?? '').toString(),
    );
  }
}

class RankingItem {
  const RankingItem({required this.rank, required this.drama});
  final int rank;
  final Drama drama;

  factory RankingItem.fromJson(Map<String, dynamic> json) {
    return RankingItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      drama: Drama.fromJson((json['drama'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }
}

/// 追剧 / 观看记录条目：服务端可能只给 id，也可能带上剧集信息
class LibraryEntry {
  const LibraryEntry({
    required this.dramaId,
    required this.drama,
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.completed,
  });

  final String dramaId;
  final Drama? drama;
  final int episode;
  final double position;
  final double duration;
  final DateTime? updatedAt;
  final bool completed;

  double get progress {
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['drama'] ?? json['detail'] ?? json['info'];
    final stamp = json['updatedAt'] ?? json['updateAt'] ?? json['time'] ?? json['watchedAt'];
    return LibraryEntry(
      dramaId: (json['dramaId'] ?? json['id'] ?? '').toString(),
      drama: raw is Map ? Drama.fromJson(raw.cast<String, dynamic>()) : null,
      episode: (json['episode'] as num?)?.toInt() ?? (json['index'] as num?)?.toInt() ?? 0,
      position: (json['position'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      updatedAt: stamp is num
          ? DateTime.fromMillisecondsSinceEpoch(
              stamp > 100000000000 ? stamp.toInt() : stamp.toInt() * 1000,
              isUtc: false,
            )
          : DateTime.tryParse(stamp?.toString() ?? ''),
      completed: json['completed'] == true,
    );
  }
}

/// 播放会话：open 之后拿到分集清单
class PlaybackEpisode {
  const PlaybackEpisode({
    required this.index,
    required this.episode,
    required this.title,
    required this.danmaku,
    required this.merged,
    required this.vip,
  });

  final int index;
  final String episode;
  final String title;
  final bool danmaku;
  final bool merged;
  final bool vip;

  String get label => title.isNotEmpty ? title : (episode.isNotEmpty ? episode : '第 $index 集');

  factory PlaybackEpisode.fromJson(Map<String, dynamic> json) {
    return PlaybackEpisode(
      index: (json['index'] as num?)?.toInt() ?? 0,
      episode: (json['episode'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      danmaku: json['danmaku'] == true,
      merged: json['merged'] == true,
      vip: json['vip'] == true,
    );
  }
}

class PlaybackSession {
  const PlaybackSession({
    required this.session,
    required this.dramaId,
    required this.title,
    required this.episodes,
    required this.initialIndex,
    required this.initialPosition,
    required this.resumeMessage,
    required this.mimeType,
    required this.mode,
  });

  final String session;
  final String dramaId;
  final String title;
  final List<PlaybackEpisode> episodes;
  final int initialIndex;
  final double initialPosition;
  final String resumeMessage;
  final String mimeType;
  final String mode;

  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'];
    return PlaybackSession(
      session: (json['session'] ?? '').toString(),
      dramaId: (json['dramaId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      episodes: rawEpisodes is List
          ? rawEpisodes
              .whereType<Map>()
              .map((e) => PlaybackEpisode.fromJson(e.cast<String, dynamic>()))
              .where((e) => e.index > 0)
              .toList()
          : const [],
      initialIndex: (json['initialIndex'] as num?)?.toInt() ?? 1,
      initialPosition: (json['initialPosition'] as num?)?.toDouble() ?? 0,
      resumeMessage: (json['resumeMessage'] ?? '').toString(),
      mimeType: (json['mimeType'] ?? '').toString(),
      mode: (json['mode'] ?? '').toString(),
    );
  }
}

/// 取流结果：url 交给 AVPlayer 直接播放
class PlaybackSource {
  const PlaybackSource({
    required this.url,
    required this.run,
    required this.duration,
    required this.qualities,
    required this.quality,
  });

  final String url;
  final int run;
  final double duration;
  final List<PlaybackQuality> qualities;
  final int quality;

  factory PlaybackSource.fromJson(Map<String, dynamic> json) {
    final rawQualities = json['qualities'];
    return PlaybackSource(
      url: (json['url'] ?? '').toString(),
      run: (json['run'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      qualities: rawQualities is List
          ? rawQualities
              .whereType<Map>()
              .map((e) => PlaybackQuality.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
      quality: (json['quality'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlaybackQuality {
  const PlaybackQuality({required this.value, required this.label});
  final int value;
  final String label;

  factory PlaybackQuality.fromJson(Map<String, dynamic> json) {
    return PlaybackQuality(
      value: (json['value'] ?? json['quality'] as num?)?.toInt() ?? 0,
      label: (json['label'] ?? json['name'] ?? '自动').toString(),
    );
  }
}
