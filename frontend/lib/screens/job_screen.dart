import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/agent_terminal.dart';
import '../widgets/job_progress.dart';
import '../widgets/status_badge.dart';
import '../widgets/storyboard_editor.dart';
import '../widgets/video_preview.dart';

class JobScreen extends ConsumerWidget {
  const JobScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobControllerProvider(jobId));
    final terminal = AgentTerminal(jobId: jobId);

    final leftPane = Column(
      children: [
        Expanded(flex: 2, child: terminal),
        const SizedBox(height: 12),
        Expanded(
          flex: 1,
          child: _VideoPane(job: job),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('#${jobId.substring(0, 8)}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusBadge(status: job.status)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: JobProgress(jobId: jobId),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 1100) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _StoryboardPane(job: job),
                        ),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: leftPane),
                      ],
                    ),
                  );
                }
                if (constraints.maxWidth >= 700) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: terminal),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _VideoPane(job: job),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _StoryboardPane(job: job)),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _VideoPane(job: job, height: 320),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 280,
                      child: _StoryboardPane(job: job),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(height: 300, child: terminal),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryboardPane extends ConsumerStatefulWidget {
  const _StoryboardPane({required this.job});

  final JobDetail job;

  @override
  ConsumerState<_StoryboardPane> createState() => _StoryboardPaneState();
}

class _StoryboardPaneState extends ConsumerState<_StoryboardPane> {
  Storyboard? _edited;
  bool _regenerating = false;

  static const Set<String> _editableStatuses = {
    'awaiting_approval',
    'completed',
    'failed',
    'rejected',
  };

  static const Set<String> _terminalStatuses = {
    'completed',
    'failed',
    'rejected',
  };

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final status = job.status;
    final dirtyHint = status == 'awaiting_approval'
        ? 'Edits and scene order are applied when you approve'
        : 'Edits and scene order are applied when you regenerate';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == 'awaiting_approval')
          _ApproveCard(job: job, storyboard: _edited),
        if (_terminalStatuses.contains(status) && job.storyboard != null)
          _RegenerateCard(
            job: job,
            busy: _regenerating,
            onPressed: _regenerate,
          ),
        Expanded(
          child: StoryboardEditor(
            jobId: job.jobId,
            storyboard: job.storyboard,
            enabled: _editableStatuses.contains(status),
            dirtyHint: dirtyHint,
            onStoryboardChanged: (board) => setState(() => _edited = board),
          ),
        ),
      ],
    );
  }

  Future<void> _regenerate() async {
    final board = _edited ?? widget.job.storyboard;
    if (board == null) {
      return;
    }
    setState(() => _regenerating = true);
    try {
      await ref.read(repositoryProvider).regenerate(widget.job.jobId, board);
      if (mounted) {
        // Remount the screen so fresh SSE/polling providers pick up the
        // new run (the previous stream ended at job_done and won't restart).
        context.pushReplacement('/jobs/${widget.job.jobId}');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Regenerate failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _regenerating = false);
      }
    }
  }
}

class _RegenerateCard extends StatelessWidget {
  const _RegenerateCard({
    required this.job,
    required this.busy,
    required this.onPressed,
  });

  final JobDetail job;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.teal.withValues(alpha: 0.10),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Job finished - edit the storyboard or reorder scenes, then regenerate',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : onPressed,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Regenerate scenes & video'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPane extends ConsumerWidget {
  const _VideoPane({required this.job, this.height});

  final JobDetail job;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = job.videoUrl;
    return VideoPreview(
      url: url == null ? null : ref.read(repositoryProvider).resolveUrl(url),
      height: height ?? 260,
      hint: job.status == 'awaiting_approval'
          ? 'Video renders after approval'
          : 'Rendering in progress...',
    );
  }
}

class _ApproveCard extends ConsumerStatefulWidget {
  const _ApproveCard({required this.job, this.storyboard});

  final JobDetail job;
  final Storyboard? storyboard;

  @override
  ConsumerState<_ApproveCard> createState() => _ApproveCardState();
}

class _ApproveCardState extends ConsumerState<_ApproveCard> {
  final TextEditingController _feedbackController = TextEditingController();
  bool _busy = false;
  String? _sent;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approved) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).approve(
            widget.job.jobId,
            approved: approved,
            feedback: _feedbackController.text.trim(),
            storyboard: widget.storyboard,
          );
      setState(() => _sent = approved ? 'Approval sent...' : 'Rejected');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approve failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orangeAccent.withValues(alpha: 0.12),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Storyboard awaiting your approval',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _feedbackController,
              enabled: !_busy,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Feedback for edits (optional)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _decide(true),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide(false),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
            if (_sent != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(_sent!, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
