# =============================================================================
# STAGE 1: Dependencies - Install and cache workspace dependencies
# =============================================================================
FROM oven/bun:1.3.4 AS deps

WORKDIR /app

# Copy workspace configuration
COPY package.json bun.lock ./

# Copy package.json files for workspace packages needed by app and portal
COPY packages/auth/package.json ./packages/auth/
COPY packages/billing/package.json ./packages/billing/
COPY packages/company/package.json ./packages/company/
COPY packages/db/package.json ./packages/db/
COPY packages/kv/package.json ./packages/kv/
COPY packages/ui/package.json ./packages/ui/
COPY packages/email/package.json ./packages/email/
COPY packages/integration-platform/package.json ./packages/integration-platform/
COPY packages/integrations/package.json ./packages/integrations/
COPY packages/utils/package.json ./packages/utils/
COPY packages/tsconfig/package.json ./packages/tsconfig/
COPY packages/analytics/package.json ./packages/analytics/

# Copy app package.json files
COPY apps/app/package.json ./apps/app/
COPY apps/portal/package.json ./apps/portal/

# Install all dependencies
RUN PRISMA_SKIP_POSTINSTALL_GENERATE=true bun install --ignore-scripts --linker hoisted

# =============================================================================
# STAGE 2: Migrator / Seeder - Local Prisma schema and workspace deps
# =============================================================================
FROM deps AS migrator

WORKDIR /app

COPY packages/db ./packages/db

# Run migrations against the local multi-file schema.
CMD ["sh", "-lc", "cd packages/db && bunx prisma migrate deploy --schema=prisma/schema"]

# =============================================================================
# STAGE 3: App Builder
# =============================================================================
FROM deps AS app-builder

WORKDIR /app
ARG DATABASE_URL

# Copy all source code needed for build
COPY packages ./packages
COPY apps/app ./apps/app

# Bring in node_modules for build and prisma prebuild
COPY --from=deps /app/node_modules ./node_modules

# Pre-combine schemas and generate the Prisma client into
# node_modules/@prisma/client. The deps stage ran `bun install` with
# `--ignore-scripts` so packages/db's postinstall was skipped; we run
# it explicitly here so `next build` can resolve the generated runtime
# + types when it imports @prisma/client.
RUN cd packages/db && rm -rf dist \
                   && bun scripts/combine-schemas.js \
                   && DATABASE_URL="$DATABASE_URL" sh scripts/generate-prisma-client-js.sh \
                   && bunx tsc \
                   && bun scripts/build-dist-schema.js

RUN cd packages/auth && bun run build \
  && cd ../integration-platform && bun run build \
  && cd ../email && bun run build \
  && cd ../company && bun run build \
  && cd ../billing && bun run build
RUN find apps/app/prisma/schema -name '*.prisma' ! -name 'schema.prisma' -delete \
  && find packages/db/prisma/schema -name '*.prisma' ! -name 'schema.prisma' -exec cp {} apps/app/prisma/schema/ \;

# Ensure Next build has required public env at build-time
ARG NEXT_PUBLIC_BETTER_AUTH_URL
ARG NEXT_PUBLIC_PORTAL_URL
ARG NEXT_PUBLIC_POSTHOG_KEY
ARG NEXT_PUBLIC_POSTHOG_HOST
ARG NEXT_PUBLIC_IS_DUB_ENABLED
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_BETTER_AUTH_URL=$NEXT_PUBLIC_BETTER_AUTH_URL \
    NEXT_PUBLIC_PORTAL_URL=$NEXT_PUBLIC_PORTAL_URL \
    NEXT_PUBLIC_POSTHOG_KEY=$NEXT_PUBLIC_POSTHOG_KEY \
    NEXT_PUBLIC_POSTHOG_HOST=$NEXT_PUBLIC_POSTHOG_HOST \
    NEXT_PUBLIC_IS_DUB_ENABLED=$NEXT_PUBLIC_IS_DUB_ENABLED \
    NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_TELEMETRY_DISABLED=1 NODE_ENV=production \
    NEXT_OUTPUT_STANDALONE=true \
    NODE_OPTIONS=--max_old_space_size=6144

# Build the app
RUN cd apps/app && SKIP_ENV_VALIDATION=true bun run build:docker

# =============================================================================
# STAGE 4: App Production
# =============================================================================
FROM node:22-alpine AS app

WORKDIR /app

# Copy Next standalone output
COPY --from=app-builder /app/apps/app/.next/standalone ./
COPY --from=app-builder /app/apps/app/.next/static ./apps/app/.next/static
COPY --from=app-builder /app/apps/app/public ./apps/app/public

EXPOSE 3000
CMD ["node", "apps/app/server.js"]

# =============================================================================
# STAGE 5: Portal Builder
# =============================================================================
FROM deps AS portal-builder

WORKDIR /app

# Copy all source code needed for build
COPY packages ./packages
COPY apps/portal ./apps/portal

# Bring in node_modules for build and prisma prebuild
COPY --from=deps /app/node_modules ./node_modules

# Pre-combine schemas and build workspace packages for portal build
ARG DATABASE_URL
RUN cd packages/db && rm -rf dist \
                   && bun scripts/combine-schemas.js \
                   && DATABASE_URL="$DATABASE_URL" sh scripts/generate-prisma-client-js.sh \
                   && bunx tsc \
                   && bun scripts/build-dist-schema.js
RUN cp packages/db/dist/schema.prisma apps/portal/prisma/schema.prisma

RUN cd packages/auth && bun run build \
  && cd ../integration-platform && bun run build \
  && cd ../email && bun run build \
  && cd ../company && bun run build \
  && cd ../billing && bun run build
RUN find apps/portal/prisma/schema -name '*.prisma' ! -name 'schema.prisma' -delete \
  && find packages/db/prisma/schema -name '*.prisma' ! -name 'schema.prisma' -exec cp {} apps/portal/prisma/schema/ \;

# Ensure Next build has required public env at build-time
ARG NEXT_PUBLIC_BETTER_AUTH_URL
ENV NEXT_PUBLIC_BETTER_AUTH_URL=$NEXT_PUBLIC_BETTER_AUTH_URL \
    NEXT_TELEMETRY_DISABLED=1 NODE_ENV=production \
    NEXT_OUTPUT_STANDALONE=true \
    NODE_OPTIONS=--max_old_space_size=6144

# Build the portal
RUN cd apps/portal && SKIP_ENV_VALIDATION=true bun run build:docker

# =============================================================================
# STAGE 6: Portal Production
# =============================================================================
FROM node:22-alpine AS portal

WORKDIR /app

# Copy Next standalone output for portal
COPY --from=portal-builder /app/apps/portal/.next/standalone ./
COPY --from=portal-builder /app/apps/portal/.next/static ./apps/portal/.next/static
COPY --from=portal-builder /app/apps/portal/public ./apps/portal/public

EXPOSE 3000
CMD ["node", "apps/portal/server.js"]

# (Trigger.dev hosted; no local runner stage)
