import 'package:flutter/foundation.dart';

enum TransferDirection {
  idle,
  uploading,
  downloading,
  bidirectional,
}

/// Global floating banner state for sync / OTA / share transfers.
class TransferActivityController extends ChangeNotifier {
  TransferDirection direction = TransferDirection.idle;
  String titleRu = '';
  String? detailRu;

  /// 0…1 when known; null = indeterminate.
  double? progress;
  bool dismissed = false;
  var _seq = 0;

  bool get isActive => direction != TransferDirection.idle && !dismissed;

  String get directionLabelRu => switch (direction) {
        TransferDirection.uploading => 'Исходящая',
        TransferDirection.downloading => 'Входящая',
        TransferDirection.bidirectional => 'Обмен',
        TransferDirection.idle => '',
      };

  /// Start or refresh a transfer card. Resets swipe-dismiss.
  int begin({
    required TransferDirection direction,
    required String titleRu,
    String? detailRu,
    double? progress,
  }) {
    this.direction = direction;
    this.titleRu = titleRu;
    this.detailRu = detailRu;
    this.progress = progress;
    dismissed = false;
    _seq++;
    notifyListeners();
    return _seq;
  }

  void update({
    int? token,
    TransferDirection? direction,
    String? titleRu,
    String? detailRu,
    double? progress,
  }) {
    if (token != null && token != _seq) return;
    if (direction != null) this.direction = direction;
    if (titleRu != null) this.titleRu = titleRu;
    if (detailRu != null) this.detailRu = detailRu;
    if (progress != null) this.progress = progress;
    notifyListeners();
  }

  void setProgress(double? value, {int? token}) {
    if (token != null && token != _seq) return;
    progress = value;
    notifyListeners();
  }

  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    notifyListeners();
  }

  void end({int? token}) {
    if (token != null && token != _seq) return;
    direction = TransferDirection.idle;
    titleRu = '';
    detailRu = null;
    progress = null;
    dismissed = false;
    notifyListeners();
  }
}
