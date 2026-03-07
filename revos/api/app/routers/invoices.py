import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_db, verify_api_key
from app.models import Invoice
from app.schemas.invoice import InvoiceCreate, InvoiceResponse, InvoiceUpdate
from app.services.invoice_service import get_overdue_invoices

router = APIRouter(prefix="/invoices", tags=["invoices"], dependencies=[Depends(verify_api_key)])


@router.post("/", response_model=InvoiceResponse, status_code=201)
async def create_invoice(data: InvoiceCreate, db: AsyncSession = Depends(get_db)) -> Invoice:
    invoice = Invoice(**data.model_dump())
    db.add(invoice)
    await db.commit()
    await db.refresh(invoice)
    return invoice


@router.get("/overdue", response_model=list[InvoiceResponse])
async def list_overdue_invoices(
    business_id: uuid.UUID = Query(...),
    db: AsyncSession = Depends(get_db),
) -> list[Invoice]:
    return await get_overdue_invoices(db, business_id)


@router.get("/", response_model=list[InvoiceResponse])
async def list_invoices(
    business_id: uuid.UUID | None = Query(None),
    status: str | None = Query(None),
    customer_id: uuid.UUID | None = Query(None),
    db: AsyncSession = Depends(get_db),
) -> list[Invoice]:
    stmt = select(Invoice).where(Invoice.deleted_at.is_(None))
    if business_id:
        stmt = stmt.where(Invoice.business_id == business_id)
    if status:
        stmt = stmt.where(Invoice.status == status)
    if customer_id:
        stmt = stmt.where(Invoice.customer_id == customer_id)
    result = await db.execute(stmt)
    return list(result.scalars().all())


@router.get("/{invoice_id}", response_model=InvoiceResponse)
async def get_invoice(invoice_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> Invoice:
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.deleted_at.is_(None))
    )
    invoice = result.scalar_one_or_none()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    return invoice


@router.patch("/{invoice_id}", response_model=InvoiceResponse)
async def update_invoice(
    invoice_id: uuid.UUID, data: InvoiceUpdate, db: AsyncSession = Depends(get_db)
) -> Invoice:
    result = await db.execute(
        select(Invoice).where(Invoice.id == invoice_id, Invoice.deleted_at.is_(None))
    )
    invoice = result.scalar_one_or_none()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(invoice, field, value)
    await db.commit()
    await db.refresh(invoice)
    return invoice
