import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';
import '../widgets/chrome.dart';
import '../widgets/cover_card.dart';
import 'detail_screen.dart';

class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.watch<AppState>();
    final entries = _tab == 0 ? state.following : state.history;

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Text('我的剧集', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: palette.text, letterSpacing: -0.6)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _tab == 0 ? state.loadFollowing() : state.loadHistory(),
                    icon: Icon(Icons.refresh_rounded, size: 20, color: palette.textDim),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Segmented(
                labels: ['追剧 ${state.following.length}', '记录 ${state.history.length}'],
                index: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: palette.accent,
                backgroundColor: palette.surface,
                onRefresh: () => _tab == 0 ? state.loadFollowing() : state.loadHistory(),
                child: entries.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 60),
                          EmptyState(
                            icon: _tab == 0 ? Icons.bookmark_border_rounded : Icons.history_rounded,
                            title: _tab == 0 ? '还没有追剧' : '还没有观看记录',
                            subtitle: _tab == 0 ? '在剧集详情页点「追剧」，更新时就能在这里看到。' : '播放过的短剧会自动记录进度。',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) => _EntryRow(
                          entry: entries[index],
                          mode: _tab,
                          onRemove: () => _remove(entries[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(LibraryEntry entry) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_tab == 0) {
        await state.unfollow(entry.dramaId);
      } else {
        await state.clearHistory(dramaId: entry.dramaId);
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
    }
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.mode, required this.onRemove});

  final LibraryEntry entry;
  final int mode;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.read<AppState>();
    final drama = entry.drama ?? state.dramaById(entry.dramaId);
    // 本地剧库没这部剧时，用服务端给的剧名兜底，别把 hongguo:123 这种 id 露出来
    final title = drama?.title ?? (entry.title.isNotEmpty ? entry.title : entry.dramaId);
    final progress = entry.progress;
    final stamp = entry.updatedAt;
    final subtitle = mode == 1
        ? (entry.episodeLabel.isNotEmpty
            ? '看到${entry.episodeLabel}'
            : (entry.episode > 0 ? '看到第 ${entry.episode} 集' : (drama?.subtitle ?? '')))
        : (entry.total > 0 ? '共 ${entry.total} 集' : (drama?.subtitle ?? ''));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (drama != null) openDrama(context, drama, heroTag: 'entry-${entry.dramaId}');
      },
      onLongPress: onRemove,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            height: 90,
            child: drama != null
                ? CoverCard(
                    drama: drama,
                    showTitle: false,
                    heroTag: 'entry-${entry.dramaId}',
                    onTap: () => openDrama(context, drama, heroTag: 'entry-${entry.dramaId}'),
                  )
                : Container(
                    decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.card)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: palette.text),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.textDim),
                ),
                if (mode == 1 && progress > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: palette.surfaceHigh,
                      valueColor: AlwaysStoppedAnimation(palette.accent),
                    ),
                  ),
                ],
                if (stamp != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    DateFormat('MM-dd HH:mm').format(stamp),
                    style: TextStyle(fontSize: 11, color: palette.textDim.withValues(alpha: 0.7)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(11), border: Border.all(color: palette.line)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? palette.accent.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: i == index ? palette.accent.withValues(alpha: 0.5) : Colors.transparent),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                      color: i == index ? palette.accent : palette.textDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
