import 'package:flutter_test/flutter_test.dart';
import 'package:juku/models/drama.dart';

void main() {
  group('LibraryEntry 解析', () {
    test('观看记录：episode 是字符串，集数在 index', () {
      final entry = LibraryEntry.fromJson({
        'dramaId': 'hongguo:123',
        'source': 'hongguo',
        'title': '闪婚后，大叔每天想官宣',
        'chapterId': 'c12',
        'episode': '第12集',
        'index': 12,
        'total': 86,
        'position': 640.0,
        'duration': 1500.0,
        'completed': false,
        'mode': 'online',
        'watchedAt': '2026-10-18T12:30:00Z',
      });

      // 回归点：服务端 episode 是 String，直接 as num? 会抛 TypeError，
      // 导致整个观看记录接口解析失败
      expect(entry.episode, 12);
      expect(entry.episodeLabel, '第12集');
      expect(entry.dramaId, 'hongguo:123');
      expect(entry.title, '闪婚后，大叔每天想官宣');
      expect(entry.total, 86);
      expect(entry.progress, closeTo(640 / 1500, 1e-6));
      expect(entry.updatedAt, isNotNull);
    });

    test('追剧条目：没有 index / episode / position 也不报错', () {
      final entry = LibraryEntry.fromJson({
        'dramaId': 'hongguo:9',
        'source': 'hongguo',
        'title': '战神归来',
        'saved': true,
        'completed': false,
        'knownEpisodes': 90,
        'addedAt': '2026-10-10T08:00:00Z',
        'updatedAt': '2026-10-18T09:20:00Z',
      });

      expect(entry.episode, 0);
      expect(entry.total, 90);
      expect(entry.title, '战神归来');
      expect(entry.progress, 0);
    });

    test('episode 是纯数字字符串时也能取出集数', () {
      expect(LibraryEntry.fromJson({'dramaId': 'x:1', 'episode': '7'}).episode, 7);
      expect(LibraryEntry.fromJson({'dramaId': 'x:1', 'episode': 7}).episode, 7);
    });

    test('updatedAt 支持秒级与毫秒级时间戳', () {
      final seconds = LibraryEntry.fromJson({'dramaId': 'x:1', 'updatedAt': 1760000000});
      final millis = LibraryEntry.fromJson({'dramaId': 'x:1', 'updatedAt': 1760000000000});
      expect(seconds.updatedAt!.year, millis.updatedAt!.year);
    });

    test('position / duration 是字符串时不抛异常', () {
      final entry = LibraryEntry.fromJson({
        'dramaId': 'x:1',
        'position': '640.5',
        'duration': '1500',
      });
      expect(entry.position, 640.5);
      expect(entry.duration, 1500);
      expect(entry.progress, closeTo(640.5 / 1500, 1e-6));
      expect(LibraryEntry.fromJson({'dramaId': 'x:1'}).progress, 0);
    });
  });

  group('PlaybackQuality 解析', () {
    test('value 是数字或数字字符串都能解析', () {
      expect(PlaybackQuality.fromJson({'value': 1080, 'label': '1080P'}).value, 1080);
      expect(PlaybackQuality.fromJson({'value': '1080', 'label': '1080P'}).value, 1080);
      expect(PlaybackQuality.fromJson({'quality': 720}).value, 720);
      expect(PlaybackQuality.fromJson({}).value, 0);
    });
  });

  group('Drama 解析', () {
    test('驼峰与下划线两套命名都能读', () {
      final drama = Drama.fromJson({
        'id': 'hongguo:1',
        'name': '样本剧',
        'cover_url': 'http://host/a.jpg',
        'total_episode': '86集',
        'category_name': '都市',
        'tags': ['都市', '', '甜宠'],
        'releaseStatus': 'finished',
      });

      expect(drama.id, 'hongguo:1');
      expect(drama.title, '样本剧');
      expect(drama.cover, 'http://host/a.jpg');
      expect(drama.episodeCount, 86);
      expect(drama.category, '都市');
      expect(drama.tags, ['都市', '甜宠']);
      expect(drama.subtitle, '都市 · 86 集 · 已完结');
    });

    test('空封面字段会继续往后找', () {
      final drama = Drama.fromJson({'id': 'x:1', 'cover': '', 'poster': 'http://host/p.jpg'});
      expect(drama.cover, 'http://host/p.jpg');
    });
  });

  group('PlaybackSession 解析', () {
    test('index 为 0 的分集会被丢弃', () {
      final session = PlaybackSession.fromJson({
        'session': 's1',
        'episodes': [
          {'index': 0, 'episode': '第0集'},
          {'index': 1, 'episode': '第1集'},
          {'index': 2, 'episode': '第2集'},
        ],
        'initialIndex': 1,
      });

      expect(session.episodes.length, 2);
      expect(session.episodes.first.index, 1);
    });
  });

  group('榜单解析', () {
    test('board 带 description', () {
      final board = RankingBoard.fromJson({
        'id': 'hongguo-hot',
        'name': '总热播榜',
        'source': 'hongguo',
        'description': '红果观看、互动等综合热度；每日更新。',
      });
      expect(board.id, 'hongguo-hot');
      expect(board.description, '红果观看、互动等综合热度；每日更新。');
      expect(RankingBoard.fromJson({'id': 'x', 'name': 'y'}).description, '');
    });

    test('page 的 hasMore / updatedText / totalPages 都能读', () {
      final page = RankingPage.fromJson({
        'boardId': 'hongguo-hot',
        'page': 2,
        'items': [
          {'rank': 7, 'drama': {'id': 'hongguo:7', 'name': '第七部'}},
          {'rank': 0, 'drama': {'id': '', 'name': '没有 id 的会被丢掉'}},
        ],
        'hasMore': true,
        'totalPages': 5,
        'updatedText': '5 分钟前更新',
        'warning': '部分剧集抓取失败',
      });
      expect(page.page, 2);
      expect(page.items.length, 1);
      expect(page.items.first.rank, 7);
      expect(page.items.first.drama.title, '第七部');
      expect(page.hasMore, isTrue);
      expect(page.totalPages, 5);
      expect(page.updatedText, '5 分钟前更新');
      expect(page.warning, '部分剧集抓取失败');
    });

    test('空响应退化成空页而不是抛异常', () {
      final page = RankingPage.fromJson({});
      expect(page.items, isEmpty);
      expect(page.page, 1);
      expect(page.hasMore, isFalse);
      expect(page.updatedText, '');
    });
  });
}
