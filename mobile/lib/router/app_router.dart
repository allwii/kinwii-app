import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/goals/presentation/screens/goal_detail_screen.dart';
import '../features/goals/presentation/screens/goals_screen.dart';
import '../features/mission/presentation/screens/mission_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
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
      final isLoggedIn = await authService.isLoggedIn();
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/auth');
      final isOnboardingRoute = loc == '/onboarding';

      if (isLoggedIn) {
        // Logged-in users skip auth & onboarding screens
        if (isAuthRoute || isOnboardingRoute) {
          final onboarded = await authService.isOnboardingComplete();
          return onboarded ? '/today' : '/today';
        }
        return null;
      }

      // Not logged in — allow auth and onboarding routes
      if (isAuthRoute || isOnboardingRoute) return null;

      // Not logged in, trying to access app — send to onboarding or login
      final seen = await authService.isOnboardingSeen();
      return seen ? '/auth/login' : '/onboarding';
    },
    routes: [
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),
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
