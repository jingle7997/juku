import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';
import '../widgets/chrome.dart';
import '../widgets/cover_card.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Drama> _results = const [];
  List<Drama> _local = const [];
  bool _loading = false;
  String? _error;
  String _keyword = '';
  /// 搜索请求令牌，快速连续搜索时只认最后一次
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) return;
    final state = context.read<AppState>();
    final api = state.api;
    final token = ++_searchToken;
    setState(() {
      _keyword = keyword;
      _error = null;
      _local = state.library
          .where((drama) =>
              drama.title.toLowerCase().contains(keyword.toLowerCase()) ||
              drama.category.contains(keyword) ||
              drama.tags.any((tag) => tag.contains(keyword)))
          .take(30)
          .toList();
      _results = const [];
      _loading = api != null;
    });
    if (api == null) return;
    try {
      final items = await api.search(keyword);
      if (!mounted || token != _searchToken) return;
      setState(() => _results = items);
    } on ApiException catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted && token == _searchToken) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final merged = <String, Drama>{for (final drama in _results) drama.id: drama, for (final drama in _local) drama.id: drama}.values.toList();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 44,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: palette.text),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: palette.textDim),
              const SizedBox(width: 7),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  // 输入时重建，否则右侧的清除按钮不会出现（它读的是 _controller.text）
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 14, color: palette.text),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '搜索短剧',
                    hintStyle: TextStyle(fontSize: 14, color: palette.textDim.withValues(alpha: 0.8)),
                  ),
                ),
              ),
              if (_controller.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _controller.clear();
                    // 让在途的搜索请求失效，避免清空后结果又跳回来
                    _searchToken++;
                    setState(() {
                      _results = const [];
                      _local = const [];
                      _keyword = '';
                      _loading = false;
                    });
                  },
                  child: Icon(Icons.close_rounded, size: 16, color: palette.textDim),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _submit(_controller.text),
            child: Text('搜索', style: TextStyle(fontSize: 14, color: palette.accent, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(context, merged),
    );
  }

  Widget _buildBody(BuildContext context, List<Drama> merged) {
    final palette = AppPalette.of(context);
    if (_keyword.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: '搜点什么',
        subtitle: '输入剧名、分类或站源关键词，\n会同时在本地剧库与在线站源中查找。',
      );
    }
    if (_loading && merged.isEmpty) return const LoadingGrid();
    if (merged.isEmpty) {
      return EmptyState(
        icon: Icons.sentiment_dissatisfied_outlined,
        title: _error ?? '没有找到匹配的短剧',
        subtitle: _error == null ? '换个关键词试试，或在网页端先更新剧库。' : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Text(
            '找到 ${merged.length} 部相关短剧',
            style: TextStyle(fontSize: 12, color: palette.textDim),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 16,
              childAspectRatio: 0.56,
            ),
            itemCount: merged.length,
            itemBuilder: (context, index) {
              final drama = merged[index];
              return CoverCard(
                drama: drama,
                badge: drama.episodeCount > 0 ? '${drama.episodeCount}集' : null,
                heroTag: 'search-${drama.id}',
                onTap: () => openDrama(context, drama, heroTag: 'search-${drama.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}
