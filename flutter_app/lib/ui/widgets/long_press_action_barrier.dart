import 'package:flutter/foundation.dart';

/// Tracks an open [LongPressActionTile] overlay so system/app back closes it first.
class LongPressActionBarrier extends ChangeNotifier {
  LongPressActionBarrier._();

  static final instance = LongPressActionBarrier._();

  Object? _openToken;

  bool get hasOpen => _openToken != null;

  void registerOpen(Object token) {
    _openToken = token;
    notifyListeners();
  }

  void registerClosed(Object token) {
    if (_openToken == token) {
      _openToken = null;
      notifyListeners();
    }
  }

  bool tryClose() {
    if (_openToken == null) return false;
    final callback = _closeCallbacks[_openToken];
    callback?.call();
    return callback != null;
  }

  final _closeCallbacks = <Object, VoidCallback>{};

  void bindClose(Object token, VoidCallback close) {
    _closeCallbacks[token] = close;
  }

  void unbindClose(Object token) {
    _closeCallbacks.remove(token);
    registerClosed(token);
  }
}
