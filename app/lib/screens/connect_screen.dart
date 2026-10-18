import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/chrome.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    final recent = state.prefs.recentServers;
    _controller = TextEditingController(text: recent.isNotEmpty ? recent.first : 'http://192.168.1.10:8998');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect([String? value]) async {
    final target = (value ?? _controller.text).trim();
    if (target.isEmpty) {
      setState(() => _error = '请填写服务器地址');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().connect(target);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '连接失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final state = context.watch<AppState>();
    final recent = state.prefs.recentServers;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Positioned(
            top: -160,
            left: -80,
            right: -80,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [palette.accent.withValues(alpha: 0.22), palette.background.withValues(alpha: 0)],
                  radius: 0.9,
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: palette.accentGradient,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(color: palette.accent.withValues(alpha: 0.35), blurRadius: 26, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 22),
                Text(
                  '短剧库',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: palette.text, letterSpacing: -0.8),
                ),
                const SizedBox(height: 8),
                Text(
                  '连接运行在电脑或 NAS 上的剧库服务，\n即可在手机上追剧。',
                  style: TextStyle(fontSize: 14, height: 1.6, color: palette.textDim),
                ),
                const SizedBox(height: 36),
                Text('服务器地址', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textDim)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _error == null ? palette.line : palette.accent.withValues(alpha: 0.6)),
                  ),
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    style: TextStyle(fontSize: 15, color: palette.text),
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      hintText: 'http://192.168.1.10:8998',
                      hintStyle: TextStyle(color: palette.textDim.withValues(alpha: 0.7), fontSize: 15),
                      prefixIcon: Icon(Icons.dns_outlined, size: 19, color: palette.textDim),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 14, color: palette.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_error!, style: TextStyle(fontSize: 12.5, color: palette.accent, height: 1.4)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                PrimaryButton(label: _busy ? '正在连接' : '连接', loading: _busy, onPressed: _busy ? null : _connect),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 34),
                  Text('最近连接', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textDim)),
                  const SizedBox(height: 10),
                  ...recent.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _busy
                              ? null
                              : () {
                                  _controller.text = item;
                                  _connect(item);
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            child: Row(
                              children: [
                                Icon(Icons.history_rounded, size: 16, color: palette.textDim),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13.5, color: palette.text),
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, size: 18, color: palette.textDim),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  '提示：电脑端启动剧库后，用同一 Wi-Fi 下的手机访问\n「http://电脑IP:8998」即可。首次使用请在网页端确认已开启访问权限。',
                  style: TextStyle(fontSize: 11.5, height: 1.7, color: palette.textDim.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
