import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_db, verify_api_key
from app.models import Payment
from app.schemas.payment import PaymentCreate, PaymentResponse

router = APIRouter(prefix="/payments", tags=["payments"], dependencies=[Depends(verify_api_key)])


@router.post("/", response_model=PaymentResponse, status_code=201)
async def create_payment(data: PaymentCreate, db: AsyncSession = Depends(get_db)) -> Payment:
    payment = Payment(**data.model_dump())
    db.add(payment)
    await db.commit()
    await db.refresh(payment)
    return payment


@router.get("/", response_model=list[PaymentResponse])
async def list_payments(
    business_id: uuid.UUID | None = Query(None),
    customer_id: uuid.UUID | None = Query(None),
    invoice_id: uuid.UUID | None = Query(None),
    db: AsyncSession = Depends(get_db),
) -> list[Payment]:
    stmt = select(Payment).where(Payment.deleted_at.is_(None))
    if business_id:
        stmt = stmt.where(Payment.business_id == business_id)
    if customer_id:
        stmt = stmt.where(Payment.customer_id == customer_id)
    if invoice_id:
        stmt = stmt.where(Payment.invoice_id == invoice_id)
    result = await db.execute(stmt)
    return list(result.scalars().all())
