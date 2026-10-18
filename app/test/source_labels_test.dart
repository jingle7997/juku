import 'package:flutter_test/flutter_test.dart';
import 'package:juku/state/app_state.dart';

/// 服务端 `internal/app/account_source_catalog.go` 的 `accountSourceChoices`，
/// 顺序和 id 都照抄。这里写死是故意的：App 的站源名表必须与它对得上，
/// 对不上时换源面板和榜单列表会直接露出 `huangju` / `dsd` 这种英文 key。
const List<List<String>> _serverSources = [
  ['huangguo', '黄果'],
  ['huangdou', '黄豆'],
  ['hongguo', '红果'],
  ['huangju', '剧果'],
  ['yeguo', '野果'],
  ['dsd', '帝果'],
  ['yaguo', '芽果'],
  ['maoguo', '猫果'],
  ['fanguo', '饭果'],
  ['guanguo', '观果'],
  ['heguo', '河果'],
  ['xingguo', '星果'],
  ['huaguo', '花果'],
  ['niuguo', '牛果'],
  ['piguo', '皮果'],
  ['wuguo', '伍果'],
];

void main() {
  group('站源中文名', () {
    test('服务端每个站源 id 都有中文名', () {
      for (final pair in _serverSources) {
        final id = pair[0];
        final name = pair[1];
        // 回归点：剧果的服务端 id 是 huangju（不是 juguo），帝果是 dsd（不是 diguo）
        expect(sourceLabel(id), name, reason: '站源 $id 的中文名对不上');
      }
    });

    test('剧果 / 帝果的 id 不是 juguo / diguo', () {
      expect(sourceLabel('huangju'), '剧果');
      expect(sourceLabel('dsd'), '帝果');
    });

    test('未知站源回退成原始 id，空值回退成「剧库」', () {
      expect(sourceLabel('unknown-source'), 'unknown-source');
      expect(sourceLabel(''), '剧库');
    });
  });
}
