import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import get_db, verify_api_key
from app.models import Business
from app.schemas.business import BusinessCreate, BusinessResponse, BusinessUpdate

router = APIRouter(prefix="/businesses", tags=["businesses"], dependencies=[Depends(verify_api_key)])


@router.post("/", response_model=BusinessResponse, status_code=201)
async def create_business(data: BusinessCreate, db: AsyncSession = Depends(get_db)) -> Business:
    business = Business(**data.model_dump())
    db.add(business)
    await db.commit()
    await db.refresh(business)
    return business


@router.get("/", response_model=list[BusinessResponse])
async def list_businesses(db: AsyncSession = Depends(get_db)) -> list[Business]:
    result = await db.execute(select(Business).where(Business.deleted_at.is_(None)))
    return list(result.scalars().all())


@router.get("/{business_id}", response_model=BusinessResponse)
async def get_business(business_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> Business:
    result = await db.execute(
        select(Business).where(Business.id == business_id, Business.deleted_at.is_(None))
    )
    business = result.scalar_one_or_none()
    if not business:
        raise HTTPException(status_code=404, detail="Business not found")
    return business


@router.patch("/{business_id}", response_model=BusinessResponse)
async def update_business(
    business_id: uuid.UUID, data: BusinessUpdate, db: AsyncSession = Depends(get_db)
) -> Business:
    result = await db.execute(
        select(Business).where(Business.id == business_id, Business.deleted_at.is_(None))
    )
    business = result.scalar_one_or_none()
    if not business:
        raise HTTPException(status_code=404, detail="Business not found")
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(business, field, value)
    await db.commit()
    await db.refresh(business)
    return business
