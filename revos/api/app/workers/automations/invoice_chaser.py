import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import async_session
from app.models import AutomationLog, Customer, Invoice, InvoiceStatus, Payment
from app.workers.automations.base import BaseAutomation


class InvoiceChaser(BaseAutomation):
    name = "invoice_chaser"
    message_type = "payment reminder"

    async def run(self, business_id: str) -> dict:
        now = datetime.now(UTC)
        invoices_processed = 0
        reminders_sent = 0
        total_overdue_amount = Decimal("0.00")

        async with async_session() as db:
            # Query overdue invoices
            result = await db.execute(
                select(Invoice)
                .options(selectinload(Invoice.customer), selectinload(Invoice.job))
                .where(
                    and_(
                        Invoice.business_id == business_id,
                        Invoice.status == InvoiceStatus.sent,
                        Invoice.due_date < now,
                        Invoice.deleted_at.is_(None),
                    )
                )
            )
            overdue_invoices = result.scalars().all()

            for invoice in overdue_invoices:
                invoices_processed += 1
                total_overdue_amount += invoice.amount
                days_overdue = (now - invoice.due_date).days

                # Check if reminder already sent today
                today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
                existing_log = await db.execute(
                    select(AutomationLog).where(
                        and_(
                            AutomationLog.business_id == business_id,
                            AutomationLog.action_type == "invoice_reminder",
                            AutomationLog.target_id == invoice.id,
                            AutomationLog.created_at >= today_start,
                        )
                    )
                )
                if existing_log.scalars().first() is not None:
                    continue

                # Get customer payment history
                payment_history = await self._get_payment_history(db, invoice.customer_id)

                # Determine tone
                if days_overdue <= 3:
                    tone = "friendly"
                elif days_overdue <= 7:
                    tone = "firm"
                else:
                    tone = "final_notice"

                customer: Customer = invoice.customer
                context = {
                    "customer_name": customer.name,
                    "invoice_amount": str(invoice.amount),
                    "days_overdue": days_overdue,
                    "due_date": str(invoice.due_date),
                    "service_description": invoice.job.description if invoice.job else "services rendered",
                    "payment_history": payment_history,
                }

                message = await self.generate_message(context, tone=tone)

                await self.log_action(
                    db=db,
                    business_id=business_id,
                    action_type="invoice_reminder",
                    target_type="invoice",
                    target_id=invoice.id,
                    details={
                        "days_overdue": days_overdue,
                        "tone": tone,
                        "message": message,
                        "amount": str(invoice.amount),
                        "customer_name": customer.name,
                    },
                )
                reminders_sent += 1

            await db.commit()

        return {
            "invoices_processed": invoices_processed,
            "reminders_sent": reminders_sent,
            "total_overdue_amount": str(total_overdue_amount),
        }

    async def _get_payment_history(
        self, db: AsyncSession, customer_id: uuid.UUID
    ) -> dict:
        """Look up customer payment history."""
        # Total invoices for this customer
        total_invoices_result = await db.execute(
            select(func.count(Invoice.id)).where(
                and_(
                    Invoice.customer_id == customer_id,
                    Invoice.deleted_at.is_(None),
                )
            )
        )
        total_invoices = total_invoices_result.scalar() or 0

        # Paid invoices and average days to pay
        paid_invoices_result = await db.execute(
            select(Invoice).where(
                and_(
                    Invoice.customer_id == customer_id,
                    Invoice.status == InvoiceStatus.paid,
                    Invoice.deleted_at.is_(None),
                )
            )
        )
        paid_invoices = paid_invoices_result.scalars().all()

        avg_days_to_pay = 0
        late_payments = 0
        if paid_invoices:
            days_to_pay_list: list[int] = []
            for inv in paid_invoices:
                if inv.paid_at and inv.sent_at:
                    days = (inv.paid_at - inv.sent_at).days
                    days_to_pay_list.append(days)
                if inv.paid_at and inv.due_date and inv.paid_at > inv.due_date:
                    late_payments += 1
            if days_to_pay_list:
                avg_days_to_pay = sum(days_to_pay_list) // len(days_to_pay_list)

        return {
            "total_invoices": total_invoices,
            "paid_invoices": len(paid_invoices),
            "avg_days_to_pay": avg_days_to_pay,
            "late_payments": late_payments,
        }
