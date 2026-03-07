from celery import Celery

from app.core.config import settings

celery_app = Celery(
    "revos",
    broker=settings.redis_url,
    backend=settings.redis_url,
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="America/New_York",
    enable_utc=True,
    task_track_started=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,
)

from app.workers.beat_schedule import CELERY_BEAT_SCHEDULE

celery_app.conf.beat_schedule = CELERY_BEAT_SCHEDULE

celery_app.autodiscover_tasks(["app.workers"])
