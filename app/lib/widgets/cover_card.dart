import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';

String resolveCover(BuildContext context, String raw) {
  if (raw.isEmpty) return '';
  final api = context.read<AppState>().api;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  return api?.resolve(raw) ?? raw;
}

/// 3:4 竖版封面卡，底部压一层渐隐，右上角显示集数。
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.drama,
    this.onTap,
    this.showTitle = true,
    this.aspect = 3 / 4,
    this.badge,
    this.heroTag,
  });

  final Drama drama;
  final VoidCallback? onTap;
  final bool showTitle;
  final double aspect;
  final String? badge;

  /// 跨页飞入动画的标识。同一个页面里同一部剧可能出现多次（比如首页的
  /// 「为你推荐」和「全部短剧」），tag 必须按出现位置区分，否则 Flutter 会抛
  /// 「There are multiple heroes that share the same tag」。为 null 则不做动画。
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final url = resolveCover(context, drama.cover);
    Widget cover = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: palette.surfaceHigh),
            if (url.isNotEmpty)
              Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 480,
                errorBuilder: (_, __, ___) => _placeholder(palette),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(color: palette.surfaceHigh);
                },
              )
            else
              _placeholder(palette),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x99000000)],
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: _Chip(text: badge!),
              ),
            if (drama.vip)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7B25C),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'VIP',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF3A2500)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (heroTag != null) cover = Hero(tag: heroTag!, child: cover);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          cover,
          if (showTitle) ...[
            const SizedBox(height: 7),
            Text(
              drama.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, color: palette.text),
            ),
            if (drama.subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  drama.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.2, color: palette.textDim),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _placeholder(AppPalette palette) {
    return Center(
      child: Icon(Icons.movie_outlined, size: 22, color: palette.textDim.withValues(alpha: 0.5)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10, height: 1.1, color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }
}
