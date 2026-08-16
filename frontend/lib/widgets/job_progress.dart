import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class JobProgress extends ConsumerWidget {
  const JobProgress({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(jobProgressProvider(jobId));
    final theme = Theme.of(context);
    final percent = progress.progress;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.message,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (percent != null)
                  Text(
                    '${(percent * 100).round()}%',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (var i = 0; i < progressStepLabels.length; i++)
                  _StepChip(
                    label: progressStepLabels[i],
                    done: progress.done[i],
                    active: progress.activeStep == i,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    final Widget icon;
    if (done) {
      color = Colors.greenAccent;
      icon = const Icon(Icons.check_circle, size: 14, color: Colors.greenAccent);
    } else if (active) {
      color = theme.colorScheme.primary;
      icon = const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      color = theme.disabledColor;
      icon = Icon(Icons.circle_outlined, size: 14, color: theme.disabledColor);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: active || done ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
