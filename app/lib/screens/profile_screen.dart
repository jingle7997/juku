import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/theme.dart';
import '../state/app_state.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            Text('我的', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: palette.text, letterSpacing: -0.6)),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(gradient: palette.accentGradient, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('本机访客', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: palette.text)),
                      const SizedBox(height: 3),
                      Text(
                        state.serverUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.textDim),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F7A4D).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('已连接', style: TextStyle(fontSize: 11, color: Color(0xFF3BC98A), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _Group(
              title: '外观',
              children: [
                _ThemeRow(state: state),
              ],
            ),
            _Group(
              title: '站源',
              children: [
                _ActionRow(
                  label: '切换站源',
                  icon: Icons.swap_horiz_rounded,
                  trailingText: state.selectedSourceLabel,
                  onTap: () => _showSourceSheet(context, state),
                ),
              ],
            ),
            _Group(
              title: '服务器',
              children: [
                _InfoRow(label: '地址', value: state.serverUrl),
                _InfoRow(label: '剧库数量', value: '${state.library.length} 部'),
                _InfoRow(label: '追剧', value: '${state.following.length} 部'),
                _ActionRow(
                  label: '重新连接',
                  icon: Icons.sync_rounded,
                  onTap: () => state.refreshAll(),
                ),
                _ActionRow(
                  label: '断开连接',
                  icon: Icons.logout_rounded,
                  danger: true,
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: palette.surface,
                        title: Text('断开连接？', style: TextStyle(fontSize: 16, color: palette.text)),
                        content: Text('断开后需要重新输入服务器地址。', style: TextStyle(fontSize: 13, color: palette.textDim)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('断开', style: TextStyle(color: palette.accent))),
                        ],
                      ),
                    );
                    if (confirmed == true) state.disconnect();
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                '$kAppName iOS · $kAppVersion',
                style: TextStyle(fontSize: 11.5, color: palette.textDim.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.textDim)),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 14, color: palette.line),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13.5, color: palette.text)),
          const SizedBox(width: 16),
          // 用 Expanded 让右侧值占满剩余宽度；原来 Spacer + Flexible 会平分空间，
          // 长地址被硬生生截掉一半
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, color: palette.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.label, required this.icon, required this.onTap, this.danger = false, this.trailingText});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = danger ? palette.accent : palette.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13.5, color: color)),
            const Spacer(),
            if (trailingText != null)
              Text(trailingText!, style: TextStyle(fontSize: 12.5, color: palette.textDim)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 17, color: palette.textDim),
          ],
        ),
      ),
    );
  }
}

/// 换源面板：全部站源 + 每个站源，选中后首页与榜单只显示该站源
void _showSourceSheet(BuildContext context, AppState state) {
  final palette = AppPalette.of(context);
  final sources = state.availableSources;
  final counts = <String, int>{};
  for (final drama in state.library) {
    if (drama.source.isEmpty) continue;
    counts[drama.source] = (counts[drama.source] ?? 0) + 1;
  }

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (sheetContext) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: palette.line, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Text('切换站源', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: palette.text)),
                    const Spacer(),
                    Text('共 ${sources.length} 个', style: TextStyle(fontSize: 12, color: palette.textDim)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '切换后首页与榜单只显示该站源的短剧',
                    style: TextStyle(fontSize: 11.5, color: palette.textDim.withValues(alpha: 0.85)),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    _SourceTile(
                      title: '全部站源',
                      subtitle: '共 ${state.library.length} 部',
                      selected: state.selectedSource.isEmpty,
                      onTap: () {
                        state.setSource('');
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                    for (final source in sources)
                      _SourceTile(
                        title: sourceLabel(source),
                        subtitle: '${counts[source] ?? 0} 部',
                        selected: state.selectedSource == source,
                        onTap: () {
                          state.setSource(source);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                    if (sources.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          '剧库还没有加载到站源信息',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: palette.textDim),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.title, required this.subtitle, required this.selected, required this.onTap});

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? palette.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? palette.accent : palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 11.5, color: palette.textDim)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 19, color: palette.accent)
                else
                  Icon(Icons.circle_outlined, size: 19, color: palette.textDim.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    const options = [('深色', 'dark'), ('浅色', 'light'), ('跟随系统', 'system')];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => state.setThemeMode(option.$2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: state.themeMode == option.$2 ? palette.accent.withValues(alpha: 0.15) : palette.surfaceHigh,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: state.themeMode == option.$2 ? palette.accent : Colors.transparent),
                    ),
                    child: Text(
                      option.$1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: state.themeMode == option.$2 ? palette.accent : palette.textDim,
                      ),
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
