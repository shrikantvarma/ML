import os
from unittest.mock import patch

from agentdesk.llm.provider import get_llm


@patch.dict(os.environ, {"LLM_PROVIDER": "openai", "OPENAI_API_KEY": "sk-test"})
def test_get_llm_openai():
    llm = get_llm()
    assert llm is not None
    assert "openai" in type(llm).__module__.lower()


@patch.dict(os.environ, {"LLM_PROVIDER": "anthropic", "ANTHROPIC_API_KEY": "sk-ant-test"})
def test_get_llm_anthropic():
    llm = get_llm()
    assert llm is not None
    assert "anthropic" in type(llm).__module__.lower()


def test_get_llm_invalid_provider():
    import pytest
    with patch.dict(os.environ, {"LLM_PROVIDER": "invalid"}):
        with pytest.raises(ValueError, match="Unsupported LLM provider"):
            get_llm()
