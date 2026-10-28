import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../app_scope.dart';
import '../../domain/theme_controller.dart';

/// Pre-blurs background photos once (memory + disk) and reuses across screens.
///
/// Avoids live [ImageFiltered] in the widget tree (Material ink crashes on
/// Windows). One decode+blur per asset/level; survives app restarts via PNG cache.
class BgBlurCache {
  BgBlurCache._();

  static final Map<String, ui.Image> _images = {};
  static final Map<String, Future<ui.Image>> _inflight = {};

  /// Finish screens use 0.5 — warm this at startup to avoid sharp→blur flash.
  static const commonBlurAmount = 0.5;

  static String _key(String asset, double blurAmount) {
    final bucket = (blurAmount.clamp(0.0, 1.0) * 10).round(); // 0..10
    return '$asset#$bucket';
  }

  static double _sigmaFor(double blurAmount) =>
      blurAmount.clamp(0.0, 1.0) * 24.0; // 0.5 → sigma 12

  static String _diskName(String key) =>
      'bg_blur_${key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.png';

  static ui.Image? peek(String asset, double blurAmount) =>
      _images[_key(asset, blurAmount)];

  static Future<ui.Image> obtain(String asset, double blurAmount) {
    final key = _key(asset, blurAmount);
    final hit = _images[key];
    if (hit != null) return Future.value(hit);
    return _inflight.putIfAbsent(key, () async {
      final fromDisk = await _loadDisk(key);
      if (fromDisk != null) {
        _images[key] = fromDisk;
        _inflight.remove(key);
        return fromDisk;
      }
      final image = await _render(asset, _sigmaFor(blurAmount));
      _images[key] = image;
      unawaited(_saveDisk(key, image));
      _inflight.remove(key);
      return image;
    });
  }

  /// Warm memory (+ disk) for typical finish-screen blur levels.
  static Future<void> warm(Iterable<String> assets, {double blurAmount = commonBlurAmount}) async {
    for (final asset in assets) {
      try {
        await obtain(asset, blurAmount);
      } catch (e, st) {
        debugPrint('BgBlurCache.warm failed for $asset: $e\n$st');
      }
    }
  }

  static Future<ui.Image?> _loadDisk(String key) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, _diskName(key)));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('BgBlurCache disk load: $e');
      return null;
    }
  }

  static Future<void> _saveDisk(String key, ui.Image image) async {
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, _diskName(key)));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } catch (e) {
      debugPrint('BgBlurCache disk save: $e');
    }
  }

  static Future<ui.Image> _render(String asset, double sigma) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 960,
    );
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width;
    final h = src.height;
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImage(src, Offset.zero, Paint());
    canvas.restore();
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    src.dispose();
    picture.dispose();
    return out;
  }
}

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
    /// 0…1 soft background blur (pre-rendered + cached, not live ImageFiltered).
    this.blurAmount = 0,
    /// Dim overlay opacity when [dim] is true (default slightly darker).
    this.dimOpacity = 0.45,
  });

  final Widget child;
  final bool dim;

  /// When false, always show photo (list screens). Enable only on home.
  final bool allowVideo;

  final double blurAmount;
  final double dimOpacity;

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

  ui.Image? _blurred;
  String? _blurRequestKey;
  int _blurGen = 0;

  bool _wantVideo(ThemeController theme) {
    if (!widget.allowVideo) return false;
    if (!theme.useVideoBg) return false;
    if (_videoFailed) return false;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBlurFromCache();
    _scheduleSync();
    _scheduleBlur();
  }

  @override
  void didUpdateWidget(covariant AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allowVideo != widget.allowVideo) {
      _scheduleSync();
    }
    if (oldWidget.blurAmount != widget.blurAmount) {
      _syncBlurFromCache();
      _scheduleBlur();
    }
  }

  /// Instant: use warm memory cache so first frame is already blurred.
  void _syncBlurFromCache() {
    final frost = widget.blurAmount.clamp(0.0, 1.0);
    if (frost < 0.01) {
      _blurred = null;
      _blurRequestKey = null;
      return;
    }
    final asset = AppScope.of(context).theme.bgImageAsset;
    final key = '$asset#${(frost * 10).round()}';
    final cached = BgBlurCache.peek(asset, frost);
    if (cached != null) {
      _blurred = cached;
      _blurRequestKey = key;
    }
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncVideo();
    });
  }

  void _scheduleBlur() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureBlurred();
    });
  }

  Future<void> _ensureBlurred() async {
    if (!mounted) return;
    final frost = widget.blurAmount.clamp(0.0, 1.0);
    if (frost < 0.01) {
      if (_blurred != null || _blurRequestKey != null) {
        setState(() {
          _blurred = null;
          _blurRequestKey = null;
        });
      }
      return;
    }

    final asset = AppScope.of(context).theme.bgImageAsset;
    final key = '$asset#${(frost * 10).round()}';
    final cached = BgBlurCache.peek(asset, frost);
    if (cached != null) {
      if (!identical(_blurred, cached) || _blurRequestKey != key) {
        setState(() {
          _blurred = cached;
          _blurRequestKey = key;
        });
      }
      return;
    }
    if (_blurRequestKey == key && _blurred != null) return;

    final gen = ++_blurGen;
    _blurRequestKey = key;
    try {
      final image = await BgBlurCache.obtain(asset, frost);
      if (!mounted || gen != _blurGen) return;
      setState(() => _blurred = image);
    } catch (e, st) {
      debugPrint('AppBackground: blur cache failed, sharp photo. $e\n$st');
    }
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
    _blurGen++;
    final v = _video;
    _video = null;
    v?.dispose();
    super.dispose();
  }

  Widget _buildPhoto(ThemeController theme, Color fallback) {
    final frost = widget.blurAmount.clamp(0.0, 1.0);
    final blurred = _blurred ??
        (frost >= 0.01
            ? BgBlurCache.peek(theme.bgImageAsset, frost)
            : null);
    if (frost >= 0.01 && blurred != null) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: blurred.width.toDouble(),
          height: blurred.height.toDouble(),
          child: RawImage(
            image: blurred,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }
    return Image.asset(
      theme.bgImageAsset,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      cacheWidth: 1280,
      errorBuilder: (_, __, ___) => ColoredBox(color: fallback),
    );
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
        _scheduleBlur();

        final frost = widget.blurAmount.clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildPhoto(theme, Theme.of(context).colorScheme.surface),
            if (frost >= 0.01)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.10 + frost * 0.12),
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
              ColoredBox(
                color: Colors.black.withValues(
                  alpha: widget.dimOpacity.clamp(0.0, 0.85),
                ),
              ),
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
