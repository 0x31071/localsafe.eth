# Dockerfile for localsafe.eth - Production Hardened
# Base: node:25.5-alpine
# Port: 30003
# Security: Non-root user, strict permissions, minimal attack surface

# ==============================================================================
# Stage 1: Builder (build and prepare application)
# ==============================================================================
FROM node:25.5-alpine AS builder

LABEL maintainer="localsafe.eth"
LABEL description="Hardened Docker image for localsafe.eth"
LABEL org.opencontainers.image.source="git@github.com:0x31071/localsafe.eth"

# Update system and install build dependencies
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        git \
        python3 \
        make \
        g++ && \
    rm -rf /var/cache/apk/* /tmp/*

# Install pnpm globally
RUN npm install -g pnpm@latest && \
    npm cache clean --force

ENV CI=true \
    NODE_ENV=production

WORKDIR /app

# Copy dependency files
COPY package.json pnpm-lock.yaml ./

# Install all dependencies (needed for build)
RUN pnpm install
#RUN pnpm install --frozen-lockfile

# Copy source code
COPY . .

# Build application
RUN pnpm run build

# Clean up unnecessary files to reduce attack surface
RUN rm -rf \
    .git \
    .github \
    .gitignore \
    .eslintrc* \
    .prettierrc* \
    node_modules/.cache \
    src/ \
    tests/ \
    test/ \
    **/*.test.js \
    **/*.spec.js \
    **/*.md \
    **/*.map \
    coverage/ \
    .nyc_output/

# ==============================================================================
# Stage 2: Runner (production runtime - minimal and secure)
# ==============================================================================
FROM node:25.5-alpine AS runner

# Security: Update base system
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
        dumb-init \
        wget \
        ca-certificates \
        tzdata && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Set timezone (optional, adjust as needed)
ENV TZ=UTC

WORKDIR /app

# Create non-root user with minimal privileges
RUN addgroup -g 1001 -S nodejs && \
    adduser -S -D -H -u 1001 -h /app -s /sbin/nologin -G nodejs -g nodejs nextjs && \
    chown -R nextjs:nodejs /app

# Copy standalone application from builder
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Security: Set strict file permissions
# 500 = r-x------ (read and execute for owner only)
RUN chmod -R 500 /app
#    chmod 100 /app/server.js && \
#    find /app -type f -name "*.json" -exec chmod 400 {} \;

# Security: Remove unnecessary packages (reduce attack surface)
RUN apk del apk-tools && \
    rm -rf /sbin/apk /etc/apk /lib/apk /usr/share/apk /var/lib/apk

# Switch to non-root user (critical security measure)
USER nextjs

# Production environment variables
ENV NODE_ENV=production \
    PORT=30003 \
    HOSTNAME="0.0.0.0" \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_OPTIONS="--max-old-space-size=512 --no-warnings" 

# Expose application port
EXPOSE 30003

# Health check configuration
HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=40s \
            --retries=3 \
    CMD wget --no-verbose --tries=1 --spider --timeout=3 http://localhost:30003/ || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Run application as non-privileged process
CMD ["node", "server.js"]

# Security labels for automated scanning
LABEL security.scan.enabled="true"
LABEL security.scan.severity="CRITICAL,HIGH"
LABEL security.non-root="true"
LABEL security.read-only-root="true"
