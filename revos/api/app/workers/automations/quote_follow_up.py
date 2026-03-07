from datetime import UTC, datetime

from sqlalchemy import and_, select
from sqlalchemy.orm import selectinload

from app.core.database import async_session
from app.models import AutomationLog, Quote, QuoteStatus
from app.workers.automations.base import BaseAutomation

FOLLOW_UP_DAYS = {2, 5, 10}

FOLLOW_UP_TONES: dict[int, str] = {
    2: "friendly",
    5: "friendly",
    10: "firm",
}

FOLLOW_UP_HINTS: dict[int, str] = {
    2: "Just checking in on the quote...",
    5: "Wanted to follow up -- happy to adjust scope if needed...",
    10: "Final follow-up -- the quote expires soon...",
}


class QuoteFollowUp(BaseAutomation):
    name = "quote_follow_up"
    message_type = "quote follow-up"

    async def run(self, business_id: str) -> dict:
        now = datetime.now(UTC)
        follow_ups_sent = 0
        quotes_pending = 0

        async with async_session() as db:
            result = await db.execute(
                select(Quote)
                .options(selectinload(Quote.customer))
                .where(
                    and_(
                        Quote.business_id == business_id,
                        Quote.status == QuoteStatus.sent,
                        Quote.deleted_at.is_(None),
                    )
                )
            )
            sent_quotes = result.scalars().all()
            quotes_pending = len(sent_quotes)

            for quote in sent_quotes:
                days_since_sent = (now - quote.created_at).days

                if days_since_sent not in FOLLOW_UP_DAYS:
                    continue

                # Check if follow-up already sent for this interval
                action_type = f"quote_follow_up_day_{days_since_sent}"
                existing_log = await db.execute(
                    select(AutomationLog).where(
                        and_(
                            AutomationLog.business_id == business_id,
                            AutomationLog.action_type == action_type,
                            AutomationLog.target_id == quote.id,
                        )
                    )
                )
                if existing_log.scalars().first() is not None:
                    continue

                tone = FOLLOW_UP_TONES[days_since_sent]
                context = {
                    "customer_name": quote.customer.name,
                    "quote_description": quote.description or "the quoted work",
                    "quote_amount": str(quote.total_amount) if quote.total_amount else "as quoted",
                    "days_since_sent": days_since_sent,
                    "follow_up_hint": FOLLOW_UP_HINTS[days_since_sent],
                    "valid_until": str(quote.valid_until) if quote.valid_until else None,
                }

                message = await self.generate_message(context, tone=tone)

                await self.log_action(
                    db=db,
                    business_id=business_id,
                    action_type=action_type,
                    target_type="quote",
                    target_id=quote.id,
                    details={
                        "message": message,
                        "days_since_sent": days_since_sent,
                        "customer_name": quote.customer.name,
                        "quote_amount": str(quote.total_amount) if quote.total_amount else None,
                    },
                )
                follow_ups_sent += 1

            await db.commit()

        return {
            "follow_ups_sent": follow_ups_sent,
            "quotes_pending": quotes_pending,
        }
