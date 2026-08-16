import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/job_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/jobs/:id',
        builder: (context, state) =>
            JobScreen(jobId: state.pathParameters['id']!),
      ),
    ],
  );
});

class AdCraftApp extends ConsumerWidget {
  const AdCraftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ad Craft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8A5A44),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
