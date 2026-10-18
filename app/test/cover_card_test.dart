import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juku/models/drama.dart';
import 'package:juku/widgets/cover_card.dart';

void main() {
  // cover 留空，这样 CoverCard 不会去读 AppState（resolveCover 在空串时直接返回）
  final drama = Drama.fromJson({'id': 'hongguo:1', 'title': '样本剧'});

  Widget card(String tag) => SizedBox(
        width: 100,
        height: 140,
        child: CoverCard(drama: drama, showTitle: false, heroTag: tag),
      );

  testWidgets('同一部剧在同一页面出现两次，heroTag 不同则不会冲突', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // 首页的「为你推荐」和「全部短剧」会同时出现同一部剧
              card('featured-${drama.id}'),
              card('library-${drama.id}'),
            ],
          ),
        ),
      ),
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Hero(tag: 'featured-${drama.id}', child: const Text('详情')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 回归点：tag 如果都写成 cover-{id}，这里会抛
    // 「There are multiple heroes that share the same tag within a subtree」
    expect(tester.takeException(), isNull);
    expect(find.text('详情'), findsOneWidget);
  });

  testWidgets('heroTag 为 null 时不包 Hero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 140,
            child: CoverCard(drama: drama, showTitle: false),
          ),
        ),
      ),
    );

    expect(find.byType(Hero), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
