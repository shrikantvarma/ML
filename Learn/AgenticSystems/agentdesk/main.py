from fastapi import FastAPI

from agentdesk.api.routes import router
from agentdesk.tracing.tracer import setup_langsmith_tracing

setup_langsmith_tracing()

app = FastAPI(
    title="AgentDesk",
    description="Agentic e-commerce customer support system",
    version="0.1.0",
)

app.include_router(router)


@app.get("/health")
def health():
    return {"status": "ok", "service": "agentdesk"}
