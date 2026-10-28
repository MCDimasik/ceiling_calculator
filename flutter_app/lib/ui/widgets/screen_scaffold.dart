import 'package:flutter/material.dart';

import 'app_background.dart';
import 'long_press_action_barrier.dart';

/// Scaffold with themed photo background (Kivy list-screen parity).
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.dimBackground = true,
    /// Soft background blur 0…1 (pre-rendered cache, not live GPU filter).
    /// Default matches finish screens (0.5).
    this.backgroundBlur = 0.5,
    /// Dim overlay strength when [dimBackground] is true.
    this.dimOpacity = 0.45,
    this.closeLongPressOnBack = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool dimBackground;
  final double backgroundBlur;
  final double dimOpacity;
  final bool closeLongPressOnBack;

  @override
  Widget build(BuildContext context) {
    Widget content = AppBackground(
      dim: dimBackground,
      allowVideo: false,
      blurAmount: backgroundBlur,
      dimOpacity: dimOpacity,
      child: Material(
        type: MaterialType.transparency,
        child: body,
      ),
    );

    if (closeLongPressOnBack) {
      content = ListenableBuilder(
        listenable: LongPressActionBarrier.instance,
        builder: (context, child) => PopScope(
          canPop: !LongPressActionBarrier.instance.hasOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) LongPressActionBarrier.instance.tryClose();
          },
          child: child!,
        ),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: content,
    );
  }
}
