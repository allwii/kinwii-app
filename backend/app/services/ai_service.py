import json
from datetime import date, timedelta

from openai import AsyncOpenAI
from sqlalchemy.orm import Session

from app.config import settings
from app.models.coach_message import CoachMessage
from app.models.goal import QuarterlyGoal
from app.models.mission import Mission
from app.models.reflection import WeeklyReflection
from app.models.role import Role
from app.models.task import Task
from app.models.user import User
from app.models.weekly_plan import WeeklyPlan

ALIGN_SYSTEM_PROMPT = """You are a calm, focused productivity coach for Kinwii, \
an intentional living app. Given a user's quarterly goal, weekly intent, and task list, \
provide exactly 3 concise, actionable suggestions to better align their week. \
Each suggestion is one sentence. Return a JSON array of 3 strings. No preamble."""

REFLECTION_SYSTEM_PROMPT = """You are a calm, encouraging reflection coach. \
Given a user's weekly reflection answers, write:
1. A summary paragraph (under 120 words) that synthesizes their week.
2. One clear, specific focus recommendation for next week.
3. If historical reflections are provided, analyze patterns across weeks. \
If you notice recurring energy drains, repeated themes, or whether the user \
followed previous recommendations, provide a brief pattern insight (1-2 sentences). \
If no clear pattern exists, return null for pattern_insight.
Return valid JSON: {"summary": "...", "focus_recommendation": "...", "pattern_insight": "..." or null}
Tone: calm, human, encouraging. Not corporate. Not hype."""

DAILY_FOCUS_SYSTEM_PROMPT = """You are a calm morning coach for Kinwii, \
an intentional living app. Given the user's quarterly goal, weekly intent, and task list, \
suggest 1-3 focus items for today. Prioritize deep work and goal-aligned tasks. \
Front-load important items Mon-Wed. Be concise — each suggestion is one sentence. \
Optionally include a brief nudge (one warm sentence of encouragement or a gentle reminder). \
Return valid JSON: {"suggestions": ["...", "...", "..."], "nudge": "..." or null}
No preamble. No hype."""

SUGGEST_DAILY_INTENT_SYSTEM_PROMPT = """You are a calm morning coach for Kinwii, \
an intentional living app. Based on the user's quarterly goal, weekly intent, \
and today's tasks, suggest a daily intent — one sentence that captures what \
today is about. It should be specific, actionable, and connect to the weekly intent. \
Return valid JSON: {"daily_intent": "..."}
No preamble. No hype."""

SUGGEST_INTENT_SYSTEM_PROMPT = """You are a calm planning coach for Kinwii, \
an intentional living app. Based on the user's quarterly goal and last week's \
progress and reflection, suggest a weekly intent for the upcoming week. \
One sentence, actionable, specific. It should connect to the quarterly goal \
and build on what was learned last week. \
Return valid JSON: {"suggested_intent": "..."}
No preamble."""

COACH_SYSTEM_PROMPT = """You are a calm, wise growth coach inside Kinwii, \
an intentional living app. You help users live with clarity and purpose.

Your personality:
- Warm but not cheesy. Calm but not passive.
- Ask thoughtful questions. Don't lecture.
- Keep responses concise (2-4 sentences usually). Go longer only when depth is needed.
- Use the user's planning context (mission, roles, goals, weekly intent, reflections) \
to give personalized, grounded advice.
- Stay scoped to intentional living: goals, focus, energy, reflection, priorities, balance.
- If someone asks about unrelated topics, gently redirect.

Never say "As an AI" or "I'm just a language model". Just be the coach."""


