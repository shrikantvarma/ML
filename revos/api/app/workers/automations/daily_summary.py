import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from sqlalchemy import and_, func, select
from sqlalchemy.orm import selectinload

from app.core.database import async_session
from app.models import (
    AutomationLog,
    Invoice,
    InvoiceStatus,
    Job,
    JobStatus,
    Payment,
)
from app.workers.automations.base import BaseAutomation


class DailySummary(BaseAutomation):
    name = "daily_summary"
    message_type = "daily business summary"

    async def run(self, business_id: str) -> dict:
        now = datetime.now(UTC)
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        today_end = today_start + timedelta(days=1)
        tomorrow_start = today_end
        tomorrow_end = tomorrow_start + timedelta(days=1)

        async with async_session() as db:
            # Jobs completed today
            completed_jobs_result = await db.execute(
                select(Job)
                .options(selectinload(Job.customer))
                .where(
                    and_(
                        Job.business_id == business_id,
                        Job.status == JobStatus.completed,
                        Job.completed_at >= today_start,
                        Job.completed_at < today_end,
                        Job.deleted_at.is_(None),
                    )
                )
            )
            completed_jobs = completed_jobs_result.scalars().all()

            # Payments received today
            payments_result = await db.execute(
                select(Payment).where(
                    and_(
                        Payment.business_id == business_id,
                        Payment.paid_at >= today_start,
                        Payment.paid_at < today_end,
                    )
                )
            )
            payments_today = payments_result.scalars().all()
            payments_total = sum((p.amount for p in payments_today), Decimal("0.00"))

            # Invoices sent today
            invoices_sent_result = await db.execute(
                select(Invoice).where(
                    and_(
                        Invoice.business_id == business_id,
                        Invoice.sent_at >= today_start,
                        Invoice.sent_at < today_end,
                        Invoice.deleted_at.is_(None),
                    )
                )
            )
            invoices_sent = invoices_sent_result.scalars().all()
            invoices_sent_total = sum(
                (i.amount for i in invoices_sent), Decimal("0.00")
            )

            # Current overdue invoices
            overdue_result = await db.execute(
                select(Invoice).where(
                    and_(
                        Invoice.business_id == business_id,
                        Invoice.status == InvoiceStatus.sent,
                        Invoice.due_date < now,
                        Invoice.deleted_at.is_(None),
                    )
                )
            )
            overdue_invoices = overdue_result.scalars().all()
            overdue_total = sum(
                (i.amount for i in overdue_invoices), Decimal("0.00")
            )

            # Jobs scheduled for tomorrow
            tomorrow_jobs_result = await db.execute(
                select(Job)
                .options(selectinload(Job.customer), selectinload(Job.technician))
                .where(
                    and_(
                        Job.business_id == business_id,
                        Job.status == JobStatus.scheduled,
                        Job.scheduled_at >= tomorrow_start,
                        Job.scheduled_at < tomorrow_end,
                        Job.deleted_at.is_(None),
                    )
                )
            )
            tomorrow_jobs = tomorrow_jobs_result.scalars().all()

            raw_data = {
                "jobs_completed_today": len(completed_jobs),
                "jobs_completed_list": [
                    {
                        "description": j.description,
                        "customer": j.customer.name,
                    }
                    for j in completed_jobs
                ],
                "payments_received_count": len(payments_today),
                "payments_received_total": str(payments_total),
                "invoices_sent_count": len(invoices_sent),
                "invoices_sent_total": str(invoices_sent_total),
                "overdue_invoices_count": len(overdue_invoices),
                "overdue_invoices_total": str(overdue_total),
                "jobs_scheduled_tomorrow": len(tomorrow_jobs),
                "jobs_tomorrow_list": [
                    {
                        "description": j.description,
                        "customer": j.customer.name,
                        "technician": j.technician.name if j.technician else "unassigned",
                        "scheduled_at": str(j.scheduled_at),
                    }
                    for j in tomorrow_jobs
                ],
            }

            # Generate natural language summary
            context = {
                "date": str(now.date()),
                **raw_data,
            }
            summary_text = await self.generate_message(context, tone="friendly")

            # Log the action -- use a deterministic target_id based on date
            date_based_id = uuid.uuid5(
                uuid.NAMESPACE_DNS,
                f"daily_summary_{business_id}_{now.date().isoformat()}",
            )

            await self.log_action(
                db=db,
                business_id=business_id,
                action_type="daily_summary",
                target_type="business",
                target_id=date_based_id,
                details={"summary": summary_text, **raw_data},
            )
            await db.commit()

        return {
            "summary": summary_text,
            "data": raw_data,
        }
