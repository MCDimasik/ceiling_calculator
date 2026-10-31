import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/transfer_activity.dart';

/// Airy bottom overlay: transfer status, swipe sideways to hide.
class TransferProgressBannerHost extends StatelessWidget {
  const TransferProgressBannerHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: false,
            child: _TransferProgressBanner(),
          ),
        ),
      ],
    );
  }
}

class _TransferProgressBanner extends StatefulWidget {
  const _TransferProgressBanner();

  @override
  State<_TransferProgressBanner> createState() =>
      _TransferProgressBannerState();
}

class _TransferProgressBannerState extends State<_TransferProgressBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;
  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _onDismiss(TransferActivityController t) {
    t.dismiss();
    _dragDx = 0;
    _slide.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).transfers;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final show = t.isActive;
        if (!show) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final icon = switch (t.direction) {
          TransferDirection.uploading => Icons.cloud_upload_outlined,
          TransferDirection.downloading => Icons.cloud_download_outlined,
          TransferDirection.bidirectional => Icons.sync_alt,
          TransferDirection.idle => Icons.cloud_outlined,
        };
        final accent = switch (t.direction) {
          TransferDirection.uploading => scheme.tertiary,
          TransferDirection.downloading => scheme.primary,
          TransferDirection.bidirectional => scheme.secondary,
          TransferDirection.idle => scheme.outline,
        };

        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) {
                setState(() => _dragDx += d.delta.dx);
              },
              onHorizontalDragEnd: (d) {
                final w = MediaQuery.sizeOf(context).width;
                final fling = d.primaryVelocity?.abs() ?? 0;
                if (_dragDx.abs() > w * 0.28 || fling > 800) {
                  _onDismiss(t);
                } else {
                  setState(() => _dragDx = 0);
                }
              },
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Transform.translate(
                  offset: Offset(_dragDx, 0),
                  child: Opacity(
                    opacity: (1 - (_dragDx.abs() / 220)).clamp(0.35, 1),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Material(
                            color: scheme.surface.withValues(alpha: 0.72),
                            elevation: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.35),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.16),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(icon, color: accent),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t.directionLabelRu,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: accent,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.3,
                                                  ),
                                            ),
                                            Text(
                                              t.titleRu,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            if (t.detailRu != null &&
                                                t.detailRu!.isNotEmpty)
                                              Text(
                                                t.detailRu!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: scheme.onSurface
                                                          .withValues(
                                                              alpha: 0.65),
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // No tooltip: banner lives in MaterialApp.builder
                                      // outside Navigator Overlay.
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _onDismiss(t),
                                        icon: const Icon(Icons.close, size: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: t.progress,
                                      minHeight: 3.5,
                                      backgroundColor:
                                          accent.withValues(alpha: 0.12),
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Свайп в сторону — скрыть',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.45),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
