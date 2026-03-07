from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, select
from sqlalchemy.orm import selectinload

from app.core.database import async_session
from app.models import AutomationLog, Job, JobStatus
from app.workers.automations.base import BaseAutomation


class ReviewRequester(BaseAutomation):
    name = "review_requester"
    message_type = "review request"

    async def run(self, business_id: str) -> dict:
        now = datetime.now(UTC)
        yesterday_start = (now - timedelta(days=1)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        yesterday_end = yesterday_start + timedelta(days=1)

        review_requests_sent = 0
        jobs_reviewed = 0

        async with async_session() as db:
            # Query jobs completed yesterday
            result = await db.execute(
                select(Job)
                .options(selectinload(Job.customer))
                .where(
                    and_(
                        Job.business_id == business_id,
                        Job.status == JobStatus.completed,
                        Job.completed_at >= yesterday_start,
                        Job.completed_at < yesterday_end,
                        Job.deleted_at.is_(None),
                    )
                )
            )
            completed_jobs = result.scalars().all()
            jobs_reviewed = len(completed_jobs)

            for job in completed_jobs:
                # Check if review already requested
                existing_log = await db.execute(
                    select(AutomationLog).where(
                        and_(
                            AutomationLog.business_id == business_id,
                            AutomationLog.action_type == "review_request",
                            AutomationLog.target_id == job.id,
                        )
                    )
                )
                if existing_log.scalars().first() is not None:
                    continue

                context = {
                    "customer_name": job.customer.name,
                    "service_description": job.description or "the service",
                    "completed_date": str(job.completed_at),
                    "google_reviews_url": "{google_reviews_url}",
                }

                message = await self.generate_message(context, tone="friendly")

                await self.log_action(
                    db=db,
                    business_id=business_id,
                    action_type="review_request",
                    target_type="job",
                    target_id=job.id,
                    details={
                        "message": message,
                        "customer_name": job.customer.name,
                        "service_description": job.description or "the service",
                    },
                )
                review_requests_sent += 1

            await db.commit()

        return {
            "review_requests_sent": review_requests_sent,
            "jobs_reviewed": jobs_reviewed,
        }