class AIService:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self.model = settings.OPENAI_MODEL

    async def align_week(
        self, plan: WeeklyPlan, tasks: list[Task], db: Session
    ) -> list[str]:
        task_lines = "\n".join(
            f"- {'[x]' if t.completed else '[ ]'} {t.title} ({t.energy_type.value}, {t.date})"
            for t in tasks
        )

        # Fetch quarterly goal for richer context
        goal_context = ""
        if plan.quarter_id:
            goal = db.query(QuarterlyGoal).filter(QuarterlyGoal.id == plan.quarter_id).first()
            if goal:
                weeks_remaining = max(0, (goal.end_date - date.today()).days // 7)
                goal_context = (
                    f"Quarterly goal: {goal.title}\n"
                    f"Why: {goal.why or 'Not specified'}\n"
                    f"Progress: {goal.progress_percent or 0}%\n"
                    f"Weeks remaining in quarter: {weeks_remaining}\n\n"
                )

        prompt = (
            f"{goal_context}"
            f"Weekly intent: {plan.intent}\n\n"
            f"Current tasks:\n{task_lines or '(no tasks yet)'}"
        )
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": ALIGN_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_completion_tokens=300,
            temperature=0.7,
        )
        content = response.choices[0].message.content or "[]"
        try:
            suggestions = json.loads(content)
            if isinstance(suggestions, list):
                return suggestions[:3]
        except json.JSONDecodeError:
            pass
        return [content.strip()]

    async def summarize_reflection(
        self, reflection: WeeklyReflection, db: Session
    ) -> tuple[str, str, str | None]:
        # Fetch historical reflections (last 4 weeks)
        historical = (
            db.query(WeeklyReflection)
            .filter(
                WeeklyReflection.user_id == reflection.user_id,
                WeeklyReflection.id != reflection.id,
            )
            .order_by(WeeklyReflection.created_at.desc())
            .limit(4)
            .all()
        )

        # Fetch linked goal context
        goal_context = ""
        plan = reflection.weekly_plan
        if plan and plan.quarter_id:
            goal = db.query(QuarterlyGoal).filter(QuarterlyGoal.id == plan.quarter_id).first()
            if goal:
                goal_context = f"\nQuarterly goal: {goal.title}\nWeekly intent: {plan.intent}\n"

        prompt = (
            f"This week's reflection:{goal_context}\n"
            f"What moved the needle: {reflection.moved_needle or 'N/A'}\n"
            f"What drained energy: {reflection.drained_energy or 'N/A'}\n"
            f"What to stop doing: {reflection.stop_doing or 'N/A'}\n"
            f"What deserves more focus: {reflection.focus_next_week or 'N/A'}"
        )

        if historical:
            prompt += "\n\nHistorical reflections (most recent first):"
            for i, h in enumerate(historical, 1):
                prompt += (
                    f"\n--- Week {i} ago ---\n"
                    f"Moved needle: {h.moved_needle or 'N/A'}\n"
                    f"Drained energy: {h.drained_energy or 'N/A'}\n"
                    f"Stop doing: {h.stop_doing or 'N/A'}\n"
                    f"Focus next week: {h.focus_next_week or 'N/A'}\n"
                    f"Previous AI recommendation: {h.ai_focus_recommendation or 'N/A'}"
                )

        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": REFLECTION_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_completion_tokens=500,
            temperature=0.6,
        )
        content = response.choices[0].message.content or "{}"
        try:
            data = json.loads(content)
            return (
                data.get("summary", ""),
                data.get("focus_recommendation", ""),
                data.get("pattern_insight"),
            )
        except json.JSONDecodeError:
            return (content.strip(), "", None)

    async def suggest_daily_focus(
        self, plan: WeeklyPlan, tasks: list[Task], focus_date: date, db: Session
    ) -> tuple[list[str], str | None]:
        task_lines = "\n".join(
            f"- {'[x]' if t.completed else '[ ]'} {t.title} ({t.energy_type.value}, {t.date})"
            for t in tasks
        )

        # Fetch quarterly goal
        goal_context = ""
        if plan.quarter_id:
            goal = db.query(QuarterlyGoal).filter(QuarterlyGoal.id == plan.quarter_id).first()
            if goal:
                weeks_remaining = max(0, (goal.end_date - date.today()).days // 7)
                goal_context = (
                    f"Quarterly goal: {goal.title}\n"
                    f"Why: {goal.why or 'Not specified'}\n"
                    f"Weeks remaining: {weeks_remaining}\n\n"
                )

        # Fetch last week's AI focus recommendation
        last_rec = ""
        last_monday = plan.week_start_date - timedelta(days=7)
        prev_plan = (
            db.query(WeeklyPlan)
            .filter(
                WeeklyPlan.user_id == plan.user_id,
                WeeklyPlan.week_start_date == last_monday,
            )
            .first()
        )
        if prev_plan and prev_plan.reflection:
            rec = prev_plan.reflection.ai_focus_recommendation
            if rec:
                last_rec = f"\nLast week's AI focus recommendation: {rec}\n"

        day_name = focus_date.strftime("%A")
        prompt = (
            f"{goal_context}"
            f"Weekly intent: {plan.intent}\n"
            f"Today: {day_name}, {focus_date}\n"
            f"{last_rec}\n"
            f"This week's tasks:\n{task_lines or '(no tasks yet)'}"
        )
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": DAILY_FOCUS_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_completion_tokens=250,
            temperature=0.7,
        )
        content = response.choices[0].message.content or "{}"
        try:
            data = json.loads(content)
            suggestions = data.get("suggestions", [])
            if isinstance(suggestions, list):
                return suggestions[:3], data.get("nudge")
        except json.JSONDecodeError:
            pass
        return [content.strip()], None

    async def suggest_daily_intent(
        self, plan: WeeklyPlan, tasks: list[Task], focus_date: date, db: Session
    ) -> str:
        task_lines = "\n".join(
            f"- {'[x]' if t.completed else '[ ]'} {t.title} ({t.energy_type.value})"
            for t in tasks
            if t.date == focus_date
        )

        goal_context = ""
        if plan.quarter_id:
            goal = db.query(QuarterlyGoal).filter(QuarterlyGoal.id == plan.quarter_id).first()
            if goal:
                goal_context = f"Quarterly goal: {goal.title}\n"

        day_name = focus_date.strftime("%A")
        prompt = (
            f"{goal_context}"
            f"Weekly intent: {plan.intent}\n"
            f"Today: {day_name}, {focus_date}\n\n"
            f"Today's tasks:\n{task_lines or '(no tasks yet)'}"
        )
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": SUGGEST_DAILY_INTENT_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_completion_tokens=100,
            temperature=0.7,
        )
        content = response.choices[0].message.content or "{}"
        try:
            data = json.loads(content)
            return data.get("daily_intent", content.strip())
        except json.JSONDecodeError:
            return content.strip()

    async def suggest_intent(
        self,
        goal: QuarterlyGoal,
        previous_plan: WeeklyPlan | None,
    ) -> str:
        weeks_remaining = max(0, (goal.end_date - date.today()).days // 7)
        prompt = (
            f"Quarterly goal: {goal.title}\n"
            f"Why: {goal.why or 'Not specified'}\n"
            f"Progress: {goal.progress_percent or 0}%\n"
            f"Weeks remaining: {weeks_remaining}\n"
        )

        if previous_plan:
            prompt += (
                f"\nLast week's intent: {previous_plan.intent}\n"
                f"Last week's progress: {previous_plan.progress_percent or 0}%\n"
            )
            if previous_plan.reflection:
                r = previous_plan.reflection
                prompt += (
                    f"\nLast week's reflection:\n"
                    f"Moved needle: {r.moved_needle or 'N/A'}\n"
                    f"Drained energy: {r.drained_energy or 'N/A'}\n"
                    f"Stop doing: {r.stop_doing or 'N/A'}\n"
                    f"Focus next week: {r.focus_next_week or 'N/A'}\n"
                    f"AI recommendation: {r.ai_focus_recommendation or 'N/A'}"
                )

        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": SUGGEST_INTENT_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_completion_tokens=150,
            temperature=0.7,
        )
        content = response.choices[0].message.content or "{}"
        try:
            data = json.loads(content)
            return data.get("suggested_intent", content.strip())
        except json.JSONDecodeError:
            return content.strip()

    async def coach_respond(
        self, user: User, history: list[CoachMessage], db: Session
    ) -> str:
        # Build user context from their planning data
        context_parts = []

        # Mission
        mission = db.query(Mission).filter(Mission.user_id == user.id).first()
        if mission:
            context_parts.append(f"Life mission: {mission.statement}")

        # Roles
        roles = db.query(Role).filter(Role.user_id == user.id).all()
        if roles:
            role_names = ", ".join(r.name for r in roles)
            context_parts.append(f"Life roles: {role_names}")

        # Current goal
        goal = (
            db.query(QuarterlyGoal)
            .filter(
                QuarterlyGoal.user_id == user.id,
                QuarterlyGoal.end_date >= date.today(),
            )
            .order_by(QuarterlyGoal.start_date.desc())
            .first()
        )
        if goal:
            context_parts.append(
                f"Current goal: {goal.title} ({goal.progress_percent or 0}% done)"
            )

        # Current weekly plan
        plan = (
            db.query(WeeklyPlan)
            .filter(WeeklyPlan.user_id == user.id)
            .order_by(WeeklyPlan.week_start_date.desc())
            .first()
        )
        if plan:
            context_parts.append(f"This week's intent: {plan.intent}")

        # Latest reflection
        reflection = (
            db.query(WeeklyReflection)
            .filter(WeeklyReflection.user_id == user.id)
            .order_by(WeeklyReflection.created_at.desc())
            .first()
        )
        if reflection and reflection.ai_summary:
            context_parts.append(f"Latest reflection summary: {reflection.ai_summary}")

        context_str = "\n".join(context_parts) if context_parts else "No planning context yet."

        # Build messages
        messages = [
            {
                "role": "system",
                "content": (
                    f"{COACH_SYSTEM_PROMPT}\n\n"
                    f"User's planning context:\n{context_str}"
                ),
            },
        ]
        for msg in history:
            messages.append({"role": msg.role, "content": msg.content})

        response = await self.client.chat.completions.create(
            model=self.model,
            messages=messages,
            max_completion_tokens=400,
            temperature=0.7,
        )
        return response.choices[0].message.content or "I'm here whenever you're ready to talk."


_ai_service: AIService | None = None


def get_ai_service() -> AIService:
    global _ai_service
    if _ai_service is None:
        _ai_service = AIService()
    return _ai_service
