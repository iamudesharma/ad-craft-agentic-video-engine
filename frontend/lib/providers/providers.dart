import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/config.dart';
import '../core/sse/sse_client.dart';
import '../core/sse/sse_parser.dart';
import '../models/models.dart';

final dioProvider = Provider<Dio>((ref) => Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 60),
      ),
    ));

final repositoryProvider = Provider<ApiRepository>(
  (ref) => ApiRepository(ref.watch(dioProvider)),
);

final sseStreamProvider = StreamProvider.autoDispose
    .family<ServerEvent, String>((ref, jobId) async* {
  final client = SseClient.create();
  ref.onDispose(client.stop);
  await client.connect(Uri.parse('$apiBaseUrl/api/v1/jobs/$jobId/stream'));
  yield* client.stream;
});

final jobListProvider = StreamProvider.autoDispose<List<JobSummary>>((ref) async* {
  final repository = ref.watch(repositoryProvider);
  while (true) {
    yield await repository.listJobs();
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});

class JobController extends AutoDisposeFamilyNotifier<JobDetail, String> {
  Timer? _pollTimer;
  late String _jobId;

  @override
  JobDetail build(String jobId) {
    _jobId = jobId;
    ref.onDispose(() => _pollTimer?.cancel());
    _fetch();
    _startPolling();
    ref.listen(sseStreamProvider(jobId), (previous, next) {
      next.whenData(_applyEvent);
    });
    return JobDetail.initial(jobId);
  }

  Future<void> _fetch() async {
    try {
      state = await ref.read(repositoryProvider).getJob(_jobId);
    } catch (error) {
      // Job missing or backend unreachable: surface it instead of staying
      // "pending" forever. The next poll overwrites this once it recovers.
      if (state.status == 'pending') {
        state = state.copyWith(status: 'unknown', error: '$error');
      }
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (state.isTerminal) {
        _pollTimer?.cancel();
        return;
      }
      await _fetch();
    });
  }

  void _applyEvent(ServerEvent event) {
    final payload = event.json;
    if (payload == null) {
      return;
    }
    Storyboard? board;
    if (payload['storyboard'] is Map<String, dynamic>) {
      board = Storyboard.fromJson(payload['storyboard'] as Map<String, dynamic>);
    }
    switch (event.type) {
      case 'storyboard_produced':
        if (board != null) state = state.copyWith(storyboard: board);
        break;
      case 'storyboard_updated':
        if (board != null) state = state.copyWith(storyboard: board);
        break;
      case 'hitl_pending':
        if (board != null) {
          state = state.copyWith(status: 'awaiting_approval', storyboard: board);
        }
        break;
      case 'approval_received':
        state = state.copyWith(status: 'running');
        break;
      case 'job_completed':
        final videoPath = payload['video_path'] as String?;
        state = state.copyWith(
          status: 'completed',
          storyboard: board,
          videoUrl: videoPath == null ? state.videoUrl : '/api/v1/jobs/${state.jobId}/video',
        );
        break;
      case 'job_failed':
        state = state.copyWith(
          status: 'failed',
          error: payload['error'] as String? ?? 'Unknown error',
        );
        break;
      case 'job_rejected':
        state = state.copyWith(
          status: 'rejected',
          error: payload['error'] as String? ?? 'Rejected',
        );
        break;
    }
  }
}

final jobControllerProvider = NotifierProvider.autoDispose
    .family<JobController, JobDetail, String>(JobController.new);

class AgentTerminalState {
  const AgentTerminalState({this.lines = const [], this.stage});

  final List<String> lines;
  final String? stage;
}

