import 'package:flutter/material.dart';

/// Tap to rotate floor layout by +90°. Optional reset to 0°.
class FloorRotateControl extends StatelessWidget {
  const FloorRotateControl({
    super.key,
    required this.rotationDeg,
    required this.onRotationChanged,
    required this.onPersist,
    this.onReset,
  });

  final int rotationDeg;
  final ValueChanged<int> onRotationChanged;
  final VoidCallback onPersist;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final showReset = rotationDeg != 0 && onReset != null;

    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !showReset,
              child: Opacity(
                opacity: showReset ? 1 : 0,
                child: Material(
                  color: const Color(0xFF2A3848).withValues(alpha: 0.92),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      onReset!();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                      child: Text(
                        '0°',
                        style: TextStyle(
                          color: Color(0xFFFFC857),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: const Color(0xFF2A3848).withValues(alpha: 0.92),
              elevation: 2,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  final next = (rotationDeg + 90) % 360;
                  onRotationChanged(next);
                  onPersist();
                },
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.rotate_90_degrees_cw,
                    size: 20,
                    color: Color(0xFFFFC857),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
