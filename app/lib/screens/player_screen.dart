import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/drama.dart';
import '../state/app_state.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.drama, this.initialEpisode = 1});

  final Drama drama;
  final int initialEpisode;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  PlaybackSession? _session;
  PlaybackSource? _source;
  int _episode = 1;
  /// 上报序号，**每次上报都要递增**。服务端用 session.historySequence 丢弃
  /// 乱序到达的旧进度，序号不变的话第二次之后的上报会被静默忽略。
  int _sequence = 0;
  /// 切集请求令牌，用来丢弃被后续请求取代的旧结果
  int _loadToken = 0;
  double _pendingStart = 0;

  bool _loading = true;
  String? _error;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  Timer? _progressTimer;
  bool _switching = false;
  double _rate = 1;
  bool _landscape = false;
  AppState? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = context.read<AppState>();
    _episode = widget.initialEpisode;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.enable();
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    // 关会话时顺带落一次进度：run / sequence 必须是真的，
    // 服务端对 run==0 或 sequence==0 会判为无效，等于白丢。
    final session = _session;
    final api = _state?.api;
    final video = _video;
    final source = _source;
    if (session != null && api != null) {
      final ready = video != null && video.value.isInitialized;
      final position = ready ? video.value.position.inMilliseconds / 1000 : 0.0;
      api
          .closePlayback(
            session.session,
            run: source?.run ?? 0,
            sequence: ++_sequence,
            episode: ready && position > 0.5 ? _episode : null,
            position: position,
            duration: ready ? video.value.duration.inMilliseconds / 1000 : 0,
          )
          .catchError((_) {});
    }
    _video?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _reportProgress();
      _video?.pause();
    }
  }

  Future<void> _bootstrap() async {
    final api = _state?.api ?? context.read<AppState>().api;
    if (api == null) {
      setState(() => _error = '尚未连接服务器');
      return;
    }
    try {
      final session = await api.openPlayback(widget.drama.id, resume: true);
      if (!mounted) return;
      if (session.episodes.isEmpty) {
        setState(() {
          _loading = false;
          _error = '站点没有返回可播放的分集';
        });
        return;
      }
      _session = session;
      final total = session.episodes.length;
      var start = widget.initialEpisode > 0 ? widget.initialEpisode : session.initialIndex;
      if (start < 1) start = 1;
      if (start > total) start = total;
      _pendingStart = start == session.initialIndex ? session.initialPosition : 0;
      await _loadEpisode(start, start: _pendingStart);
      if (session.resumeMessage.isNotEmpty && mounted) {
        _toast(session.resumeMessage);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _loadEpisode(int index, {double start = 0}) async {
    final api = _state?.api ?? context.read<AppState>().api;
    final session = _session;
    if (api == null || session == null) return;
    // 快速连点选集时，只认最后一次请求的结果
    final token = ++_loadToken;
    // 切集期间停掉进度定时器：这时 _video 还是上一集的、_episode 已经是新集，
    // 定时器若照常触发，会把旧集的播放位置标成新集上报，服务端按
    // run.episode != progress.episode 丢弃，白丢一次进度。
    _progressTimer?.cancel();
    setState(() {
      _switching = true;
      _error = null;
      _episode = index;
    });
    try {
      final source = await api.openStream(session: session.session, episode: index, start: start);
      if (!mounted || token != _loadToken) return;
      final url = api.resolve(source.url);
      final previous = _video;
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted || token != _loadToken) {
        await controller.dispose();
        return;
      }
      _source = source;
      await previous?.dispose();
      setState(() {
        _video = controller;
        _loading = false;
        _switching = false;
      });
      controller.addListener(_onTick);
      if (start > 0 && controller.value.duration > Duration.zero) {
        final target = start.clamp(0, controller.value.duration.inMilliseconds / 1000);
        await controller.seekTo(Duration(milliseconds: (target * 1000).round()));
      }
      await controller.setPlaybackSpeed(_rate);
      await controller.play();
      _startProgressTimer();
      _scheduleHide();
    } on ApiException catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _switching = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _switching = false;
        _error = '播放失败：$error';
      });
    }
  }

  void _onTick() {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isCompleted) {
      // 先摘掉监听：否则切集失败时这个已播完的 controller 会每帧继续触发，
      // 变成不停地重新请求 openStream
      video.removeListener(_onTick);
      _reportProgress(completed: true);
      _nextEpisode();
      return;
    }
    if (mounted) setState(() {});
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) => _reportProgress());
  }

  Future<void> _reportProgress({bool completed = false}) async {
    final api = _state?.api;
    final session = _session;
    final video = _video;
    final source = _source;
    if (api == null || session == null || video == null || source == null) return;
    if (!video.value.isInitialized) return;
    final position = video.value.position.inMilliseconds / 1000;
    if (position <= 0.5 && !completed) return;
    try {
      await api.reportProgress(
        session: session.session,
        run: source.run,
        sequence: ++_sequence,
        episode: _episode,
        position: position,
        duration: video.value.duration.inMilliseconds / 1000,
        completed: completed,
      );
    } catch (_) {
      // 进度上报失败不打扰用户
    }
  }

  void _nextEpisode() {
    final total = _session?.episodes.length ?? 0;
    if (_episode >= total) return;
    _reportProgress();
    _loadEpisode(_episode + 1);
  }

  void _prevEpisode() {
    if (_episode <= 1) return;
    _reportProgress();
    _loadEpisode(_episode - 1);
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (_video?.value.isPlaying ?? false)) setState(() => _controlsVisible = false);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _landscape = !_landscape);
    if (_landscape) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final ready = video != null && video.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: video.value.aspectRatio == 0 ? 16 / 9 : video.value.aspectRatio,
                  child: VideoPlayer(video),
                ),
              )
            else
              Center(
                child: _loading ? const CircularProgressIndicator(color: Colors.white70) : const SizedBox.shrink(),
              ),
            if (_error != null) _errorOverlay(),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _controls(context, ready),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorOverlay() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 34),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              if (_session == null) {
                _bootstrap();
              } else {
                _loadEpisode(_episode);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('重试', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, bool ready) {
    final video = _video;
    final palette = AppPalette.of(context);
    final total = _session?.episodes.length ?? 0;
    final episodeLabel = total > 0 ? '第 $_episode 集 / 共 $total 集' : '';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
          stops: [0, 0.25, 0.6, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 19),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _session?.title.isNotEmpty == true ? _session!.title : widget.drama.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                        ),
                        if (episodeLabel.isNotEmpty)
                          Text(episodeLabel, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  if (total > 0)
                    TextButton(
                      onPressed: _showEpisodes,
                      child: const Text('选集', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                ],
              ),
            ),
            const Spacer(),
            if (_switching) const CircularProgressIndicator(color: Colors.white70),
            const Spacer(),
            if (ready) _bottomBar(context, video!, total, palette),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, VideoPlayerController video, int total, AppPalette palette) {
    final duration = video.value.duration;
    final position = video.value.position;
    final max = duration.inMilliseconds.toDouble() <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final value = position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_format(position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: palette.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: palette.accent,
                  ),
                  child: Slider(
                    value: value,
                    max: max,
                    onChanged: (value) {
                      video.seekTo(Duration(milliseconds: value.round()));
                      _scheduleHide();
                    },
                  ),
                ),
              ),
              Text(_format(duration), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _episode > 1 ? _prevEpisode : null,
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
              ),
              IconButton(
                onPressed: () {
                  if (video.value.isPlaying) {
                    video.pause();
                    _reportProgress();
                  } else {
                    video.play();
                  }
                  _scheduleHide();
                  setState(() {});
                },
                icon: Icon(
                  video.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              IconButton(
                onPressed: _episode < total ? _nextEpisode : null,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
              ),
              const Spacer(),
              _pill(
                label: '${_rate.toStringAsFixed(_rate == _rate.roundToDouble() ? 0 : 1)}x',
                onTap: _showRates,
              ),
              const SizedBox(width: 8),
              _pill(
                label: _landscape ? '竖屏' : '全屏',
                onTap: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showRates() {
    const rates = [0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('播放速度', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            for (final rate in rates)
              ListTile(
                dense: true,
                title: Text('${rate}x', style: const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: _rate == rate ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                onTap: () async {
                  Navigator.of(context).pop();
                  setState(() => _rate = rate);
                  await _video?.setPlaybackSpeed(rate);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEpisodes() {
    final episodes = _session?.episodes ?? const <PlaybackEpisode>[];
    if (episodes.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161C),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('选集（${episodes.length}）', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.5,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final active = episode.index == _episode;
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      _reportProgress();
                      _loadEpisode(episode.index);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? const Color(0x33FF4D6D) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: active ? const Color(0xFFFF4D6D) : Colors.white12),
                      ),
                      child: Text(
                        '${episode.index}',
                        style: TextStyle(
                          color: active ? const Color(0xFFFF4D6D) : Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) return '${duration.inHours}:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
