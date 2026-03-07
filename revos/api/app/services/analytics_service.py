import uuid
from datetime import date, datetime, time, timezone
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Invoice, Job, Payment


async def get_daily_summary(
    db: AsyncSession, business_id: uuid.UUID, target_date: date
) -> dict:
    day_start = datetime.combine(target_date, time.min, tzinfo=timezone.utc)
    day_end = datetime.combine(target_date, time.max, tzinfo=timezone.utc)

    # Jobs completed on this date
    jobs_result = await db.execute(
        select(func.count()).select_from(Job).where(
            Job.business_id == business_id,
            Job.status == "completed",
            Job.completed_at >= day_start,
            Job.completed_at <= day_end,
            Job.deleted_at.is_(None),
        )
    )
    jobs_completed = jobs_result.scalar() or 0

    # Revenue collected on this date
    revenue_result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), Decimal("0"))).where(
            Payment.business_id == business_id,
            Payment.paid_at >= day_start,
            Payment.paid_at <= day_end,
            Payment.deleted_at.is_(None),
        )
    )
    revenue_collected = revenue_result.scalar() or Decimal("0")

    # Overdue invoices
    now = datetime.now(timezone.utc)
    overdue_result = await db.execute(
        select(
            func.count(),
            func.coalesce(func.sum(Invoice.amount), Decimal("0")),
        ).where(
            Invoice.business_id == business_id,
            Invoice.status == "sent",
            Invoice.due_date < now,
            Invoice.deleted_at.is_(None),
        )
    )
    row = overdue_result.one()
    invoices_overdue = row[0] or 0
    total_overdue_amount = row[1] or Decimal("0")

    return {
        "jobs_completed": jobs_completed,
        "revenue_collected": revenue_collected,
        "invoices_overdue": invoices_overdue,
        "total_overdue_amount": total_overdue_amount,
    }


async def get_cash_flow_snapshot(db: AsyncSession, business_id: uuid.UUID) -> dict:
    now = datetime.now(timezone.utc)

    # Expected in: sum of sent invoices not yet overdue
    expected_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.amount), Decimal("0"))).where(
            Invoice.business_id == business_id,
            Invoice.status == "sent",
            Invoice.due_date >= now,
            Invoice.deleted_at.is_(None),
        )
    )
    expected_in = expected_result.scalar() or Decimal("0")

    # Bills due: sum of all sent invoices
    bills_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.amount), Decimal("0"))).where(
            Invoice.business_id == business_id,
            Invoice.status == "sent",
            Invoice.deleted_at.is_(None),
        )
    )
    bills_due = bills_result.scalar() or Decimal("0")

    # Overdue: sent invoices past due date
    overdue_result = await db.execute(
        select(func.coalesce(func.sum(Invoice.amount), Decimal("0"))).where(
            Invoice.business_id == business_id,
            Invoice.status == "sent",
            Invoice.due_date < now,
            Invoice.deleted_at.is_(None),
        )
    )
    overdue_amount = overdue_result.scalar() or Decimal("0")

    return {
        "expected_in": expected_in,
        "bills_due": bills_due,
        "overdue_amount": overdue_amount,
    }
