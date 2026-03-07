FROM node:20-slim

RUN npm install -g pnpm

WORKDIR /openclaw

RUN git clone https://github.com/openclaw/openclaw.git . && \
    pnpm install && \
    pnpm build

COPY config/ /openclaw-config/
COPY agents/ /openclaw-agents/

CMD ["node", "packages/gateway/dist/index.js"]
