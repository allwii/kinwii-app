# Kinwii Mobile App — Project Plan

## Overview

Kinwii is an AI-powered intentional living planner. Core loop: **Plan → Execute → Reflect → Improve**.

Alignment chain: **Quarterly Goals → Weekly Intent → Daily Execution → Weekly Reflection**

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter + Dart + Riverpod + GoRouter + Hive |
| Backend | FastAPI + SQLAlchemy + Alembic + Pydantic |
| Database | PostgreSQL |
| AI | OpenAI API (via backend only) |
| Auth | JWT (python-jose + bcrypt) |
| Notifications | Firebase Cloud Messaging |

---

## Architecture

```
Flutter App → FastAPI Backend → PostgreSQL
                             → OpenAI API
```

- Monorepo: `backend/` (FastAPI) + `mobile/` (Flutter)
- Python 3.12 venv at `backend/.venv/`
- Flutter at `/Users/bytedance/development/flutter/bin`

---

## Data Models

| Model | Key Fields |
|-------|-----------|
| User | id (UUID), email, hashed_password, created_at |
| QuarterlyGoal | id, user_id FK, title, why, start_date, end_date, progress_percent |
| WeeklyPlan | id, user_id FK, quarter_id FK, week_start_date, intent, progress_percent |
| Task | id, user_id FK, weekly_plan_id FK, title, date, completed, energy_type |
| WeeklyReflection | id, user_id FK, weekly_plan_id FK, 4 reflection fields, ai_summary, ai_focus_recommendation |

---

## API Endpoints (23 total)

### Auth
- `POST /auth/register` — Create account, return JWT
- `POST /auth/login` — Authenticate, return JWT
- `GET /auth/me` — Current user profile

### Goals
- `GET /goals` — List user's quarterly goals
- `POST /goals` — Create goal
- `GET /goals/{id}` — Get single goal
- `PUT /goals/{id}` — Update goal
- `DELETE /goals/{id}` — Delete goal

### Week
- `GET /week/current` — Get current week's plan
- `POST /week` — Create week plan
- `GET /week/{id}` — Get specific plan
- `PUT /week/{id}` — Update intent/progress

### Tasks
- `GET /tasks?date=YYYY-MM-DD` — Tasks for a date
- `POST /tasks` — Create task
- `PUT /tasks/{id}` — Update task
- `PATCH /tasks/{id}/complete` — Toggle completion
- `DELETE /tasks/{id}` — Delete task

### Reflection
- `GET /reflection/{weekly_plan_id}` — Get reflection
- `POST /reflection` — Submit reflection
- `PUT /reflection/{id}` — Update reflection

### AI
- `POST /ai/align-week` — 3 alignment suggestions
- `POST /ai/summarize-reflection` — Summary + focus recommendation

### Utility
- `GET /health` — Health check

---

## Flutter Screens

| Screen | Purpose | Route |
|--------|---------|-------|
| Login | Authentication | `/auth/login` |
| Register | Account creation | `/auth/register` |
| Onboarding | 4-step setup | `/onboarding` |
| Today | Daily focus | `/today` |
| Week | Weekly alignment | `/week` |
| Goals | Quarterly direction | `/goals` |
| Goal Detail | Goal deep-dive | `/goals/:id` |
| Reflect | Weekly reflection | `/reflect` |

Navigation: 4-tab bottom bar (Today, Week, Goals, Reflect)

---

## Development Phases

### Phase 1: Project Scaffolding ✅
- Git repo, .gitignore, directory structure
- FastAPI skeleton (main.py, config, database, empty modules)
- Flutter project with all dependencies

### Phase 2: Database Models & Migrations ✅
- 5 SQLAlchemy ORM models with relationships
- Alembic migration config
- UUID primary keys, cascade deletes, unique constraints

### Phase 3: Authentication ✅
- JWT auth (register, login, me)
- `get_current_user` dependency for all protected routes
- Flutter auth screens + secure token storage
- GoRouter redirect guards

### Phase 4: Core API Endpoints ✅
- Full CRUD for goals, week plans, tasks, reflections
- Ownership checks on every route (user_id filter)
- Progress calculation service (tasks → weekly progress)

### Phase 5: Flutter App Shell ✅
- Design system (AppColors, AppTypography, AppTheme)
- Shared widgets (KinwiiCard, ProgressBar, EmptyState)
- 4-tab bottom navigation with GoRouter ShellRoute

### Phase 6: Feature Screens ✅
- Today: tasks + intent + progress + add task + reflection prompt
- Week: 7-day grid + intent editing + AI align button
- Goals: card list + detail view + create goal
- Reflect: 4-question form + AI summary display

### Phase 7: AI Integration ✅
- AIService with AsyncOpenAI client
- Prompt engineering for alignment (3 suggestions) and reflection (summary + recommendation)
- Error handling with 503 fallback

### Phase 8: Onboarding ✅
- 4-step PageView (quarter → goal → why → intent)
- Auto-selects current quarter
- Creates goal + week plan on completion

### Phase 9: Local Caching (Hive)
- [ ] StorageService with Hive boxes
- [ ] Stale-while-revalidate pattern
- [ ] Offline Today screen support

### Phase 10: Firebase Cloud Messaging
- [ ] FCM setup (google-services.json, Info.plist)
- [ ] NotificationService scaffold
- [ ] FCM token storage endpoint

### Phase 11: Polish & Testing
- [ ] Backend pytest suite (auth, CRUD, ownership, AI mocks)
- [ ] Flutter unit + widget tests
- [ ] Animations, loading states, error states
- [ ] Accessibility (Semantics, tap targets, contrast)

---

## MVP Completion Criteria

User must be able to:
1. ✅ Create quarterly goal
2. ✅ Set weekly intent
3. ✅ Add daily tasks
4. ✅ Complete tasks
5. ✅ Submit weekly reflection
6. ✅ Receive AI summary

---

## Design System

| Token | Value |
|-------|-------|
| Background | #F8F9F6 (soft off-white) |
| Primary Accent | #78C850 (kiwi green) |
| Font | Inter |
| Card Radius | 16px |
| Shadows | Soft (0.04 opacity, 8px blur) |

Energy type colors: Deep=green, Admin=gray, Creative=purple, Personal=rose

---

## Security Rules

- All AI calls through backend only
- JWT auth required for all endpoints
- Row-level ownership checks (`user_id == current_user.id`)
- Returns 404 (not 403) to avoid leaking resource existence
- Never trust client input

---

## How to Run

### Backend
```bash
cd backend
source .venv/bin/activate
cp .env.example .env  # Edit with real credentials
alembic upgrade head
uvicorn app.main:app --reload
```

### Mobile
```bash
cd mobile
export PATH="$PATH:/Users/bytedance/development/flutter/bin"
flutter pub get
flutter run
```
