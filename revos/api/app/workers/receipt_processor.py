import json

import anthropic

from app.core.config import settings


async def process_receipt_image(image_url: str) -> dict:
    """Extract receipt data using Claude Vision."""
    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

    response = await client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {"type": "url", "url": image_url},
                    },
                    {
                        "type": "text",
                        "text": (
                            "Extract the following from this receipt: vendor_name, "
                            "total_amount (as a number), date (YYYY-MM-DD format), "
                            "line_items (list of items with description and amount). "
                            "Return as JSON only, no other text."
                        ),
                    },
                ],
            }
        ],
    )

    return json.loads(response.content[0].text)
