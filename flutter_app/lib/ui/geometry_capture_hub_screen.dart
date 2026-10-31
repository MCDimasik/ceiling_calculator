import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../domain/design_walls_baseline.dart';
import '../domain/device_capabilities.dart';
import '../domain/finish_design_baseline.dart';
import '../domain/finish_model.dart' show AppModule;
import '../domain/geometry_capture_apply.dart';
import '../domain/models.dart';
import '../domain/room_plan_service.dart';
import '../domain/room_scan_import.dart';
import '../domain/wall_polygon_diff.dart';
import '../platform/geometry_capture_channel.dart';
import 'photo_plan_capture_screen.dart';
import 'room_editor_screen.dart';
import 'widgets/screen_scaffold.dart';

/// Unified entry: photo plan, RoomPlan (iOS), ARCore (Android).
class GeometryCaptureHubScreen extends StatefulWidget {
  const GeometryCaptureHubScreen({
    super.key,
    required this.projectId,
    required this.roomId,
    this.module = AppModule.ceilingLayout,
  });

  final int projectId;
  final int roomId;

  /// Passed through to [RoomEditorScreen] for exit → overview vs layout.
  final AppModule module;

  @override
  State<GeometryCaptureHubScreen> createState() =>
      _GeometryCaptureHubScreenState();
}

