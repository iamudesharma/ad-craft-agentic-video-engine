import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/providers.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/job_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/org_settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final location = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return location == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return location == '/login' ? null : '/login';
        case AuthStatus.authenticated:
          if (auth.org == null) {
            return location == '/onboarding' ? null : '/onboarding';
          }
          if (location == '/login' || location == '/onboarding') {
            return '/';
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(path: '/login', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/jobs/:id',
        builder: (context, state) =>
            JobScreen(jobId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/org',
        builder: (context, state) => const OrgSettingsScreen(),
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