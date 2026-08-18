import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import 'status_badge.dart';

String relativeTime(DateTime dt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.month}/${dt.day}/${dt.year}';
}

String _statusLabel(String status) => switch (status) {
      'pending' => 'Pending',
      'running' => 'Running',
      'awaiting_approval' => 'Awaiting',
      'completed' => 'Completed',
      'failed' => 'Failed',
      'rejected' => 'Rejected',
      _ => status,
    };

class JobListSection extends ConsumerStatefulWidget {
  const JobListSection({super.key});

  @override
  ConsumerState<JobListSection> createState() => _JobListSectionState();
}

class _JobListSectionState extends ConsumerState<JobListSection> {
  static const List<String> _statuses = [
    'pending',
    'running',
    'awaiting_approval',
    'completed',
    'failed',
    'rejected',
  ];
  static const List<String> _aspectRatios = ['9:16', '16:9', '1:1'];

  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref
          .read(jobListControllerProvider.notifier)
          .applyFilters(query: value.trim());
    });
  }

  Future<void> _duplicate(JobSummary job, String mode) async {
    try {
      final newId = await ref.read(repositoryProvider).duplicate(job.jobId, mode);
      if (mounted) {
        context.push('/jobs/$newId');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Duplicate failed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jobListControllerProvider);
    final notifier = ref.read(jobListControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Jobs', style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search jobs by brief...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_statusLabel(s)),
                    selected: state.statusFilter == s,
                    onSelected: (_) => notifier.applyFilters(
                      status: state.statusFilter == s ? null : s,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final r in _aspectRatios)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(r),
                    selected: state.aspectFilter == r,
                    onSelected: (_) => notifier.applyFilters(
                      aspect: state.aspectFilter == r ? null : r,
                    ),
                  ),
                ),
              FilterChip(
                label: const Text('Favorites'),
                selected: state.favoritesOnly,
                onSelected: (v) =>
                    notifier.applyFilters(favoritesOnly: v),
              ),
            ],
          ),
        ),
        Expanded(child: _buildList(state, notifier)),
      ],
    );
  }

  Widget _buildList(JobListState state, JobListController notifier) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Cannot load jobs.\n${state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state.items.isEmpty) {
      final message = state.hasActiveFilters
          ? 'No jobs match your filters'
          : 'No jobs yet - generate one';
      return Center(child: Text(message));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          notifier.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return _JobRow(job: state.items[index], onDuplicate: _duplicate);
        },
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job, required this.onDuplicate});

  final JobSummary job;
  final void Function(JobSummary job, String mode) onDuplicate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title =
        job.title.isNotEmpty ? job.title : '#${job.jobId.substring(0, 8)}';
    final brief = job.prompt.isNotEmpty ? job.prompt : '';
    final subtitle = brief.isEmpty
        ? '${job.aspectRatio}  |  ${relativeTime(job.createdAt)}'
        : '${job.aspectRatio}  |  $brief  |  ${relativeTime(job.createdAt)}';
    return ListTile(
      leading: IconButton(
        icon: Icon(
          job.favorite ? Icons.star : Icons.star_border,
          color: job.favorite ? Colors.amber : null,
        ),
        tooltip: job.favorite ? 'Remove favorite' : 'Add favorite',
        onPressed: () =>
            ref.read(jobListControllerProvider.notifier).toggleFavorite(job.jobId),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(status: job.status),
        ],
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        tooltip: 'More options',
        onSelected: (value) {
          if (value == 'brief' || value == 'storyboard') {
            onDuplicate(job, value);
          } else if (value == 'open') {
            context.push('/jobs/${job.jobId}');
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'open', child: Text('Open')),
          const PopupMenuItem(value: 'brief', child: Text('New from brief')),
          if (job.hasStoryboard)
            const PopupMenuItem(value: 'storyboard', child: Text('Clone storyboard')),
        ],
      ),
      onTap: () => context.push('/jobs/${job.jobId}'),
    );
  }
}
