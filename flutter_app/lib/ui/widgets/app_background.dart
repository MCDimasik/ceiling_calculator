import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app_scope.dart';
import '../../domain/theme_controller.dart';

/// Full-bleed photo background; optional muted looping video (home only).
///
/// On Windows, `video_player` often fails with external GL textures and can crash
/// the embedder when many screens each open a player. Video is therefore opt-in
/// via [allowVideo] and auto-falls back to photo after the first failure.
class AppBackground extends StatefulWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.dim = false,
    this.allowVideo = false,
  });

  final Widget child;
  final bool dim;

  /// When false, always show photo (list screens). Enable only on home.
  final bool allowVideo;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  VideoPlayerController? _video;
  String? _loadedVideoAsset;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _syncing = false;
  bool? _lastWantVideo;

  bool _wantVideo(ThemeController theme) {
    if (!widget.allowVideo) return false;
    if (!theme.useVideoBg) return false;
    if (_videoFailed) return false;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allowVideo != widget.allowVideo) {
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncVideo();
    });
  }

  Future<void> _syncVideo() async {
    if (!mounted || _syncing) return;
    final theme = AppScope.of(context).theme;
    final want = _wantVideo(theme);
    final asset = theme.bgVideoAsset;

    if (!want) {
      if (_video != null) {
        _syncing = true;
        await _disposeVideo();
        _syncing = false;
        if (mounted) setState(() {});
      }
      _lastWantVideo = false;
      return;
    }

    if (_lastWantVideo == true && _loadedVideoAsset == asset && _video != null) {
      return;
    }
    _lastWantVideo = true;

    _syncing = true;
    await _disposeVideo();
    final c = VideoPlayerController.asset(asset);
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _loadedVideoAsset = asset;
        _videoReady = true;
        _videoFailed = false;
      });
    } catch (e, st) {
      debugPrint('AppBackground: video failed, using photo. $e\n$st');
      await c.dispose();
      _videoFailed = true;
      if (mounted) {
        setState(() {
          _video = null;
          _loadedVideoAsset = null;
          _videoReady = false;
        });
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _disposeVideo() async {
    final v = _video;
    _video = null;
    _loadedVideoAsset = null;
    _videoReady = false;
    try {
      await v?.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    final v = _video;
    _video = null;
    v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppScope.of(context).theme;
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        final want = _wantVideo(theme);
        if (want != _lastWantVideo ||
            (want && _loadedVideoAsset != theme.bgVideoAsset && !_syncing)) {
          _scheduleSync();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              theme.bgImageAsset,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              // Downscale decode — full-res bg was a major open-screen hitch.
              cacheWidth: 1280,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
            if (want && _videoReady && _video != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _video!.value.size.width,
                  height: _video!.value.size.height,
                  child: VideoPlayer(_video!),
                ),
              ),
            if (widget.dim)
              ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
            widget.child,
          ],
        );
      },
    );
  }
}

/// Desktop platforms where video_player external textures crash the embedder.
bool get videoBgUnsupportedPlatform {
  if (kIsWeb) return false;
  try {
    return Platform.isWindows || Platform.isLinux;
  } catch (_) {
    return false;
  }
}
