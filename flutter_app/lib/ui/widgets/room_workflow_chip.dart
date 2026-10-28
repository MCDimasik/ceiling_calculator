import 'package:flutter/material.dart';

import '../../domain/room_documentation_status.dart';

/// Compact workflow badge: Не начато / В работе / Сдан.
class RoomWorkflowChip extends StatelessWidget {
  const RoomWorkflowChip({super.key, required this.status});

  final RoomWorkflowStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RoomWorkflowStatus.handedOver => Colors.green.shade700,
      RoomWorkflowStatus.inProgress => Colors.orange.shade800,
      RoomWorkflowStatus.notStarted => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.labelRu,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
