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
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String _updatedText = '';
  String _warning = '';
  String? _error;
  String _lastSource = '';
  /// 榜单请求令牌：连点几个榜单 tab 时只认最后一次，否则先发的慢请求
  /// 会把后发的结果盖掉，列表和选中的 tab 对不上。
  int _token = 0;

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
      // 作废在途请求，同时把 loading 复位：令牌对不上时 finally 不会兜底，
      // 不复位就会一直卡在骨架屏上。
      _token++;
      if (mounted) {
        setState(() {
          _items = const [];
          _boardId = null;
          _loading = false;
          _loadingMore = false;
          _hasMore = false;
          _updatedText = '';
          _warning = '';
        });
      }
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
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await api.rankingBoards();
      if (!mounted || token != _token) return;
      final source = context.read<AppState>().selectedSource;
      _lastSource = source;
      final visible = source.isEmpty ? boards : boards.where((board) => board.source == source).toList();
      setState(() {
        _boards = boards;
        _boardId = visible.isNotEmpty ? visible.first.id : (boards.isNotEmpty ? boards.first.id : null);
      });
      if (_boardId != null) await _loadItems(_boardId!);
    } on ApiException catch (error) {
      if (!mounted || token != _token) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted && token == _token) setState(() => _loading = false);
    }
  }

  Future<void> _loadItems(String boardId, {int page = 1, bool append = false}) async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    final token = ++_token;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        // 换榜单时先清空：否则上一个榜单的条目会挂着，等新数据回来才替换
        _loading = true;
        _items = const [];
        _hasMore = false;
        _updatedText = '';
        _warning = '';
      }
      _boardId = boardId;
      _error = null;
    });
    try {
      final result = await api.rankingItems(boardId, page);
      if (!mounted || token != _token) return;
      setState(() {
        _items = append ? [..._items, ...result.items] : result.items;
        _page = result.page;
        _hasMore = result.hasMore;
        _updatedText = result.updatedText;
        _warning = result.warning;
      });
    } on ApiException catch (error) {
      if (!mounted || token != _token) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted && token == _token) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _loadMore() {
    final boardId = _boardId;
    if (boardId == null || _loadingMore || !_hasMore) return;
    _loadItems(boardId, page: _page + 1, append: true);
  }

  RankingBoard? get _currentBoard {
    for (final board in _boards) {
      if (board.id == _boardId) return board;
    }
    return null;
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
                subtitle: _updatedText.isNotEmpty
                    ? _updatedText
                    : (state.selectedSource.isEmpty ? '按站源实时抓取' : '${state.selectedSourceLabel}榜单'),
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
            if (_boardNote.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    _boardNote,
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: palette.textDim),
                  ),
                ),
              ),
            if (_warning.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 13, color: palette.accent.withValues(alpha: 0.9)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _warning,
                          style: TextStyle(fontSize: 11.5, color: palette.accent.withValues(alpha: 0.9)),
                        ),
                      ),
                    ],
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
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverList.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _RankRow(rank: item.rank == 0 ? index + 1 : item.rank, drama: item.drama);
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  child: Center(child: _footer(palette)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 当前榜单的说明：优先用服务端给的 description，没有就用站源名兜底。
  String get _boardNote {
    final board = _currentBoard;
    if (board == null) return '';
    return board.description;
  }

  Widget _footer(AppPalette palette) {
    if (_loadingMore) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
      );
    }
    if (_hasMore) {
      return GhostButton(
        label: '加载更多',
        icon: Icons.expand_more_rounded,
        onPressed: _loadMore,
      );
    }
    // 只有一页的榜单（黄果、帝果）不显示「已到底」，避免看起来像出错
    if (_page <= 1) return const SizedBox.shrink();
    return Text('已经到底了', style: TextStyle(fontSize: 11.5, color: palette.textDim));
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
