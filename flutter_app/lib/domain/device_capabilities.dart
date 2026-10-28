import 'dart:io';



import 'package:flutter/foundation.dart';



import '../platform/geometry_capture_channel.dart';

import 'room_plan_service.dart';



/// Device readiness for geometry capture modules.

enum GeometryCaptureFeature {

  photoPlan,

  arCoreRoom,

  iosRoomPlan,

}



enum CapabilityLevel { supported, needsInstall, unsupported, wrongPlatform }



class FeatureCapability {

  const FeatureCapability({

    required this.feature,

    required this.level,

    required this.title,

    required this.message,

    this.installUrl,

  });



  final GeometryCaptureFeature feature;

  final CapabilityLevel level;

  final String title;

  final String message;

  final String? installUrl;

}



class DeviceCapabilities {

  static const arCorePlayStore =

      'https://play.google.com/store/apps/details?id=com.google.ar.core';



  static Future<List<FeatureCapability>> geometryCaptureReport() async {

    if (kIsWeb) {

      return [

        const FeatureCapability(

          feature: GeometryCaptureFeature.photoPlan,

          level: CapabilityLevel.unsupported,

          title: 'Фото плана',

          message: 'На web захват недоступен — используйте Android или iOS.',

        ),

        const FeatureCapability(

          feature: GeometryCaptureFeature.arCoreRoom,

          level: CapabilityLevel.wrongPlatform,

          title: 'AR-обход',

          message: 'Только мобильное приложение.',

        ),

      ];

    }



    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {

      return [

        const FeatureCapability(

          feature: GeometryCaptureFeature.photoPlan,

          level: CapabilityLevel.supported,

          title: 'Фото / PDF плана',

          message: 'Загрузите JPG/PNG/PDF, отметьте углы и одну известную стену.',

        ),

        const FeatureCapability(

          feature: GeometryCaptureFeature.arCoreRoom,

          level: CapabilityLevel.wrongPlatform,

          title: 'RoomPlan / ARCore',

          message: '3D-скан только на iPhone с LiDAR или Android с ARCore.',

        ),

      ];

    }



    if (Platform.isIOS) {

      final roomPlan = await RoomPlanService.isSupported();

      return [

        const FeatureCapability(

          feature: GeometryCaptureFeature.photoPlan,

          level: CapabilityLevel.supported,

          title: 'Фото / PDF плана',

          message: 'Камера или галерея → углы → одна известная длина стены.',

        ),

        FeatureCapability(

          feature: GeometryCaptureFeature.iosRoomPlan,

          level: roomPlan ? CapabilityLevel.supported : CapabilityLevel.unsupported,

          title: 'RoomPlan (LiDAR)',

          message: roomPlan

              ? '3D-обход — автоматический контур и высота потолка.'

              : 'Нужен iPhone/iPad Pro с LiDAR и iOS 16+.',

        ),

      ];

    }



    if (Platform.isAndroid) {

      final sdk = await _androidSdkInt();

      final arCore = await GeometryCaptureChannel.isArCoreAvailable();

      final lowRam = sdk != null && sdk < 26;

      return [

        FeatureCapability(

          feature: GeometryCaptureFeature.photoPlan,

          level: CapabilityLevel.supported,

          title: 'Фото / PDF плана',

          message: lowRam

              ? 'Камера и файлы. На слабых устройствах обработка может занять дольше.'

              : 'Камера или файл → углы → одна известная длина.',

        ),

        FeatureCapability(

          feature: GeometryCaptureFeature.arCoreRoom,

          level: arCore

              ? CapabilityLevel.supported

              : (sdk != null && sdk >= 24

                  ? CapabilityLevel.needsInstall

                  : CapabilityLevel.unsupported),

          title: 'AR-углы (ARCore)',
          message: arCore
              ? 'Тапайте углы пола в AR — контур помещения.'
              : sdk != null && sdk >= 24
                  ? 'Установите Google Play Services for AR, если устройство поддерживается.'
                  : 'Нужен Android 7.0+ для ARCore.',

          installUrl: !arCore && sdk != null && sdk >= 24 ? arCorePlayStore : null,

        ),

      ];

    }



    return const [];

  }



  static Future<int?> _androidSdkInt() async {

    if (!Platform.isAndroid) return null;

    try {

      final match = RegExp(r'API (\d+)').firstMatch(Platform.operatingSystemVersion);

      if (match != null) return int.tryParse(match.group(1)!);

    } catch (_) {}

    return 28;

  }

}

