# syntax=docker/dockerfile:1
# The options agent as a container. One stage on purpose: operator scripts (db:status, reconcile,
# report:performance) run through tsx, so the dev dependencies stay in the image.
FROM node:22-slim

ENV NODE_ENV=production \
    UI=off

WORKDIR /app

COPY package.json package-lock.json ./
# NODE_ENV=production would skip devDependencies (tsc, tsx), which the build and the scripts need.
RUN NODE_ENV=development npm ci

COPY tsconfig.json tsconfig.typecheck.json ./
COPY src ./src
COPY scripts ./scripts
COPY config.paper.yml ./
RUN npm run build

# The JSONL journal lives here; mount a volume so it survives restarts.
RUN mkdir -p /app/data/journal && chown -R node:node /app/data
USER node

# SIGTERM starts the agent's graceful shutdown (exits are bounded by its shutdown timeout).
STOPSIGNAL SIGTERM

# No inbound ports: the agent only makes outbound connections.
CMD ["node", "dist/index.js"]
