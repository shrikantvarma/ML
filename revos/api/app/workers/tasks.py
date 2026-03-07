import asyncio
import logging
import uuid
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import select

from app.core.database import async_session
from app.models import Business, Expense
from app.workers.celery_app import celery_app
from app.workers.receipt_processor import process_receipt_image

logger = logging.getLogger(__name__)


def _get_automation(name: str):
    """Import an automation class by name, returning None if not yet available."""
    try:
        module = __import__(
            f"app.workers.automations.{name}",
            fromlist=[name],
        )
        class_name = "".join(part.capitalize() for part in name.split("_"))
        return getattr(module, class_name)
    except (ImportError, AttributeError):
        logger.warning("Automation %s not available yet", name)
        return None


async def _get_all_active_business_ids() -> list[str]:
    """Return IDs of all non-deleted businesses."""
    async with async_session() as session:
        result = await session.execute(
            select(Business.id).where(Business.deleted_at.is_(None))
        )
        return [str(row[0]) for row in result.all()]


# ---------------------------------------------------------------------------
# Individual automation tasks
# ---------------------------------------------------------------------------


@celery_app.task(bind=True, name="app.workers.tasks.run_invoice_chaser")
def run_invoice_chaser(self, business_id: str) -> dict:
    """Chase overdue invoices for a single business."""
    klass = _get_automation("invoice_chaser")
    if klass is None:
        return {"status": "skipped", "reason": "automation not available"}
    try:
        result = asyncio.run(klass().run(business_id))
        return {"status": "ok", "business_id": business_id, "result": result}
    except Exception as exc:
        logger.exception("invoice_chaser failed for %s", business_id)
        return {"status": "error", "business_id": business_id, "error": str(exc)}


@celery_app.task(bind=True, name="app.workers.tasks.run_appointment_reminder")
def run_appointment_reminder(self, business_id: str) -> dict:
    """Send appointment reminders for a single business."""
    klass = _get_automation("appointment_reminder")
    if klass is None:
        return {"status": "skipped", "reason": "automation not available"}
    try:
        result = asyncio.run(klass().run(business_id))
        return {"status": "ok", "business_id": business_id, "result": result}
    except Exception as exc:
        logger.exception("appointment_reminder failed for %s", business_id)
        return {"status": "error", "business_id": business_id, "error": str(exc)}


@celery_app.task(bind=True, name="app.workers.tasks.run_review_requester")
def run_review_requester(self, business_id: str) -> dict:
    """Request reviews for completed jobs for a single business."""
    klass = _get_automation("review_requester")
    if klass is None:
        return {"status": "skipped", "reason": "automation not available"}
    try:
        result = asyncio.run(klass().run(business_id))
        return {"status": "ok", "business_id": business_id, "result": result}
    except Exception as exc:
        logger.exception("review_requester failed for %s", business_id)
        return {"status": "error", "business_id": business_id, "error": str(exc)}


@celery_app.task(bind=True, name="app.workers.tasks.run_daily_summary")
def run_daily_summary(self, business_id: str) -> dict:
    """Generate and send a daily summary for a single business."""
    klass = _get_automation("daily_summary")
    if klass is None:
        return {"status": "skipped", "reason": "automation not available"}
    try:
        result = asyncio.run(klass().run(business_id))
        return {"status": "ok", "business_id": business_id, "result": result}
    except Exception as exc:
        logger.exception("daily_summary failed for %s", business_id)
        return {"status": "error", "business_id": business_id, "error": str(exc)}


@celery_app.task(bind=True, name="app.workers.tasks.run_quote_follow_up")
def run_quote_follow_up(self, business_id: str) -> dict:
    """Follow up on outstanding quotes for a single business."""
    klass = _get_automation("quote_follow_up")
    if klass is None:
        return {"status": "skipped", "reason": "automation not available"}
    try:
        result = asyncio.run(klass().run(business_id))
        return {"status": "ok", "business_id": business_id, "result": result}
    except Exception as exc:
        logger.exception("quote_follow_up failed for %s", business_id)
        return {"status": "error", "business_id": business_id, "error": str(exc)}


