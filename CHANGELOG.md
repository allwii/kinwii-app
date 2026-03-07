# Changelog

All notable changes to the Kinwii app are documented here.

Format: [category] description — files affected

---

## 2026-02-25 — AI Features Wave 1

### Added

#### Bug Fix
- [backend] `GET /tasks` now accepts optional `weekly_plan_id` query param (in addition to `date`) — `backend/app/api/routes_tasks.py`

#### Feature A: Daily Focus Suggestions
- [backend] `POST /ai/suggest-daily-focus` endpoint — returns 1-3 AI focus suggestions for today based on quarterly goal, weekly intent, tasks, and last week's recommendation — `backend/app/api/routes_ai.py`
- [backend] `suggest_daily_focus()` method in AIService with calm morning coach prompt — `backend/app/services/ai_service.py`
- [backend] `DailyFocusRequest/Response` schemas — `backend/app/schemas/ai.py`
- [flutter] `_DailyFocusCard` widget on Today screen — kiwi50 background, sparkle icon, 1-3 bullet points, optional nudge, dismissable — `mobile/lib/features/today/presentation/screens/today_screen.dart`

#### Feature B: Weekly Intent Suggestion
- [backend] `POST /ai/suggest-intent` endpoint — suggests a weekly intent based on quarterly goal + last week's reflection — `backend/app/api/routes_ai.py`
- [backend] `suggest_intent()` method in AIService — `backend/app/services/ai_service.py`
- [backend] `SuggestIntentRequest/Response` schemas — `backend/app/schemas/ai.py`
- [backend] `GET /week/previous` endpoint — returns the most recent week plan before current week — `backend/app/api/routes_week.py`
- [flutter] "Suggest intent" chip on Week screen intent edit mode — calls AI, fills text field with suggestion — `mobile/lib/features/week/presentation/screens/week_screen.dart`

#### Feature C: Enhanced Reflection with Pattern Tracking
- [backend] Added `ai_pattern_insight` column to `weekly_reflections` table — `backend/app/models/reflection.py`
- [backend] Alembic migration for new column — `backend/alembic/versions/f76fc44f0e59_add_ai_pattern_insight_to_reflections.py`
- [backend] Enhanced `summarize_reflection()` — now fetches last 4 weeks of reflections + quarterly goal context for pattern detection — `backend/app/services/ai_service.py`
- [backend] Updated `SummarizeReflectionResponse` with `pattern_insight` field — `backend/app/schemas/ai.py`, `backend/app/schemas/reflection.py`
- [flutter] Added `aiPatternInsight` field to `WeeklyReflection` model — `mobile/lib/models/weekly_reflection.dart`
- [flutter] "Pattern noticed" card (trending_up icon, kiwi50 background) in both `_AiResultView` and `_ReflectionReadOnly` — `mobile/lib/features/reflect/presentation/screens/reflect_screen.dart`

#### Enriched Existing AI
- [backend] `align_week()` now fetches quarterly goal context (title, why, progress, weeks remaining) for goal-aware suggestions — `backend/app/services/ai_service.py`

### Changed
- [backend] `align_week()` and `summarize_reflection()` signatures now accept `db: Session` parameter — `backend/app/services/ai_service.py`, `backend/app/api/routes_ai.py`
- [docs] Updated PROJECTPLAN.md with AI features roadmap (Wave 1, 2, 3) — `PROJECTPLAN.md`
- [backend] Route count: 27 → 30 (added 3 new endpoints)

---

## 2026-02-22 — Initial MVP Build

### Added

#### Project Setup
- [scaffold] Initialized git repo with comprehensive .gitignore — `.gitignore`
- [scaffold] Created monorepo structure: `backend/` (FastAPI) + `mobile/` (Flutter)
- [backend] FastAPI project with Python 3.12 venv, all dependencies installed — `backend/requirements.txt`
- [backend] Environment config with Pydantic Settings — `backend/app/config.py`
- [backend] SQLAlchemy database engine and session dependency — `backend/app/database.py`
- [backend] Alembic migration setup — `backend/alembic.ini`, `backend/alembic/env.py`
- [mobile] Flutter project created with Riverpod, GoRouter, Hive, Dio, flutter_secure_storage — `mobile/pubspec.yaml`

#### Database Models (5 tables)
- [backend] User model — `backend/app/models/user.py`
- [backend] QuarterlyGoal model — `backend/app/models/goal.py`
- [backend] WeeklyPlan model with unique constraint (user_id, week_start_date) — `backend/app/models/weekly_plan.py`
- [backend] Task model with EnergyType enum (deep, admin, creative, personal) — `backend/app/models/task.py`
- [backend] WeeklyReflection model with AI response fields — `backend/app/models/reflection.py`

