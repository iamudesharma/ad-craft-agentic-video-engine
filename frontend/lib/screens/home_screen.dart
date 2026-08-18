import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../widgets/brand_guidelines_form.dart';
import '../widgets/status_badge.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _promptController = TextEditingController();
  final _brandFormKey = GlobalKey<BrandGuidelinesFormState>();
  String _aspectRatio = '9:16';
  bool _hitlEnabled = true;
  bool _busy = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showError('Enter a creative brief first');
      return;
    }
    setState(() => _busy = true);
    try {
      final jobId = await ref.read(repositoryProvider).generate(
            prompt: prompt,
            brandGuidelines: _brandFormKey.currentState?.value,
            aspectRatio: _aspectRatio,
            hitlEnabled: _hitlEnabled,
          );
      if (mounted) {
        _promptController.clear();
        context.push('/jobs/$jobId');
      }
    } catch (error) {
      _showError('Generate failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final org = ref.watch(authControllerProvider).org;
    return Scaffold(
      appBar: AppBar(
        title: Text(org == null ? 'Ad Craft' : 'Ad Craft - ${org.name}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'org') {
                context.push('/org');
              } else if (value == 'logout') {
                ref.read(authControllerProvider.notifier).logout();
              }
            },
            itemBuilder: (context) => [
              if (org != null)
                const PopupMenuItem(value: 'org', child: Text('Organization settings')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final form = _buildForm(context);
          final list = _buildJobList(context);
          if (wide) {
            return Row(
              children: [
                SizedBox(width: 400, child: form),
                const VerticalDivider(width: 1),
                Expanded(child: list),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [form, const SizedBox(height: 16), list],
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Create a video ad',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        TextField(
          controller: _promptController,
          enabled: !_busy,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Creative brief',
            hintText: 'e.g. A moody craft coffee ad for Instagram...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        BrandGuidelinesForm(
          key: _brandFormKey,
          enabled: !_busy,
          initial: ref.watch(authControllerProvider).org?.brandGuidelines,
          title: 'Brand guidelines for this ad',
          subtitle: 'Pre-filled from your organization - change per ad if needed',
        ),
        const SizedBox(height: 16),
        const Text('Aspect ratio', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '9:16', label: Text('9:16')),
            ButtonSegment(value: '16:9', label: Text('16:9')),
            ButtonSegment(value: '1:1', label: Text('1:1')),
          ],
          selected: {_aspectRatio},
          onSelectionChanged: _busy
              ? null
              : (selection) => setState(() => _aspectRatio = selection.first),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Human approval before render'),
          value: _hitlEnabled,
          onChanged: _busy ? null : (value) => setState(() => _hitlEnabled = value),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: const Text('Generate ad'),
        ),
      ],
    );
  }

  Widget _buildJobList(BuildContext context) {
    final state = ref.watch(jobListControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Jobs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Cannot reach backend at the configured API base URL.\n${state.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : state.items.isEmpty
                      ? const Center(child: Text('No jobs yet - generate one'))
                      : ListView.separated(
                          itemCount: state.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final job = state.items[index];
                            return ListTile(
                              leading: StatusBadge(status: job.status),
                              title: Text('#${job.jobId.substring(0, 8)}'),
                              subtitle: Text(
                                '${job.aspectRatio}  |  ${job.createdAt.toLocal()}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/jobs/${job.jobId}'),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
