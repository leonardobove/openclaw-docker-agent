# ─────────────────────────────────────────────────────────────────────────────
# Custom Caddy build — includes caddy-ratelimit module
# ─────────────────────────────────────────────────────────────────────────────
FROM caddy:2-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Verify module is present
RUN caddy list-modules | grep ratelimit