class AgentTerminalController
    extends AutoDisposeFamilyNotifier<AgentTerminalState, String> {
  static const int _maxLines = 500;

  @override
  AgentTerminalState build(String jobId) {
    ref.listen(sseStreamProvider(jobId), (previous, next) {
      next.whenData(_applyEvent);
      if (next.hasError) {
        _add('-- stream error: ${next.error} --');
      }
      if (previous != null &&
          (previous.hasError || previous.isLoading) &&
          next.hasValue) {
        _add('-- reconnected --');
      }
    });
    return const AgentTerminalState(lines: ['-- connecting to agent stream --']);
  }

  void _applyEvent(ServerEvent event) {
    final payload = event.json;
    switch (event.type) {
      case 'connected':
        _add('-- connected --');
      case 'node_started':
        _stage(payload?['node'] as String?);
        _add('>> ${payload?['node'] ?? 'node'}');
      case 'node_completed':
        _add('   ${payload?['node'] ?? 'node'} done');
        _stage(null);
      case 'token':
        _append(payload?['content'] as String? ?? '');
      case 'storyboard_produced':
        final scenes = (payload?['storyboard'] as Map<String, dynamic>?)?['scenes'];
        _add('storyboard produced (${scenes is List ? scenes.length : '?'} scenes)');
      case 'storyboard_updated':
        _add('storyboard updated from your edits');
      case 'prompts_optimized':
        _add('visual prompts optimized');
      case 'hitl_pending':
        _add('(paused) awaiting your approval');
      case 'approval_received':
        _add('-> ${payload?['decision'] ?? 'decision'}');
      case 'qc_report':
        final passed = payload?['report'] is Map
            ? (payload?['report'] as Map)['passed'] == true
            : null;
        _add(passed == true
            ? 'quality check: passed'
            : 'quality check: issues found');
      case 'qc_corrected':
        _add('storyboard auto-corrected');
      case 'asset_progress':
        _add('assets ${payload?['done']}/${payload?['total']} (${payload?['current']})');
      case 'render_progress':
        _add('render ${payload?['done']}/${payload?['total']} (${payload?['current']})');
      case 'video_rendered':
        _add('video rendered');
      case 'job_completed':
        _add('-- job completed --');
      case 'job_failed':
        _add('-- job failed: ${payload?['error'] ?? 'unknown error'}');
      case 'job_rejected':
        _add('-- job rejected: ${payload?['error'] ?? 'no feedback'}');
      case 'job_done':
        _add('-- stream closed --');
    }
  }

  void _add(String line) {
    final lines = [...state.lines, line];
    if (lines.length > _maxLines) {
      lines.removeRange(0, lines.length - _maxLines);
    }
    state = AgentTerminalState(lines: lines, stage: state.stage);
  }

  void _append(String text) {
    if (text.isEmpty) {
      return;
    }
    var lines = [...state.lines];
    var last = lines.isEmpty ? '' : lines.removeLast();
    last += text;
    final parts = <String>[];
    while (last.length > 3000) {
      parts.add(last.substring(0, 3000));
      last = last.substring(3000);
    }
    if (last.isNotEmpty) {
      parts.add(last);
    }
    lines.addAll(parts);
    if (lines.length > _maxLines) {
      lines.removeRange(0, lines.length - _maxLines);
    }
    state = AgentTerminalState(lines: lines, stage: state.stage);
  }

  void _stage(String? stage) {
    state = AgentTerminalState(lines: state.lines, stage: stage);
  }
}

final agentTerminalProvider = NotifierProvider.autoDispose
    .family<AgentTerminalController, AgentTerminalState, String>(
        AgentTerminalController.new);

const List<String> progressStepLabels = [
  'Storyboard',
  'Prompts',
  'Approval',
  'Quality',
  'Assets',
  'Render',
  'Done',
];

class JobProgressState {
  const JobProgressState({
    required this.done,
    required this.activeStep,
    required this.message,
    this.progress,
  });

  final List<bool> done;
  final int activeStep;
  final String message;
  final double? progress;
}

