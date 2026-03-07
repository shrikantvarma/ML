import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_db, verify_api_key
from app.models import Quote
from app.schemas.quote import QuoteCreate, QuoteResponse, QuoteUpdate

router = APIRouter(prefix="/quotes", tags=["quotes"], dependencies=[Depends(verify_api_key)])


@router.post("/", response_model=QuoteResponse, status_code=201)
async def create_quote(data: QuoteCreate, db: AsyncSession = Depends(get_db)) -> Quote:
    quote = Quote(**data.model_dump())
    db.add(quote)
    await db.commit()
    await db.refresh(quote)
    return quote


@router.get("/", response_model=list[QuoteResponse])
async def list_quotes(
    business_id: uuid.UUID | None = Query(None),
    status: str | None = Query(None),
    db: AsyncSession = Depends(get_db),
) -> list[Quote]:
    stmt = select(Quote).where(Quote.deleted_at.is_(None))
    if business_id:
        stmt = stmt.where(Quote.business_id == business_id)
    if status:
        stmt = stmt.where(Quote.status == status)
    result = await db.execute(stmt)
    return list(result.scalars().all())


@router.get("/{quote_id}", response_model=QuoteResponse)
async def get_quote(quote_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> Quote:
    result = await db.execute(
        select(Quote).where(Quote.id == quote_id, Quote.deleted_at.is_(None))
    )
    quote = result.scalar_one_or_none()
    if not quote:
        raise HTTPException(status_code=404, detail="Quote not found")
    return quote


@router.patch("/{quote_id}", response_model=QuoteResponse)
async def update_quote(
    quote_id: uuid.UUID, data: QuoteUpdate, db: AsyncSession = Depends(get_db)
) -> Quote:
    result = await db.execute(
        select(Quote).where(Quote.id == quote_id, Quote.deleted_at.is_(None))
    )
    quote = result.scalar_one_or_none()
    if not quote:
        raise HTTPException(status_code=404, detail="Quote not found")
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(quote, field, value)
    await db.commit()
    await db.refresh(quote)
    return quote
