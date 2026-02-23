import json

from openai import AsyncOpenAI

from app.config import settings
from app.models.reflection import WeeklyReflection
from app.models.task import Task
from app.models.weekly_plan import WeeklyPlan

ALIGN_SYSTEM_PROMPT = """You are a calm, focused productivity coach for Kinwii, \
an intentional living app. Given a user's weekly intent and task list, \
provide exactly 3 concise, actionable suggestions to better align their week. \
Each suggestion is one sentence. Return a JSON array of 3 strings. No preamble."""

REFLECTION_SYSTEM_PROMPT = """You are a calm, encouraging reflection coach. \
Given a user's weekly reflection answers, write:
1. A summary paragraph (under 120 words) that synthesizes their week.
2. One clear, specific focus recommendation for next week.
Return valid JSON: {"summary": "...", "focus_recommendation": "..."}
Tone: calm, human, encouraging. Not corporate. Not hype."""


class AIService:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self.model = settings.OPENAI_MODEL

    async def align_week(
        self, plan: WeeklyPlan, tasks: list[Task]
    ) -> list[str]:
        task_lines = "\n".join(
            f"- {'[x]' if t.completed else '[ ]'} {t.title} ({t.energy_type.value})"
            for t in tasks
        )
        prompt = (
            f"Weekly intent: {plan.intent}\n\n"
            f"Current tasks:\n{task_lines or '(no tasks yet)'}"
        )
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": ALIGN_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_tokens=300,
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
        self, reflection: WeeklyReflection
    ) -> tuple[str, str]:
        prompt = (
            f"What moved the needle: {reflection.moved_needle or 'N/A'}\n"
            f"What drained energy: {reflection.drained_energy or 'N/A'}\n"
            f"What to stop doing: {reflection.stop_doing or 'N/A'}\n"
            f"What deserves more focus: {reflection.focus_next_week or 'N/A'}"
        )
        response = await self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": REFLECTION_SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            max_tokens=400,
            temperature=0.6,
        )
        content = response.choices[0].message.content or "{}"
        try:
            data = json.loads(content)
            return (
                data.get("summary", ""),
                data.get("focus_recommendation", ""),
            )
        except json.JSONDecodeError:
            return (content.strip(), "")


_ai_service: AIService | None = None


def get_ai_service() -> AIService:
    global _ai_service
    if _ai_service is None:
        _ai_service = AIService()
    return _ai_service
