import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/providers.dart';
import '../features/goals/presentation/screens/goal_detail_screen.dart';
import '../features/goals/presentation/screens/goals_screen.dart';
import '../features/mission/presentation/screens/mission_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/settings/presentation/screens/account_screen.dart';
import '../features/settings/presentation/screens/notification_settings_screen.dart';
import '../features/settings/presentation/screens/privacy_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/coach/presentation/screens/coach_screen.dart';
import '../features/reflect/presentation/screens/weekly_review_screen.dart';
import '../features/analytics/presentation/screens/analytics_screen.dart';
import '../features/subscription/presentation/screens/paywall_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/today/presentation/screens/today_screen.dart';
import '../features/week/presentation/screens/week_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.read(authServiceProvider);

  return GoRouter(
    initialLocation: '/onboarding',
    redirect: (context, state) async {
      try {
        final isLoggedIn = await authService.isLoggedIn();
        final loc = state.matchedLocation;
        final isOnboardingRoute = loc == '/onboarding';
        final isPaywallRoute = loc == '/pro';

        if (!isLoggedIn) {
          // No token — send to onboarding (which will auto-register)
          if (isOnboardingRoute || isPaywallRoute) return null;
          return '/onboarding';
        }

        // Logged in — skip onboarding
        if (isOnboardingRoute) {
          final onboarded = await authService.isOnboardingComplete();
          return onboarded ? '/today' : null;
        }

        return null;
      } catch (_) {
        return '/onboarding';
      }
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/mission',
        builder: (context, state) => const MissionScreen(),
      ),
      GoRoute(
        path: '/pro',
        builder: (context, state) => const PaywallScreen(),
      ),
      GoRoute(
        path: '/analytics',
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => const AccountScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: '/reflect/review/:id',
        builder: (context, state) => WeeklyReviewScreen(
          weeklyPlanId: state.pathParameters['id']!,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/today',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TodayScreen(),
            ),
          ),
          GoRoute(
            path: '/week',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WeekScreen(),
            ),
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: GoalsScreen(),
            ),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => GoalDetailScreen(
                  goalId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/coach',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CoachScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