class _GeometryCaptureHubScreenState extends State<GeometryCaptureHubScreen> {
  Room? _room;
  bool _loading = true;
  bool _busyScan = false;
  String? _lastError;
  bool _roomPlanSupported = false;
  ArCoreAvailability _arCore = ArCoreAvailability.unknown;
  List<FeatureCapability>? _caps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _lastError = null;
    });
    try {
      final project =
          await AppScope.of(context).projects.getProject(widget.projectId);
      Room? room;
      if (project != null) {
        for (final r in project.rooms) {
          if (r.id == widget.roomId) room = r;
        }
      }
      final caps = await DeviceCapabilities.geometryCaptureReport();
      final rp = await RoomPlanService.isSupported();
      final ar = await GeometryCaptureChannel.arCoreAvailability();
      if (!mounted) return;
      setState(() {
        _room = room;
        _caps = caps;
        _roomPlanSupported = rp;
        _arCore = ar;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastError = e.toString();
      });
    }
  }

  void _openEditor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RoomEditorScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
          module: widget.module,
        ),
      ),
    );
  }

  void _showScanError({
    required String message,
    VoidCallback? onRetry,
  }) {
    setState(() => _lastError = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: onRetry != null ? 'Повторить' : 'Редактор',
          onPressed: onRetry ?? _openEditor,
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _confirmAndApply(RoomScanImportResult result) async {
    final room = _room;
    if (room?.id == null || result.walls.length < 3) return;

    snapshotFinishDesignIfNeeded(room!);
    final diff = compareWallPolygons(readDesignWalls(room), result.walls);
    final choice = await showCaptureApplyDialog(
      context: context,
      room: room,
      result: result,
      diff: diff,
    );
    if (choice == null || !choice.apply || !mounted) return;
    try {
      final sync = await applyCaptureToRoom(
        room: room,
        result: result,
        choice: choice,
        projects: AppScope.of(context).projects,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            captureApplySnackBarMessage(result, choice, room, contourSync: sync),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showScanError(
        message: 'Не удалось применить контур: $e',
        onRetry: () => _confirmAndApply(result),
      );
    }
  }

  Future<void> _openPhotoPlan() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PhotoPlanCaptureScreen(
          projectId: widget.projectId,
          roomId: widget.roomId,
        ),
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _startRoomPlan() async {
    setState(() => _busyScan = true);
    try {
      final result = await RoomPlanService.scanRoom();
      if (!mounted) return;
      setState(() => _busyScan = false);
      if (result == null || result.walls.length < 3) {
        _showScanError(
          message: 'Скан отменён или контур не получен.',
          onRetry: _startRoomPlan,
        );
        return;
      }
      await _confirmAndApply(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyScan = false);
      _showScanError(
        message: 'RoomPlan: $e',
        onRetry: _startRoomPlan,
      );
    }
  }

  Future<void> _offerArCorePlayStore({
    required String title,
    required String body,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Позже'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _openEditor();
            },
            child: const Text('Редактор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Play Маркет'),
          ),
        ],
      ),
    );
    if (go == true) {
      await GeometryCaptureChannel.openArCorePlayStore();
    }
  }

  Future<void> _startArCore() async {
    if (_arCore == ArCoreAvailability.unsupported) {
      await _offerArCorePlayStore(
        title: 'AR недоступен',
        body:
            'На этом устройстве ARCore недоступен или не установлен. '
            'Установите «Google Play Services for AR» из Play Маркета. '
            'Фото/PDF плана и ручной редактор работают без AR.',
      );
      return;
    }
    if (_arCore == ArCoreAvailability.supportedNotInstalled ||
        _arCore == ArCoreAvailability.unknown) {
      final status = await GeometryCaptureChannel.ensureArCoreInstalled();
      if (!mounted) return;
      if (status == 'installing') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Установите Google Play Services for AR, затем снова «AR-углы».',
            ),
          ),
        );
        _arCore = await GeometryCaptureChannel.arCoreAvailability();
        setState(() {});
        return;
      }
      if (status.startsWith('error') || status == 'unsupported') {
        await _offerArCorePlayStore(
          title: 'Нужны сервисы AR',
          body:
              'Не удалось подготовить AR ($status). '
              'Откройте Play Маркет или используйте фото/PDF / редактор.',
        );
        return;
      }
      _arCore = ArCoreAvailability.supportedInstalled;
    }

    setState(() => _busyScan = true);
    try {
      final walls = await GeometryCaptureChannel.startArRoomScan();
      if (!mounted) return;
      setState(() => _busyScan = false);
      if (walls == null || walls.length < 3) {
        _showScanError(
          message: 'AR-скан не дал контур. Нужны камера, свет и сервисы AR.',
          onRetry: _startArCore,
        );
        return;
      }
      final result = RoomScanImportResult(
        walls: walls,
        source: 'arcore',
        wallCount: walls.length,
      );
      await _confirmAndApply(result);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _busyScan = false);
      await _offerArCorePlayStore(
        title: 'AR не запустился',
        body:
            '${e.message ?? e.code}\n\n'
            'Установите «Google Play Services for AR» или откройте редактор.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyScan = false);
      _showScanError(
        message: 'AR: $e',
        onRetry: _startArCore,
      );
    }
  }

  Widget _capabilityBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String title;
    String body;
    Color? bg;
    IconData icon;

    if (kIsWeb) {
      title = 'Захват на web недоступен';
      body = 'Откройте Android / iOS сборку или нарисуйте вручную.';
      icon = Icons.block;
      bg = scheme.errorContainer;
    } else if (Platform.isIOS) {
      if (_roomPlanSupported) {
        title = 'LiDAR · RoomPlan готов';
        body = 'Можно сканировать комнату или взять фото/PDF плана.';
        icon = Icons.check_circle_outline;
        bg = scheme.primaryContainer.withValues(alpha: 0.4);
      } else {
        title = 'Нет LiDAR';
        body = 'RoomPlan недоступен. Используйте фото/PDF или редактор.';
        icon = Icons.info_outline;
        bg = scheme.secondaryContainer;
      }
    } else if (Platform.isAndroid) {
      switch (_arCore) {
        case ArCoreAvailability.supportedInstalled:
          title = 'ARCore готов';
          body = 'AR-углы, фото/PDF и ручной редактор доступны.';
          icon = Icons.check_circle_outline;
          bg = scheme.primaryContainer.withValues(alpha: 0.4);
        case ArCoreAvailability.supportedNotInstalled:
          title = 'Нужен Play Services for AR';
          body = 'Установите системный пакет, иначе только фото/PDF / редактор.';
          icon = Icons.download_outlined;
          bg = scheme.tertiaryContainer;
        case ArCoreAvailability.unsupported:
          title = 'ARCore недоступен';
          body = 'Устройство без AR. Фото/PDF плана и редактор работают.';
          icon = Icons.block;
          bg = scheme.secondaryContainer;
        case ArCoreAvailability.unknown:
          title = 'Проверка AR…';
          body = 'При первом запуске предложим установить сервисы.';
          icon = Icons.hourglass_empty;
          bg = scheme.surfaceContainerHighest;
      }
    } else {
      title = 'AR / LiDAR — на телефоне';
      body = 'На ПК: фото/PDF плана или ручной редактор стен.';
      icon = Icons.computer_outlined;
      bg = scheme.surfaceContainerHighest;
    }

    return Card(
      color: bg,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(body),
        isThreeLine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final room = _room;
    final caps = _caps ?? const [];
    final designDiff = room != null && hasDesignWallBaseline(room)
        ? compareWallPolygons(readDesignWalls(room), room.walls)
        : null;
    final scheme = Theme.of(context).colorScheme;

    return ScreenScaffold(
      appBar: AppBar(
        title: Text('Захват · ${room?.name ?? ''}'),
        actions: [
          IconButton(
            tooltip: 'Обновить статус',
            icon: const Icon(Icons.refresh),
            onPressed: _busyScan ? null : _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Контур для отделки: пол, потолок, стены, проёмы. '
                'Повторный захват сравнивает с проектом перед записью.',
              ),
              const SizedBox(height: 12),
              _capabilityBanner(context),
              if (_lastError != null) ...[
                const SizedBox(height: 8),
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.55),
                  child: ListTile(
                    leading: Icon(Icons.error_outline, color: scheme.error),
                    title: const Text('Последняя ошибка'),
                    subtitle: Text(_lastError!),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _lastError = null),
                          child: const Text('Скрыть'),
                        ),
                        TextButton(
                          onPressed: _openEditor,
                          child: const Text('Редактор'),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                ),
              ],
              if (designDiff != null && designDiff.hasSignificantDiff) ...[
                const SizedBox(height: 8),
                Card(
                  color: scheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      formatWallPolygonDiffSummary(designDiff),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Способы', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Фото / PDF плана'),
                  subtitle: Text(
                    kIsWeb || (!Platform.isAndroid && !Platform.isIOS)
                        ? 'Файл JPG/PDF → углы → одна известная стена'
                        : 'Камера или файл → углы → одна известная стена',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busyScan ? null : _openPhotoPlan,
                ),
              ),
              if (Platform.isIOS)
                Card(
                  child: ListTile(
                    enabled: _roomPlanSupported && !_busyScan,
                    leading: Icon(
                      Icons.view_in_ar,
                      color: _roomPlanSupported
                          ? null
                          : Theme.of(context).disabledColor,
                    ),
                    title: const Text('RoomPlan (LiDAR)'),
                    subtitle: Text(
                      _roomPlanSupported
                          ? '3D-обход — контур, высота, проёмы'
                          : 'Нужен iPhone/iPad с LiDAR и iOS 16+',
                    ),
                    trailing: _roomPlanSupported
                        ? const Icon(Icons.chevron_right)
                        : const Icon(Icons.block, size: 20),
                    onTap: _roomPlanSupported && !_busyScan
                        ? _startRoomPlan
                        : null,
                  ),
                ),
              if (Platform.isAndroid)
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.view_in_ar_outlined,
                      color: _arCore == ArCoreAvailability.unsupported
                          ? Theme.of(context).disabledColor
                          : null,
                    ),
                    title: const Text('AR-углы (ARCore)'),
                    subtitle: Text(
                      switch (_arCore) {
                        ArCoreAvailability.supportedInstalled =>
                          'Камера + тап углов на полу',
                        ArCoreAvailability.supportedNotInstalled =>
                          'Нужен Google Play Services for AR',
                        ArCoreAvailability.unsupported =>
                          'Откроет Маркет или подскажет альтернативу',
                        ArCoreAvailability.unknown =>
                          'Проверка… при старте предложим сервисы',
                      },
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busyScan ? null : _startArCore,
                  ),
                ),
              if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS)
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: const ListTile(
                    leading: Icon(Icons.phone_android),
                    title: Text('AR и LiDAR — на телефоне'),
                    subtitle: Text(
                      'RoomPlan (iPhone) и AR-углы (Android) в мобильной '
                      'сборке. Здесь — фото/PDF или редактор.',
                    ),
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Нарисовать вручную'),
                  subtitle: const Text('Редактор стен — 8 направлений'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busyScan ? null : _openEditor,
                ),
              ),
              if (caps.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Статус устройства',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final c in caps)
                  ListTile(
                    dense: true,
                    leading: Icon(_iconFor(c.level), size: 20),
                    title: Text(
                      c.title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      c.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: c.installUrl != null
                        ? IconButton(
                            icon: const Icon(Icons.link, size: 18),
                            tooltip: 'Скопировать ссылку',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: c.installUrl!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Ссылка скопирована'),
                                  ),
                                );
                              }
                            },
                          )
                        : null,
                  ),
              ],
            ],
          ),
          if (_busyScan)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(CapabilityLevel level) => switch (level) {
        CapabilityLevel.supported => Icons.check_circle_outline,
        CapabilityLevel.needsInstall => Icons.download_outlined,
        CapabilityLevel.unsupported => Icons.block,
        CapabilityLevel.wrongPlatform => Icons.devices,
      };
}
