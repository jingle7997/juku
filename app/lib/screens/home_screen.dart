import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';
import '../widgets/brand_mark.dart';
import '../widgets/chrome.dart';
import '../widgets/cover_card.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.watch<AppState>();
    final source = state.selectedSource;
    List<Drama> filter(List<Drama> input) =>
        source.isEmpty ? input : input.where((drama) => drama.source == source).toList();
    final featured = filter(state.recommendations.isNotEmpty ? state.recommendations : state.library);
    final list = state.visibleLibrary;

    return RefreshIndicator(
      color: palette.accent,
      backgroundColor: palette.surface,
      onRefresh: () => state.refreshAll(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: palette.background.withValues(alpha: 0.92),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 16,
            title: Row(
              children: [
                const BrandMark(26, shadow: false),
                const SizedBox(width: 9),
                Text(
                  '果果短剧',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: palette.text, letterSpacing: -0.4),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () => _openSearch(context),
                icon: Icon(Icons.search_rounded, size: 22, color: palette.text),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if (state.loadingLibrary && list.isEmpty)
            const SliverToBoxAdapter(child: LoadingGrid())
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.video_library_outlined,
                title: source.isEmpty ? '剧库还是空的' : '${state.selectedSourceLabel}还没有剧',
                subtitle: state.lastError ?? (source.isEmpty ? '在电脑端更新一次剧库后，这里就会出现短剧。' : '可以在「我的 → 站源」里切换回全部站源。'),
                action: GhostButton(
                  label: '重新加载',
                  icon: Icons.refresh_rounded,
                  onPressed: () => state.loadLibrary(),
                ),
              ),
            )
          else ...[
            if (featured.isNotEmpty) _featuredRail(context, featured),
            if (list.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: '全部短剧',
                  subtitle: source.isEmpty ? '共 ${list.length} 部' : '${state.selectedSourceLabel} · 共 ${list.length} 部',
                  trailing: TextButton(
                    onPressed: () => state.loadLibrary(),
                    child: Text('刷新', style: TextStyle(fontSize: 12.5, color: palette.textDim)),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.56,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final drama = list[index];
                      return CoverCard(
                        drama: drama,
                        badge: drama.episodeCount > 0 ? '${drama.episodeCount}集' : null,
                        onTap: () => openDrama(context, drama),
                      );
                    },
                    childCount: list.length,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _featuredRail(BuildContext context, List<Drama> items) {
    final palette = AppPalette.of(context);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: '为你推荐', subtitle: '来自各站源的热门短剧'),
          SizedBox(
            height: 252,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length > 12 ? 12 : items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final drama = items[index];
                return SizedBox(
                  width: 132,
                  child: CoverCard(
                    drama: drama,
                    badge: drama.episodeCount > 0 ? '${drama.episodeCount}集' : null,
                    onTap: () => openDrama(context, drama),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: palette.line),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }
}
