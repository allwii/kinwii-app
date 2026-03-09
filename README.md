# Kinwii

AI-powered intentional living planner with goal tracking.

Align your **Quarterly Goals → Weekly Intent → Daily Execution → Weekly Reflection**.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter 3.24 + Dart 3.5 + Riverpod + GoRouter + Hive |
| Backend | FastAPI + SQLAlchemy + Alembic + Pydantic |
| Database | PostgreSQL |
| AI | OpenAI API (backend only) |
| Auth | JWT (bcrypt + python-jose) |

---

## Prerequisites

- **Flutter** 3.24+ ([install guide](https://docs.flutter.dev/get-started/install))
- **Python** 3.11–3.12 (3.13+ not yet supported by pydantic-core)
- **PostgreSQL** 14+ — local install or any hosted Postgres
- **OpenAI API key** — for AI features
- **Xcode** (macOS, for iOS builds)
- **Android Studio** or Android SDK (for Android builds)
- **CocoaPods** (for iOS plugin support): `sudo gem install cocoapods`

---

## Project Structure

```
kinwii-app/
├── backend/                 # FastAPI API server
│   ├── app/
│   │   ├── api/             # Route handlers
│   │   ├── models/          # SQLAlchemy ORM models
│   │   ├── schemas/         # Pydantic request/response models
│   │   ├── services/        # AI + business logic
│   │   ├── middleware/      # Auth middleware
│   │   ├── main.py          # FastAPI app entry point
│   │   ├── config.py        # Environment config
│   │   └── database.py      # DB engine + session
│   ├── alembic/             # Database migrations
│   ├── tests/               # pytest test suite
│   ├── requirements.txt
│   └── .env.example
├── mobile/                  # Flutter mobile app
│   ├── lib/
│   │   ├── core/            # Theme, constants, shared widgets
│   │   ├── features/        # Feature modules (auth, today, week, goals, reflect, onboarding)
│   │   ├── models/          # Dart data models
│   │   ├── services/        # API + auth services
│   │   ├── router/          # GoRouter config
│   │   └── main.dart
│   └── pubspec.yaml
├── CLAUDE.md                # Product spec + coding guidelines
├── PROJECTPLAN.md           # Development plan + phase tracking
├── CHANGELOG.md             # Change history
└── README.md                # This file
```

---

## Backend Setup

### 1. Create virtual environment

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
```

### 2. Install dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure environment

```bash
cp .env.example .env
```

Edit `.env` with your credentials:

```
DATABASE_URL=postgresql://user:password@localhost:5432/kinwii
SECRET_KEY=your-256-bit-random-secret
OPENAI_API_KEY=sk-your-key-here
OPENAI_MODEL=gpt-5.2
```

### 4. Run database migrations

```bash
alembic upgrade head
```

### 5. Start the server

```bash
uvicorn app.main:app --reload
```

The API will be available at `http://localhost:8000`. Interactive docs at `http://localhost:8000/docs`.

---

## Mobile Setup

### 1. Ensure Flutter is on your PATH

```bash
export PATH="$PATH:/path/to/flutter/bin"
flutter doctor
```

### 2. Install dependencies

```bash
cd mobile
flutter pub get
```

### 3. Run on a device or emulator

```bash
# iOS simulator
flutter run -d ios

# Android emulator
flutter run -d android

# Specify backend URL (defaults to http://localhost:8000)
flutter run --dart-define=API_BASE_URL=http://your-backend-url
```

> **Note:** For iOS simulator talking to local backend, use `http://localhost:8000`. For Android emulator, use `http://10.0.2.2:8000`.

---

## API Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Create account |
| POST | `/auth/login` | Sign in |
| GET | `/auth/me` | Current user |
| GET | `/goals` | List goals |
| POST | `/goals` | Create goal |
| GET | `/goals/{id}` | Get goal |
| PUT | `/goals/{id}` | Update goal |
| DELETE | `/goals/{id}` | Delete goal |
| GET | `/week/current` | Current week plan |
| POST | `/week` | Create week plan |
| PUT | `/week/{id}` | Update week plan |
| GET | `/tasks?date=YYYY-MM-DD` | Tasks for a date |
| POST | `/tasks` | Create task |
| PATCH | `/tasks/{id}/complete` | Toggle completion |
| DELETE | `/tasks/{id}` | Delete task |
| POST | `/reflection` | Submit reflection |
| GET | `/reflection/{weekly_plan_id}` | Get reflection |
| POST | `/ai/align-week` | AI weekly alignment |
| POST | `/ai/summarize-reflection` | AI reflection summary |
| GET | `/health` | Health check |

All endpoints except `/auth/register`, `/auth/login`, and `/health` require a Bearer token.

---

## App Screens

| Tab | Screen | Purpose |
|-----|--------|---------|
| Today | Daily focus | See weekly intent, manage today's tasks (max 5) |
| Week | Weekly alignment | 7-day grid, edit intent, AI alignment suggestions |
| Goals | Quarterly direction | Create and track quarterly goals |
| Reflect | Weekly reflection | Answer 4 questions, receive AI summary |

### Onboarding (first-time users)
1. Select current quarter
2. Enter your #1 goal
3. Write why it matters
4. Set this week's intent

---

## Development

### Run backend tests

```bash
cd backend
source .venv/bin/activate
pytest
```

### Run Flutter analysis

```bash
cd mobile
flutter analyze
```

### Run Flutter tests

```bash
cd mobile
flutter test
```

---

## Environment Variables

### Backend (`.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | Postgres connection string |
| `SECRET_KEY` | Yes | JWT signing secret (256-bit random) |
| `ALGORITHM` | No | JWT algorithm (default: HS256) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | No | Token expiry (default: 10080 = 7 days) |
| `OPENAI_API_KEY` | Yes | OpenAI API key |
| `OPENAI_MODEL` | No | Model to use (default: gpt-4o-mini) |
| `ENVIRONMENT` | No | development / production |

### Mobile (compile-time)

| Variable | Default | Description |
|----------|---------|-------------|
| `API_BASE_URL` | `http://localhost:8000` | Backend URL (pass via `--dart-define`) |

---

## Design

- **Font:** Inter
- **Background:** #F8F9F6 (soft off-white)
- **Accent:** #78C850 (kiwi green)
- **Cards:** 16px radius, soft shadows
- **Feeling:** Calm morning clarity