@celery_app.task(bind=True, name="app.workers.tasks.run_all_automations")
def run_all_automations(self, business_id: str) -> dict:
    """Run all automations sequentially for a single business."""
    results: dict[str, dict] = {}
    for task_name in [
        "invoice_chaser",
        "appointment_reminder",
        "review_requester",
        "daily_summary",
        "quote_follow_up",
    ]:
        klass = _get_automation(task_name)
        if klass is None:
            results[task_name] = {"status": "skipped", "reason": "not available"}
            continue
        try:
            result = asyncio.run(klass().run(business_id))
            results[task_name] = {"status": "ok", "result": result}
        except Exception as exc:
            logger.exception("%s failed for %s", task_name, business_id)
            results[task_name] = {"status": "error", "error": str(exc)}
    return {"status": "ok", "business_id": business_id, "results": results}


# ---------------------------------------------------------------------------
# Receipt processing
# ---------------------------------------------------------------------------


@celery_app.task(bind=True, name="app.workers.tasks.process_receipt")
def process_receipt(self, business_id: str, job_id: str, image_url: str) -> dict:
    """OCR a receipt photo and create an Expense record."""
    try:
        extracted = asyncio.run(process_receipt_image(image_url))

        async def _save_expense() -> str:
            async with async_session() as session:
                expense = Expense(
                    business_id=uuid.UUID(business_id),
                    job_id=uuid.UUID(job_id),
                    description=extracted.get("vendor_name", "Receipt expense"),
                    amount=Decimal(str(extracted.get("total_amount", 0))),
                    category="receipt",
                    receipt_url=image_url,
                    incurred_at=datetime.strptime(
                        extracted.get("date", datetime.now(timezone.utc).strftime("%Y-%m-%d")),
                        "%Y-%m-%d",
                    ).replace(tzinfo=timezone.utc),
                )
                session.add(expense)
                await session.commit()
                await session.refresh(expense)
                return str(expense.id)

        expense_id = asyncio.run(_save_expense())
        return {
            "status": "ok",
            "business_id": business_id,
            "job_id": job_id,
            "expense_id": expense_id,
            "extracted": extracted,
        }
    except Exception as exc:
        logger.exception("process_receipt failed for job %s", job_id)
        return {
            "status": "error",
            "business_id": business_id,
            "job_id": job_id,
            "error": str(exc),
        }


# ---------------------------------------------------------------------------
# QuickBooks sync stub
# ---------------------------------------------------------------------------


@celery_app.task(bind=True, name="app.workers.tasks.sync_quickbooks")
def sync_quickbooks(self, business_id: str) -> dict:
    """Stub task for QuickBooks sync."""
    logger.info("QuickBooks sync not yet implemented for business %s", business_id)
    return {
        "status": "skipped",
        "business_id": business_id,
        "reason": "QuickBooks sync not yet implemented",
    }


# ---------------------------------------------------------------------------
# "Run for all businesses" tasks (used by beat schedule)
# ---------------------------------------------------------------------------


@celery_app.task(bind=True, name="app.workers.tasks.run_invoice_chaser_all")
def run_invoice_chaser_all(self) -> dict:
    """Chase overdue invoices for all active businesses."""
    business_ids = asyncio.run(_get_all_active_business_ids())
    for bid in business_ids:
        run_invoice_chaser.delay(bid)
    return {"status": "ok", "dispatched": len(business_ids)}


@celery_app.task(bind=True, name="app.workers.tasks.run_appointment_reminder_all")
def run_appointment_reminder_all(self) -> dict:
    """Send appointment reminders for all active businesses."""
    business_ids = asyncio.run(_get_all_active_business_ids())
    for bid in business_ids:
        run_appointment_reminder.delay(bid)
    return {"status": "ok", "dispatched": len(business_ids)}


@celery_app.task(bind=True, name="app.workers.tasks.run_review_requester_all")
def run_review_requester_all(self) -> dict:
    """Request reviews for all active businesses."""
    business_ids = asyncio.run(_get_all_active_business_ids())
    for bid in business_ids:
        run_review_requester.delay(bid)
    return {"status": "ok", "dispatched": len(business_ids)}


@celery_app.task(bind=True, name="app.workers.tasks.run_daily_summary_all")
def run_daily_summary_all(self) -> dict:
    """Generate daily summaries for all active businesses."""
    business_ids = asyncio.run(_get_all_active_business_ids())
    for bid in business_ids:
        run_daily_summary.delay(bid)
    return {"status": "ok", "dispatched": len(business_ids)}


@celery_app.task(bind=True, name="app.workers.tasks.run_quote_follow_up_all")
def run_quote_follow_up_all(self) -> dict:
    """Follow up on quotes for all active businesses."""
    business_ids = asyncio.run(_get_all_active_business_ids())
    for bid in business_ids:
        run_quote_follow_up.delay(bid)
    return {"status": "ok", "dispatched": len(business_ids)}
