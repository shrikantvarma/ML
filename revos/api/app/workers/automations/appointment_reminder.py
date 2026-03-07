from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, select
from sqlalchemy.orm import selectinload

from app.core.database import async_session
from app.models import AutomationLog, Job, JobStatus
from app.workers.automations.base import BaseAutomation


class AppointmentReminder(BaseAutomation):
    name = "appointment_reminder"
    message_type = "appointment reminder"

    async def run(self, business_id: str) -> dict:
        now = datetime.now(UTC)
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        tomorrow_start = today_start + timedelta(days=1)
        tomorrow_end = tomorrow_start + timedelta(days=1)
        two_hours_from_now = now + timedelta(hours=2)

        reminders_sent = 0
        jobs_tomorrow = 0
        jobs_today = 0

        async with async_session() as db:
            # Query all scheduled jobs for today and tomorrow
            result = await db.execute(
                select(Job)
                .options(
                    selectinload(Job.customer),
                    selectinload(Job.technician),
                )
                .where(
                    and_(
                        Job.business_id == business_id,
                        Job.status == JobStatus.scheduled,
                        Job.scheduled_at >= today_start,
                        Job.scheduled_at < tomorrow_end,
                        Job.deleted_at.is_(None),
                    )
                )
            )
            scheduled_jobs = result.scalars().all()

            for job in scheduled_jobs:
                if job.scheduled_at is None:
                    continue

                is_tomorrow = tomorrow_start <= job.scheduled_at < tomorrow_end
                is_today_soon = today_start <= job.scheduled_at <= two_hours_from_now and job.scheduled_at >= now

                if is_tomorrow:
                    jobs_tomorrow += 1
                    action_type = "night_before_reminder"
                elif is_today_soon:
                    jobs_today += 1
                    action_type = "on_the_way_reminder"
                else:
                    continue

                # Check if reminder already sent today for this action type
                existing_log = await db.execute(
                    select(AutomationLog).where(
                        and_(
                            AutomationLog.business_id == business_id,
                            AutomationLog.action_type == action_type,
                            AutomationLog.target_id == job.id,
                            AutomationLog.created_at >= today_start,
                        )
                    )
                )
                if existing_log.scalars().first() is not None:
                    continue

                technician_name = job.technician.name if job.technician else "our technician"
                context = {
                    "customer_name": job.customer.name,
                    "service_description": job.description or "scheduled service",
                    "scheduled_time": str(job.scheduled_at),
                    "technician_name": technician_name,
                    "reminder_type": "night_before" if is_tomorrow else "on_the_way",
                    "address": job.address or "",
                }

                tone = "friendly"
                message = await self.generate_message(context, tone=tone)

                await self.log_action(
                    db=db,
                    business_id=business_id,
                    action_type=action_type,
                    target_type="job",
                    target_id=job.id,
                    details={
                        "message": message,
                        "customer_name": job.customer.name,
                        "scheduled_at": str(job.scheduled_at),
                        "reminder_type": action_type,
                    },
                )
                reminders_sent += 1

            await db.commit()

        return {
            "reminders_sent": reminders_sent,
            "jobs_tomorrow": jobs_tomorrow,
            "jobs_today": jobs_today,
        }
