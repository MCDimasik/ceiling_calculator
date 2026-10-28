import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'widgets/screen_scaffold.dart';

import 'package:flutter/services.dart';



import '../app_scope.dart';

import '../domain/design_walls_baseline.dart';
import '../domain/finish_design_baseline.dart';
import '../domain/device_capabilities.dart';

import '../domain/geometry_capture_apply.dart';

import '../domain/models.dart';

import '../domain/room_plan_service.dart';

import '../domain/room_scan_import.dart';

import '../domain/finish_model.dart' show AppModule;

import '../domain/wall_polygon_diff.dart';

import '../platform/geometry_capture_channel.dart';

import 'photo_plan_capture_screen.dart';

import 'room_editor_screen.dart';

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

  State<GeometryCaptureHubScreen> createState() => _GeometryCaptureHubScreenState();

}



class _GeometryCaptureHubScreenState extends State<GeometryCaptureHubScreen> {

  Room? _room;

  bool _loading = true;

  bool _roomPlanSupported = false;

  ArCoreAvailability _arCore = ArCoreAvailability.unknown;

  List<FeatureCapability>? _caps;



  @override

  void initState() {

    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());

  }



  Future<void> _load() async {

    final project = await AppScope.of(context).projects.getProject(widget.projectId);

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

    setState(() => _loading = true);

    try {

      final result = await RoomPlanService.scanRoom();

      if (!mounted) return;

      setState(() => _loading = false);

      if (result == null || result.walls.length < 3) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Скан отменён или не удалось получить контур. Повторите съёмку.'),
            action: SnackBarAction(label: 'Повторить', onPressed: _startRoomPlan),
          ),
        );

        return;

      }

      await _confirmAndApply(result);

    } catch (e) {

      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text('RoomPlan: $e')),

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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть Play Маркет'),
          ),
        ],
      ),
    );
    if (go == true) {
      await GeometryCaptureChannel.openArCorePlayStore();
    }
  }

  Future<void> _startArCore() async {
    // Always recoverable: never leave the user on a crash path.
    if (_arCore == ArCoreAvailability.unsupported) {
      await _offerArCorePlayStore(
        title: 'AR недоступен',
        body:
            'На этом устройстве ARCore сейчас недоступен или не установлен. '
            'Установите «Google Play Services for AR» из Play Маркета и повторите. '
            'Движок AR нельзя вшить в наше приложение (требование Google) — '
            'в APK уже есть клиент SDK, нужен только этот системный пакет.',
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
              'Не удалось подготовить AR автоматически ($status). '
              'Откройте Play Маркет и установите «Google Play Services for AR».',
        );
        return;
      }
      _arCore = ArCoreAvailability.supportedInstalled;
    }

    setState(() => _loading = true);
    try {
      final walls = await GeometryCaptureChannel.startArRoomScan();
      if (!mounted) return;
      setState(() => _loading = false);
      if (walls == null || walls.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'AR-скан не дал контур. Нужны камера, освещение и сервисы AR.',
            ),
            action: SnackBarAction(
              label: 'Сервисы AR',
              onPressed: () => GeometryCaptureChannel.openArCorePlayStore(),
            ),
          ),
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
      setState(() => _loading = false);
      await _offerArCorePlayStore(
        title: 'AR не запустился',
        body:
            '${e.message ?? e.code}\n\n'
            'Установите «Google Play Services for AR» и повторите. '
            'Фото/PDF плана работают без AR.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _offerArCorePlayStore(
        title: 'AR не запустился',
        body:
            '$e\n\nОткройте Play Маркет → Google Play Services for AR, '
            'либо используйте фото/PDF плана.',
      );
    }
  }



  @override

  Widget build(BuildContext context) {

    if (_loading) {

      return const ScreenScaffold(body: Center(child: CircularProgressIndicator()));

    }

    final room = _room;

    final caps = _caps ?? const [];

    final designDiff = room != null && hasDesignWallBaseline(room)

        ? compareWallPolygons(readDesignWalls(room), room.walls)

        : null;



    return ScreenScaffold(

      appBar: AppBar(
        title: Text('Захват · ${room?.name ?? ''}'),
      ),

      body: ListView(

        padding: const EdgeInsets.all(16),

        children: [

          const Text(

            'Контур для комплекса отделки: пол, потолок, стены, проёмы, смета. '

            'При повторном захвате — сравнение с проектом.',

          ),

          if (designDiff != null && designDiff.hasSignificantDiff) ...[

            const SizedBox(height: 8),

            Card(

              color: Theme.of(context).colorScheme.secondaryContainer,

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

          Card(

            child: ListTile(

              leading: const Icon(Icons.photo_camera_outlined),

              title: const Text('Фото / PDF плана'),

              subtitle: Text(
                kIsWeb || (!Platform.isAndroid && !Platform.isIOS)
                    ? 'Файл JPG/PDF → углы → одна известная стена (на ПК без камеры)'
                    : 'Камера или файл → углы → одна известная стена',
              ),

              trailing: const Icon(Icons.chevron_right),

              onTap: _openPhotoPlan,

            ),

          ),

          if (Platform.isIOS)

            Card(

              child: ListTile(

                leading: Icon(

                  Icons.view_in_ar,

                  color: _roomPlanSupported ? null : Theme.of(context).disabledColor,

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

                onTap: _roomPlanSupported ? _startRoomPlan : null,

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
                      'Камера + тап углов на полу · сервисы AR установлены',
                    ArCoreAvailability.supportedNotInstalled =>
                      'Нужен пакет Google Play Services for AR (~скачать из Маркета)',
                    ArCoreAvailability.unsupported =>
                      'Нажмите — откроем Play Маркет (Services for AR)',
                    ArCoreAvailability.unknown =>
                      'Проверка AR… при первом запуске предложим сервисы',
                  },
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _startArCore,
              ),
            ),

          if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(
                  Icons.phone_android,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('AR и LiDAR — на телефоне'),
                subtitle: const Text(
                  'RoomPlan (iPhone с LiDAR) и AR-углы (Android с ARCore) '
                  'доступны в мобильной сборке. На Windows/macOS/Linux — '
                  'фото/PDF или ручной редактор.',
                ),
              ),
            ),

          Card(

            child: ListTile(

              leading: const Icon(Icons.edit_outlined),

              title: const Text('Нарисовать вручную'),

              subtitle: const Text('Редактор стен — 8 направлений'),

              onTap: () {

                Navigator.of(context).pushReplacement(

                  MaterialPageRoute(

                    builder: (_) => RoomEditorScreen(

                      projectId: widget.projectId,

                      roomId: widget.roomId,

                      module: widget.module,

                    ),

                  ),

                );

              },

            ),

          ),

          const SizedBox(height: 16),

          Text('Статус устройства', style: Theme.of(context).textTheme.titleSmall),

          const SizedBox(height: 8),

          for (final c in caps)

            ListTile(

              dense: true,

              leading: Icon(_iconFor(c.level), size: 20),

              title: Text(c.title, style: Theme.of(context).textTheme.bodyMedium),

              subtitle: Text(c.message, style: Theme.of(context).textTheme.bodySmall),

              trailing: c.installUrl != null

                  ? IconButton(

                      icon: const Icon(Icons.link, size: 18),

                      tooltip: 'Скопировать ссылку',

                      onPressed: () async {

                        await Clipboard.setData(ClipboardData(text: c.installUrl!));

                        if (context.mounted) {

                          ScaffoldMessenger.of(context).showSnackBar(

                            const SnackBar(content: Text('Ссылка скопирована')),

                          );

                        }

                      },

                    )

                  : null,

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