class JobProgressController
    extends AutoDisposeFamilyNotifier<JobProgressState, String> {
  static const List<bool> _kNoneDone = [false, false, false, false, false, false, false];
  static const List<bool> _kAllDone = [true, true, true, true, true, true, true];
  static const List<bool> _kUntilApproval = [true, true, false, false, false, false, false];
  static const JobProgressState _queued = JobProgressState(
    done: _kNoneDone,
    activeStep: -1,
    message: 'Queued...',
  );

  /// Last state reported by the live SSE stream. Kept in a plain field (not
  /// via `state`) so that `_deriveFromJob` never reads `state`, which Riverpod
  /// does not allow before the first build has completed ("Tried to read the
  /// state of an uninitialized provider").
  JobProgressState? _live;

  @override
  JobProgressState build(String jobId) {
    ref.listen(jobControllerProvider(jobId), (previous, next) {
      state = _deriveFromJob(next);
    });
    ref.listen(sseStreamProvider(jobId), (previous, next) {
      next.whenData(_applyEvent);
    });
    return _deriveFromJob(ref.watch(jobControllerProvider(jobId)));
  }

  /// Derives the stepper from the job's API status. SSE events refine the
  /// state while a job is running; terminal/paused statuses resolve instantly
  /// even when no live events are available (e.g. reopening a finished job or
  /// after a backend restart).
  JobProgressState _deriveFromJob(JobDetail job) {
    final live = _live;
    switch (job.status) {
      case 'completed':
        return const JobProgressState(
          done: _kAllDone,
          activeStep: -1,
          message: 'Completed',
          progress: 1.0,
        );
      case 'failed':
        return JobProgressState(
          done: live?.done ?? _kNoneDone,
          activeStep: -1,
          message: 'Failed: ${job.error ?? 'unknown error'}',
          progress: 1.0,
        );
      case 'rejected':
        return JobProgressState(
          done: live?.done ?? _kNoneDone,
          activeStep: -1,
          message: 'Rejected: ${job.error ?? 'no feedback'}',
          progress: 1.0,
        );
      case 'awaiting_approval':
        return const JobProgressState(
          done: _kUntilApproval,
          activeStep: 2,
          message: 'Awaiting your approval',
        );
      case 'pending':
        return _queued;
      case 'running':
        // Keep whatever the live SSE events reported; only fall back to a
        // generic "Running..." when no progress detail is known yet.
        if (live == null || live.message == 'Queued...' || live.message.isEmpty) {
          return const JobProgressState(
            done: _kNoneDone,
            activeStep: -1,
            message: 'Running...',
          );
        }
        return live;
      default:
        return live ?? _queued;
    }
  }

  void _applyEvent(ServerEvent event) {
    final payload = event.json;
    switch (event.type) {
      case 'node_started':
        final node = payload?['node'] as String?;
        switch (node) {
          case 'planner':
            _set(0, 'Planning storyboard...');
          case 'prompt_engine':
            _set(1, 'Optimizing visual prompts...');
          case 'quality_checker':
            _set(3, 'Checking scene quality...');
          case 'ingest_assets':
            _set(4, 'Fetching scene assets...');
          case 'render_video':
            _set(5, 'Rendering scenes...');
        }
        break;
      case 'node_completed':
        final node = payload?['node'] as String?;
        switch (node) {
          case 'planner':
            _done(0);
          case 'prompt_engine':
            _done(1);
          case 'quality_checker':
            _done(3);
          case 'ingest_assets':
            _done(4);
          case 'render_video':
            _done(5);
        }
        break;
      case 'hitl_pending':
        _set(2, 'Awaiting your approval');
        break;
      case 'approval_received':
        _done(2);
        _message('Approved - starting production');
        break;
      case 'asset_progress':
        final d = (payload?['done'] as num?)?.toInt() ?? 0;
        final t = (payload?['total'] as num?)?.toInt() ?? 1;
        _progress(d / t, 'Fetching scene assets $d/$t');
        break;
      case 'render_progress':
        final d = (payload?['done'] as num?)?.toInt() ?? 0;
        final t = (payload?['total'] as num?)?.toInt() ?? 1;
        _progress(d / t, 'Rendering scenes $d/$t');
        break;
      case 'video_rendered':
        _done(5);
        _message('Finalizing video...');
        break;
      case 'job_completed':
        _allDone('Completed');
        break;
      case 'job_failed':
        _error('Failed: ${payload?['error'] ?? 'unknown error'}');
        break;
      case 'job_rejected':
        _error('Rejected: ${payload?['error'] ?? 'no feedback'}');
        break;
    }
  }

  void _set(int step, String message) {
    final done = [...(_live?.done ?? _kNoneDone)];
    for (var i = 0; i < step; i++) {
      done[i] = true;
    }
    _emit(JobProgressState(done: done, activeStep: step, message: message));
  }

  void _done(int step) {
    final prev = _live ?? _queued;
    final done = [...prev.done];
    done[step] = true;
    _emit(JobProgressState(done: done, activeStep: -1, message: prev.message));
  }

  void _progress(double value, String message) {
    final prev = _live ?? _queued;
    _emit(JobProgressState(
      done: [...prev.done],
      activeStep: prev.activeStep,
      message: message,
      progress: value,
    ));
  }

  void _message(String message) {
    final prev = _live ?? _queued;
    _emit(JobProgressState(
      done: [...prev.done],
      activeStep: prev.activeStep,
      message: message,
    ));
  }

  void _allDone(String message) {
    _emit(JobProgressState(
      done: List.filled(7, true),
      activeStep: -1,
      message: message,
      progress: 1.0,
    ));
  }

  void _error(String message) {
    final prev = _live ?? _queued;
    _emit(JobProgressState(
      done: [...prev.done],
      activeStep: -1,
      message: message,
      progress: 1.0,
    ));
  }

  void _emit(JobProgressState next) {
    _live = next;
    state = next;
  }
}

final jobProgressProvider = NotifierProvider.autoDispose
    .family<JobProgressController, JobProgressState, String>(
        JobProgressController.new);
