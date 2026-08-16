import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  static Color colorFor(String status) {
    switch (status) {
      case 'pending':
        return Colors.amber;
      case 'running':
      case 'storyboard_planned':
      case 'prompts_generated':
      case 'corrected':
      case 'quality_checked':
      case 'assets_ready':
      case 'skipped_hitl':
      case 'approved':
        return Colors.lightBlueAccent;
      case 'awaiting_approval':
        return Colors.orangeAccent;
      case 'completed':
        return Colors.greenAccent;
      case 'failed':
        return Colors.redAccent;
      case 'rejected':
        return Colors.pinkAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.replaceAll('_', ' '),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
