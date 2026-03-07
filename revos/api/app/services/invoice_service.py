import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Invoice, Payment
from app.schemas.payment import PaymentCreate


async def get_overdue_invoices(db: AsyncSession, business_id: uuid.UUID) -> list[Invoice]:
    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(Invoice).where(
            Invoice.business_id == business_id,
            Invoice.status == "sent",
            Invoice.due_date < now,
            Invoice.deleted_at.is_(None),
        )
    )
    return list(result.scalars().all())


async def mark_invoice_paid(
    db: AsyncSession, invoice_id: uuid.UUID, payment_data: PaymentCreate
) -> Invoice:
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.deleted_at.is_(None))
    )
    invoice = result.scalar_one_or_none()
    if not invoice:
        raise ValueError(f"Invoice {invoice_id} not found")

    payment = Payment(**payment_data.model_dump())
    db.add(payment)

    invoice.status = "paid"
    invoice.paid_at = payment_data.paid_at

    await db.commit()
    await db.refresh(invoice)
    return invoice
