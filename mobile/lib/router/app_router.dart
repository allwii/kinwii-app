import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/goals/presentation/screens/goal_detail_screen.dart';
import '../features/goals/presentation/screens/goals_screen.dart';
import '../features/mission/presentation/screens/mission_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/reflect/presentation/screens/reflect_screen.dart';
import '../features/coach/presentation/screens/coach_screen.dart';
import '../features/reflect/presentation/screens/weekly_review_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/today/presentation/screens/today_screen.dart';
import '../features/week/presentation/screens/week_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.read(authServiceProvider);

  return GoRouter(
    initialLocation: '/auth/login',
    redirect: (context, state) async {
      final isLoggedIn = await authService.isLoggedIn();
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) {
        final onboarded = await authService.isOnboardingComplete();
        return onboarded ? '/today' : '/onboarding';
      }
      return null;
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
        path: '/coach',
        builder: (context, state) => const CoachScreen(),
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
            path: '/reflect',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReflectScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
