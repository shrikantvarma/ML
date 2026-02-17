from __future__ import annotations

import os

from dotenv import load_dotenv
from langchain_core.language_models import BaseChatModel

load_dotenv()


def get_llm(provider: str | None = None, model: str | None = None) -> BaseChatModel:
    """Return a configured LLM based on environment or explicit args."""
    provider = provider or os.getenv("LLM_PROVIDER", "openai")

    if provider == "openai":
        from langchain_openai import ChatOpenAI
        return ChatOpenAI(model=model or "gpt-4o-mini", temperature=0)

    if provider == "anthropic":
        from langchain_anthropic import ChatAnthropic
        return ChatAnthropic(model=model or "claude-sonnet-4-5-20250929", temperature=0)

    if provider == "ollama":
        from langchain_ollama import ChatOllama
        return ChatOllama(
            model=model or os.getenv("OLLAMA_MODEL", "llama3.1"),
            base_url=os.getenv("OLLAMA_BASE_URL", "http://localhost:11434"),
            temperature=0,
        )

    raise ValueError(f"Unsupported LLM provider: {provider}")
