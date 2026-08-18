import 'package:ad_craft_frontend/core/api/api_client.dart';
import 'package:ad_craft_frontend/models/models.dart';
import 'package:ad_craft_frontend/providers/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
}

class _FakeRepo extends ApiRepository {
  _FakeRepo({List<JobSummary>? jobs}) : jobs = jobs ?? [], super(Dio(BaseOptions(baseUrl: 'http://localhost')));

  List<JobSummary> jobs;
  final List<Map<String, dynamic>> listCalls = [];
  bool? lastFavorite;
  bool failFavorites = false;

  @override
  Future<JobListPage> listJobs({
    int page = 1,
    int perPage = 20,
    String? status,
    String? aspectRatio,
    String? query,
    bool favoritesOnly = false,
  }) async {
    listCalls.add({
      'page': page,
      'query': query,
      'status': status,
      'aspectRatio': aspectRatio,
      'favoritesOnly': favoritesOnly,
    });
    final start = (page - 1) * perPage;
    final slice = jobs.skip(start).take(perPage).toList();
    return JobListPage(items: slice, total: jobs.length, page: page, perPage: perPage);
  }

  @override
  Future<bool> setFavorite(String jobId, bool favorite) async {
    if (failFavorites) {
      throw Exception('boom');
    }
    lastFavorite = favorite;
    return favorite;
  }
}

JobSummary _job(String id, {String status = 'completed', bool favorite = false}) => JobSummary(
      jobId: id,
      status: status,
      aspectRatio: '9:16',
      createdAt: DateTime.now(),
      title: 'Job $id',
      prompt: 'brief',
      favorite: favorite,
    );

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(_FakeAuth.new),
    ]);
    addTearDown(container.dispose);
  });

  test('loads page 1 on build', () async {
    repo.jobs = [_job('j1'), _job('j2'), _job('j3')];
    container.read(jobListControllerProvider);
    await _flush();
    final state = container.read(jobListControllerProvider);
    expect(state.items, hasLength(3));
    expect(state.total, 3);
    expect(state.loading, isFalse);
    expect(repo.listCalls.first['page'], 1);
  });

  test('applyFilters resets pagination and reloads with query', () async {
    repo.jobs = [_job('j1'), _job('j2')];
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).applyFilters(query: 'coffee');
    await _flush();
    final state = container.read(jobListControllerProvider);
    expect(state.query, 'coffee');
    expect(state.page, 1);
    expect(repo.listCalls.last['query'], 'coffee');
  });

  test('applyFilters passes status, aspect and favoritesOnly', () async {
    repo.jobs = [_job('j1')];
    container.read(jobListControllerProvider);
    await _flush();
    container
        .read(jobListControllerProvider.notifier)
        .applyFilters(status: 'failed', aspect: '1:1', favoritesOnly: true);
    await _flush();
    final call = repo.listCalls.last;
    expect(call['status'], 'failed');
    expect(call['aspectRatio'], '1:1');
    expect(call['favoritesOnly'], isTrue);
  });

  test('loadMore appends the next page', () async {
    repo.jobs = List.generate(25, (i) => _job('j${i + 1}'));
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).loadMore();
    await _flush();
    final state = container.read(jobListControllerProvider);
    expect(state.items, hasLength(25));
    expect(state.total, 25);
    expect(state.hasMore, isFalse);
  });

  test('toggleFavorite flips state and calls the API', () async {
    repo.jobs = [_job('j1', favorite: false)];
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).toggleFavorite('j1');
    await _flush();
    expect(repo.lastFavorite, isTrue);
    expect(container.read(jobListControllerProvider).items.first.favorite, isTrue);
  });

  test('toggleFavorite reverts on API failure', () async {
    repo.jobs = [_job('j1', favorite: false)];
    repo.failFavorites = true;
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).toggleFavorite('j1');
    await _flush();
    expect(container.read(jobListControllerProvider).items.first.favorite, isFalse);
  });

  test('addJob prepends an unfiltered list', () async {
    repo.jobs = [_job('j1')];
    container.read(jobListControllerProvider);
    await _flush();
    container.read(jobListControllerProvider.notifier).addJob('brand-new');
    final state = container.read(jobListControllerProvider);
    expect(state.items.first.jobId, 'brand-new');
    expect(state.items, hasLength(2));
  });
}