#### Authentication (3 endpoints)
- [backend] JWT auth middleware with bcrypt password hashing — `backend/app/middleware/auth_middleware.py`
- [backend] Auth routes: POST /auth/register, POST /auth/login, GET /auth/me — `backend/app/api/routes_auth.py`
- [backend] Auth schemas: UserCreate, UserResponse, TokenResponse — `backend/app/schemas/user.py`
- [mobile] AuthService with flutter_secure_storage for JWT — `mobile/lib/services/auth_service.dart`
- [mobile] ApiService (Dio) with Bearer token interceptor and 401 handler — `mobile/lib/services/api_service.dart`
- [mobile] Login screen — `mobile/lib/features/auth/presentation/screens/login_screen.dart`
- [mobile] Register screen — `mobile/lib/features/auth/presentation/screens/register_screen.dart`

#### Core API Endpoints (18 endpoints)
- [backend] Goals CRUD: GET/POST /goals, GET/PUT/DELETE /goals/{id} — `backend/app/api/routes_goals.py`
- [backend] Week plans: GET /week/current, POST /week, GET/PUT /week/{id} — `backend/app/api/routes_week.py`
- [backend] Tasks: GET /tasks?date=, POST, PUT, PATCH complete, DELETE — `backend/app/api/routes_tasks.py`
- [backend] Reflections: GET /reflection/{weekly_plan_id}, POST, PUT — `backend/app/api/routes_reflection.py`
- [backend] Progress calculation service — `backend/app/services/alignment_service.py`
- [backend] Pydantic schemas for all resources — `backend/app/schemas/`

#### AI Integration (2 endpoints)
- [backend] AIService with AsyncOpenAI, prompt engineering — `backend/app/services/ai_service.py`
- [backend] POST /ai/align-week (3 suggestions) — `backend/app/api/routes_ai.py`
- [backend] POST /ai/summarize-reflection (summary + focus recommendation) — `backend/app/api/routes_ai.py`

#### Flutter Design System
- [mobile] AppColors: kiwi green palette, off-white background, energy type colors — `mobile/lib/core/theme/app_colors.dart`
- [mobile] AppTypography: Inter font scale — `mobile/lib/core/theme/app_typography.dart`
- [mobile] AppTheme: Material 3 theme with custom card, button, input styles — `mobile/lib/core/theme/app_theme.dart`
- [mobile] KinwiiCard widget (16px radius, soft shadow) — `mobile/lib/core/widgets/kinwii_card.dart`
- [mobile] ProgressBar widget (animated, kiwi green) — `mobile/lib/core/widgets/progress_bar.dart`
- [mobile] EmptyState widget — `mobile/lib/core/widgets/empty_state.dart`

#### Flutter Navigation
- [mobile] GoRouter with ShellRoute, auth guards, NoTransitionPage — `mobile/lib/router/app_router.dart`
- [mobile] AppShell with 4-tab NavigationBar (Today, Week, Goals, Reflect) — `mobile/lib/features/shell/app_shell.dart`

#### Flutter Feature Screens
- [mobile] Today screen: date header, intent card, task list with optimistic toggle, add task sheet — `mobile/lib/features/today/presentation/screens/today_screen.dart`
- [mobile] Week screen: 7-day grid, intent editing, AI align button with suggestions sheet — `mobile/lib/features/week/presentation/screens/week_screen.dart`
- [mobile] Goals screen: goal cards, create goal sheet, empty state — `mobile/lib/features/goals/presentation/screens/goals_screen.dart`
- [mobile] Goal detail screen: full goal info, progress, date range — `mobile/lib/features/goals/presentation/screens/goal_detail_screen.dart`
- [mobile] Reflect screen: 4-question form, AI summary with fade animation — `mobile/lib/features/reflect/presentation/screens/reflect_screen.dart`

#### Flutter Onboarding
- [mobile] 4-step onboarding: quarter selection → goal → why → intent → Today — `mobile/lib/features/onboarding/presentation/screens/onboarding_screen.dart`

#### Dart Models
- [mobile] QuarterlyGoal, WeeklyPlan, Task (with EnergyType), WeeklyReflection — `mobile/lib/models/`

---

## Upcoming

- Hive local caching with stale-while-revalidate
- Firebase Cloud Messaging scaffold
- Backend pytest suite
- Flutter widget tests
- UI polish (shimmer loading, animations, accessibility)
