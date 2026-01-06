# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Base - Common base image for all stages
# =============================================================================
FROM node:20-alpine AS base
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app

# =============================================================================
# Stage 2: Dependencies - Install production dependencies
# =============================================================================
FROM base AS deps

# Copy dependency definition files FIRST (Requirement 1.1)
COPY package.json package-lock.json ./
COPY prisma ./prisma/

# Install dependencies with BuildKit cache mount (Requirement 4.1)
RUN --mount=type=cache,target=/root/.npm \
    npm ci --only=production

# =============================================================================
# Stage 3: Build - Build the application
# =============================================================================
FROM base AS builder
WORKDIR /app

# Copy dependency files first
COPY package.json package-lock.json ./
COPY prisma ./prisma/

# Install ALL dependencies (including devDependencies) with cache
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Copy application source code AFTER dependencies (Requirement 1.2)
COPY app ./app
COPY components ./components
COPY lib ./lib
COPY types ./types
COPY public ./public
COPY tailwind.config.ts postcss.config.mjs tsconfig.json next.config.mjs next-env.d.ts ./

# Generate Prisma client
RUN npx prisma generate

# Build the application
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# =============================================================================
# Stage 4: Runner - Production runtime (Requirement 1.3)
# =============================================================================
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy only necessary files from builder
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/prisma ./node_modules/prisma

# Copy entrypoint script
COPY --chown=nextjs:nodejs docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

ENTRYPOINT ["./docker-entrypoint.sh"]
