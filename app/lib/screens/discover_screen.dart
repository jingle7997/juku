import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';
import '../widgets/chrome.dart';
import '../widgets/cover_card.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<RankingBoard> _boards = const [];
  List<RankingItem> _items = const [];
  String? _boardId;
  bool _loading = false;
  String? _error;
  String _lastSource = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoards());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 站源在「我的」里切换后，这里要跟着换榜单。
    // 放在 didChangeDependencies 而不是 build：build 会频繁触发，
    // 每次都注册一个 post-frame 回调纯属浪费。
    final source = context.watch<AppState>().selectedSource;
    if (source == _lastSource) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSource(source);
    });
  }

  /// 站源在「我的」里切换后，这里要跟着换榜单
  void _syncSource(String source) {
    if (source == _lastSource) return;
    _lastSource = source;
    final visible = _visibleBoards(source);
    if (visible.isEmpty) {
      if (mounted) setState(() => _items = const []);
      return;
    }
    if (_boardId == null || !visible.any((board) => board.id == _boardId)) {
      _loadItems(visible.first.id);
    }
  }

  List<RankingBoard> _visibleBoards(String source) {
    if (source.isEmpty) return _boards;
    return _boards.where((board) => board.source == source).toList();
  }

  Future<void> _loadBoards() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await api.rankingBoards();
      if (!mounted) return;
      final source = context.read<AppState>().selectedSource;
      _lastSource = source;
      final visible = source.isEmpty ? boards : boards.where((board) => board.source == source).toList();
      setState(() {
        _boards = boards;
        _boardId = visible.isNotEmpty ? visible.first.id : (boards.isNotEmpty ? boards.first.id : null);
      });
      if (_boardId != null) await _loadItems(_boardId!);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadItems(String boardId) async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _boardId = boardId;
    });
    try {
      final items = await api.rankingItems(boardId, 1);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.watch<AppState>();
    final boards = _visibleBoards(state.selectedSource);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发现',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: palette.text, letterSpacing: -0.6),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      ),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.line),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: 19, color: palette.textDim),
                            const SizedBox(width: 8),
                            Text(
                              '搜索剧名、站源或分类',
                              style: TextStyle(fontSize: 13.5, color: palette.textDim.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (state.selectedSource.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 15, color: palette.textDim),
                          const SizedBox(width: 6),
                          Text(
                            '当前站源：${state.selectedSourceLabel}',
                            style: TextStyle(fontSize: 12, color: palette.textDim),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '热门榜单',
                subtitle: state.selectedSource.isEmpty ? '按站源实时抓取' : '${state.selectedSourceLabel}榜单',
              ),
            ),
            if (boards.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: boards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final board = boards[index];
                      final active = board.id == _boardId;
                      return GestureDetector(
                        onTap: () => _loadItems(board.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: active ? palette.accentGradient : null,
                            color: active ? null : palette.surface,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: active ? Colors.transparent : palette.line),
                          ),
                          child: Text(
                            board.name,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: active ? Colors.white : palette.text,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (_loading && _items.isEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 12), child: LoadingGrid(count: 6)))
            else if (_items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: EmptyState(
                    icon: Icons.leaderboard_outlined,
                    title: _error ?? (boards.isEmpty && state.selectedSource.isNotEmpty ? '${state.selectedSourceLabel}暂未提供榜单' : '暂无榜单数据'),
                    subtitle: _error == null
                        ? (boards.isEmpty && state.selectedSource.isNotEmpty
                            ? '在「我的 → 站源」里切换到全部站源看看。'
                            : '榜单由各站源提供，稍后重试或先浏览剧库。')
                        : null,
                    action: GhostButton(label: '重新加载', icon: Icons.refresh_rounded, onPressed: _loadBoards),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                sliver: SliverList.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _RankRow(rank: item.rank == 0 ? index + 1 : item.rank, drama: item.drama);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.drama});

  final int rank;
  final Drama drama;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hot = rank <= 3;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openDrama(context, drama, heroTag: 'rank-${drama.id}'),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: hot ? 20 : 15,
                fontWeight: FontWeight.w800,
                fontStyle: hot ? FontStyle.italic : FontStyle.normal,
                color: hot ? palette.accent : palette.textDim,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            height: 76,
            child: CoverCard(
              drama: drama,
              showTitle: false,
              heroTag: 'rank-${drama.id}',
              onTap: () => openDrama(context, drama, heroTag: 'rank-${drama.id}'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  drama.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: palette.text),
                ),
                const SizedBox(height: 4),
                Text(
                  drama.subtitle.isEmpty ? sourceLabel(drama.source) : drama.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
                if (drama.heat.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('热度 ${drama.heat}', style: TextStyle(fontSize: 11, color: palette.accent.withValues(alpha: 0.85))),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: palette.textDim.withValues(alpha: 0.6)),
        ],
      ),
    );
  }
}
