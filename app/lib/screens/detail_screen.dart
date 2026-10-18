import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';
import '../widgets/chrome.dart';
import '../widgets/cover_card.dart';
import 'player_screen.dart';

Future<void> openDrama(BuildContext context, Drama drama, {Object? heroTag}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => DetailScreen(drama: drama, heroTag: heroTag),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.drama, this.heroTag});

  final Drama drama;

  /// 与来源卡片的 Hero tag 对应；为 null 时不做飞入动画
  final Object? heroTag;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _descExpanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.watch<AppState>();
    final drama = state.dramaById(widget.drama.id) ?? widget.drama;
    final following = state.isFollowing(drama.id);
    final history = state.history.where((e) => e.dramaId == drama.id).toList();
    final entry = history.isNotEmpty ? history.first : null;
    final resumeEpisode = entry?.episode ?? 0;
    final episodes = drama.episodeCount > 0 ? drama.episodeCount : (entry?.episode ?? 0);
    final cover = resolveCover(context, drama.cover);

    return Scaffold(
      backgroundColor: palette.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            backgroundColor: palette.background,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Center(
                child: _RoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: palette.surfaceHigh),
                  if (cover.isNotEmpty)
                    _coverImage(cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0x66000000),
                          const Color(0x00000000),
                          palette.background.withValues(alpha: 0.82),
                          palette.background,
                        ],
                        stops: const [0, 0.3, 0.86, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25, color: palette.text, letterSpacing: -0.4),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Tag(text: sourceLabel(drama.source), highlight: true),
                      if (drama.category.isNotEmpty) _Tag(text: drama.category),
                      if (drama.episodeCount > 0) _Tag(text: '${drama.episodeCount} 集'),
                      if (drama.releaseStatus == 'finished') const _Tag(text: '已完结'),
                      if (drama.score.isNotEmpty) _Tag(text: '评分 ${drama.score}'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: PrimaryButton(
                          label: entry != null && resumeEpisode > 0 ? '继续第 $resumeEpisode 集' : '开始播放',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => _play(context, resumeEpisode > 0 ? resumeEpisode : 1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: GhostButton(
                          label: following ? '已追剧' : '追剧',
                          icon: following ? Icons.check_rounded : Icons.add_rounded,
                          onPressed: () async {
                            try {
                              await state.toggleFollowing(drama);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (drama.desc.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    Text('简介', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.text)),
                    const SizedBox(height: 7),
                    Text(
                      drama.desc,
                      maxLines: _descExpanded ? null : 3,
                      overflow: _descExpanded ? null : TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 1.65, color: palette.textDim),
                    ),
                    if (drama.desc.length > 60)
                      GestureDetector(
                        onTap: () => setState(() => _descExpanded = !_descExpanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _descExpanded ? '收起' : '展开',
                            style: TextStyle(fontSize: 12.5, color: palette.accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                  if (episodes > 0) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('选集', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.text)),
                        const SizedBox(width: 8),
                        Text('共 $episodes 集', style: TextStyle(fontSize: 12, color: palette.textDim)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _EpisodeGrid(
                      total: episodes,
                      current: resumeEpisode,
                      onPick: (index) => _play(context, index),
                    ),
                    const SizedBox(height: 40),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverImage(String cover) {
    final image = Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox());
    final tag = widget.heroTag;
    return tag == null ? image : Hero(tag: tag, child: image);
  }

  void _play(BuildContext context, int episode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlayerScreen(drama: widget.drama, initialEpisode: episode),
      ),
    );
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.total, required this.current, required this.onPick});

  final int total;
  final int current;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.35,
      ),
      itemCount: total,
      itemBuilder: (context, index) {
        final number = index + 1;
        final active = number == current;
        return GestureDetector(
          onTap: () => onPick(number),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? palette.accent.withValues(alpha: 0.16) : palette.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: active ? palette.accent : palette.line),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? palette.accent : palette.text,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.highlight = false});
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? palette.accent.withValues(alpha: 0.14) : palette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: highlight ? Colors.transparent : palette.line),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: highlight ? palette.accent : palette.textDim,
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
