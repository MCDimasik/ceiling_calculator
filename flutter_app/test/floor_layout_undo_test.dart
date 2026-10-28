import 'package:flutter_test/flutter_test.dart';

import 'package:ceiling_calculator/domain/floor_layout_undo.dart';

void main() {
  test('undo stack tracks rotation changes', () {
    final stack = FloorLayoutUndoStack();
    stack.seed(const FloorLayoutUndoSnapshot(offsetX: 0, offsetY: 0, rotationDeg: 0));
    stack.push(const FloorLayoutUndoSnapshot(offsetX: 0, offsetY: 0, rotationDeg: 90));
    stack.push(const FloorLayoutUndoSnapshot(offsetX: 5, offsetY: 0, rotationDeg: 90));

    expect(stack.canUndo, isTrue);
    expect(stack.undo()?.rotationDeg, 90);
    expect(stack.undo()?.rotationDeg, 0);
    expect(stack.canUndo, isFalse);

    expect(stack.redo()?.rotationDeg, 90);
    expect(stack.redo()?.offsetX, 5);
  });

  test('push skips duplicate snapshots', () {
    final stack = FloorLayoutUndoStack();
    stack.seed(const FloorLayoutUndoSnapshot(offsetX: 1, offsetY: 2, rotationDeg: 0));
    stack.push(const FloorLayoutUndoSnapshot(offsetX: 1, offsetY: 2, rotationDeg: 0));
    expect(stack.canUndo, isFalse);
  });

  test('formatFloorLayoutUndoLabel includes rotation', () {
    expect(
      formatFloorLayoutUndoLabel(
        const FloorLayoutUndoSnapshot(offsetX: 10, offsetY: 20, rotationDeg: 90),
      ),
      '10×20 см · 90°',
    );
  });
}
