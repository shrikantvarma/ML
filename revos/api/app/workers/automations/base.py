import json
import uuid

import anthropic
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import AutomationLog, AutomationStatus

client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)


class BaseAutomation:
    name: str = "base"
    message_type: str = "general"

    async def run(self, business_id: str) -> dict:
        """Override in subclass. Returns a summary dict."""
        raise NotImplementedError

    async def generate_message(self, context: dict, tone: str = "friendly") -> str:
        """Use Claude API to generate a customer-facing message."""
        response = await client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=300,
            system=(
                "You are RevOS, an AI assistant for home service businesses. "
                "Generate a short, professional message for a customer. "
                "Be concise — SMS/WhatsApp messages should be 2-3 sentences max."
            ),
            messages=[
                {
                    "role": "user",
                    "content": (
                        f"Generate a {tone} {self.message_type} message.\n\n"
                        f"Context:\n{json.dumps(context, indent=2, default=str)}"
                    ),
                }
            ],
        )
        return response.content[0].text

    async def log_action(
        self,
        db: AsyncSession,
        business_id: str,
        action_type: str,
        target_type: str,
        target_id: uuid.UUID,
        details: dict,
        status: AutomationStatus = AutomationStatus.success,
    ) -> AutomationLog:
        """Log automation action to AutomationLog table."""
        log = AutomationLog(
            business_id=uuid.UUID(business_id) if isinstance(business_id, str) else business_id,
            action_type=action_type,
            target_type=target_type,
            target_id=target_id,
            details=details,
            status=status,
        )
        db.add(log)
        await db.flush()
        return log
