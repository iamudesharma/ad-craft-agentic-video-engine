import 'package:ad_craft_frontend/core/api/api_client.dart';
import 'package:ad_craft_frontend/models/models.dart';
import 'package:ad_craft_frontend/providers/providers.dart';
import 'package:ad_craft_frontend/widgets/job_list.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
}

class _FakeRepo extends ApiRepository {
  _FakeRepo({List<JobSummary>? jobs})
      : jobs = jobs ?? [],
        super(Dio(BaseOptions(baseUrl: 'http://localhost')));

  List<JobSummary> jobs;
  final List<Map<String, dynamic>> listCalls = [];
  bool? lastFavorite;

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
    lastFavorite = favorite;
    return favorite;
  }
}

JobSummary _job(String id, String title,
        {String status = 'completed', bool storyboard = false, bool favorite = false}) =>
    JobSummary(
      jobId: id,
      status: status,
      aspectRatio: '9:16',
      createdAt: DateTime.now(),
      title: title,
      prompt: 'brief for $title',
      hasStoryboard: storyboard,
      favorite: favorite,
    );

Widget _wrap(ApiRepository repo) => ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_FakeAuth.new),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: JobListSection()),
            ),
            GoRoute(
              path: '/jobs/:jobId',
              builder: (_, s) => Scaffold(
                body: Text('job ${s.pathParameters['jobId']}'),
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('renders job rows with titles', (tester) async {
    final repo = _FakeRepo(
      jobs: [_job('j1', 'Craft Coffee', storyboard: true)],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('Craft Coffee'), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
  });

  testWidgets('star toggles favorite via the API', (tester) async {
    final repo = _FakeRepo(jobs: [_job('j1', 'Craft Coffee')]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle();
    expect(repo.lastFavorite, isTrue);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('menu shows clone storyboard only when storyboard exists', (tester) async {
    final repo = _FakeRepo(
      jobs: [
        _job('j1', 'With board', storyboard: true),
        _job('j2', 'No board'),
      ],
    );
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options').first);
    await tester.pumpAndSettle();
    expect(find.text('Clone storyboard'), findsOneWidget);
    expect(find.text('New from brief'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options').last);
    await tester.pumpAndSettle();
    expect(find.text('Clone storyboard'), findsNothing);
  });

  testWidgets('typing in search applies the query filter', (tester) async {
    final repo = _FakeRepo(jobs: [_job('j1', 'Craft Coffee')]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.listCalls.last['query'], 'coffee');
  });

  testWidgets('shows empty states', (tester) async {
    final repo = _FakeRepo(jobs: []);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    expect(find.text('No jobs yet - generate one'), findsOneWidget);
    await tester.tap(find.text('Failed'));
    await tester.pumpAndSettle();
    expect(find.text('No jobs match your filters'), findsOneWidget);
  });

  group('relativeTime', () {
    final now = DateTime(2026, 8, 18, 12, 0, 0);
    test('formats minutes, hours, days and dates', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 30)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now), '2d ago');
      expect(relativeTime(DateTime(2026, 1, 5), now: now), '1/5/2026');
    });
  });
}
