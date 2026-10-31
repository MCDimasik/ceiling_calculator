import 'package:flutter/material.dart';

import '../adaptive_layout.dart';
import '../desktop_cascade.dart';
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
    /// Cap content width on wide/desktop windows.
    this.constrainDesktopWidth = true,
    this.desktopMaxWidth = AdaptiveBreakpoints.contentMaxFhd,
    /// Cascade pane: skip nested photo bg (parent shell already draws it).
    this.embedInParentBackground = false,
    /// When embedded in a wide cascade pane, center a readable column.
    this.embeddedMaxWidth = AdaptiveBreakpoints.paneReadableMax,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool dimBackground;
  final double backgroundBlur;
  final double dimOpacity;
  final bool closeLongPressOnBack;
  final bool constrainDesktopWidth;
  final double desktopMaxWidth;
  final bool embedInParentBackground;
  final double embeddedMaxWidth;

  @override
  Widget build(BuildContext context) {
    // Desktop cascade shell already paints AppBackground once — nest transparent.
    final embed = embedInParentBackground ||
        DesktopCascadeHost.maybeOf(context) != null;

    Widget wrapWidth(Widget child) {
      if (!constrainDesktopWidth ||
          !AdaptiveBreakpoints.useDesktopChrome(context)) {
        return child;
      }
      if (!embed) {
        return AdaptiveContent(maxWidth: desktopMaxWidth, child: child);
      }
      // Narrow mid-pane (projects/rooms ~400px): leave as-is.
      // Wide solo modules (~1600px): center a readable column.
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 560) return child;
          return AdaptiveContent(
            maxWidth: embeddedMaxWidth,
            padding: EdgeInsets.symmetric(
              horizontal: DesktopMetrics.hPad(context) * 0.5,
            ),
            child: child,
          );
        },
      );
    }

    final inner = wrapWidth(body);
    Widget content = embed
        ? Material(
            type: MaterialType.transparency,
            child: inner,
          )
        : AppBackground(
            dim: dimBackground,
            allowVideo: false,
            blurAmount: backgroundBlur,
            dimOpacity: dimOpacity,
            child: Material(
              type: MaterialType.transparency,
              child: inner,
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
