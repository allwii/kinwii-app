from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes_ai import router as ai_router
from app.api.routes_auth import router as auth_router
from app.api.routes_analytics import router as analytics_router
from app.api.routes_coach import router as coach_router
from app.api.routes_notifications import router as notifications_router
from app.api.routes_subscription import router as subscription_router
from app.api.routes_daily import router as daily_router
from app.api.routes_goals import router as goals_router
from app.api.routes_mission import router as mission_router
from app.api.routes_reflection import router as reflection_router
from app.api.routes_tasks import router as tasks_router
from app.api.routes_week import router as week_router

app = FastAPI(title="Kinwii API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(mission_router)
app.include_router(goals_router)
app.include_router(week_router)
app.include_router(tasks_router)
app.include_router(daily_router)
app.include_router(reflection_router)
app.include_router(ai_router)
app.include_router(analytics_router)
app.include_router(coach_router)
app.include_router(notifications_router)
app.include_router(subscription_router)


@app.get("/health")
async def health_check():
    return {"status": "ok"}
