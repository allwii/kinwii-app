# Kinwii Mobile App

## Product Vision

Kinwii is an AI-powered intentional living planner with goal tracking.
It connects mission → roles → quarterly goals → weekly big rocks → daily focus → reflection.
It follows the KISS (keep it simple and stupid) design principle, and empowers users to achieve their goals and track weekly and daily progress towards the goals.

Kinwii is NOT:
- A generic task manager
- A cluttered productivity dashboard
- A Notion clone
- A hustle culture app

Kinwii IS:
- Calm
- Focused
- Minimal
- AI-assisted
- Reflection-driven

Core loop:
Plan → Execute → Reflect → Improve

Clarity > Busyness
Direction > Activity
Reflection > Hustle

---

# Tech Stack

## Frontend
- Flutter (latest stable)
- Dart
- Riverpod for state management
- GoRouter for navigation
- Local persistence: Hive
- Clean Architecture pattern

## Backend
- FastAPI (Python 3.11+)
- Uvicorn
- Postgres (primary database)
- SQLAlchemy ORM
- Pydantic models
- JWT-based authentication

## AI Layer
- OpenAI API
- All AI calls handled ONLY by FastAPI backend
- No direct AI calls from Flutter
- Store AI responses in DB

## Notifications
- Firebase Cloud Messaging (FCM)

---

# High-Level Architecture

Flutter App
    ↓
FastAPI Backend
    ↓
Postgres
    ↓
OpenAI API (via backend only)

Never expose OpenAI key in mobile app.

---

# Suggested Project Structure (can improve if needed)

## Flutter Structure

lib/
  core/
    theme/
    constants/
    utils/
  features/
    auth/
    today/
    week/
    goals/
    reflect/
  services/
    api_service.dart
    auth_service.dart
  models/
  main.dart

Use feature-first architecture.

---

## FastAPI Structure

app/
  main.py
  api/
    routes_auth.py
    routes_goals.py
    routes_week.py
    routes_tasks.py
    routes_reflection.py
    routes_ai.py
  services/
    ai_service.py
    alignment_service.py
  models/
    user.py
    goal.py
    weekly_plan.py
    quarter_plan.py
    task.py
    reflection.py
  schemas/
  database.py
  config.py