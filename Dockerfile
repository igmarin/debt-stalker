# ---- Builder Stage ----
# Uses the official Elixir image matching the project's Erlang/OTP and Elixir versions.
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20260610-slim AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set build environment
ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

# Cache deps — copy mix files first for better layer caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application source
COPY lib lib
COPY config config
COPY priv priv

# Compile and build assets
# Compile first so phoenix-colocated CSS is generated for tailwind
COPY assets assets
RUN mix compile
RUN mix assets.deploy

# Build the release
RUN mix release

# ---- Runtime Stage ----
# Slim runtime image based on the same Debian version as the builder.
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies (ncurses for the release console, libssl for crypto, ca-certs for HTTPS, curl for healthcheck)
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses5 \
    ca-certificates \
    curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create a non-root user for security
RUN groupadd -r debtstalker && useradd -r -g debtstalker -s /bin/sh -d /app debtstalker

# Copy the release from the builder stage
COPY --from=builder --chown=debtstalker:debtstalker /app/_build/prod/rel/debt_stalker ./

USER debtstalker

# Expose the Phoenix server port
EXPOSE 4000

# Health check via the /api/health endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:4000/api/health || exit 1

# Default command: start the release in server mode
CMD ["bin/debt_stalker", "start"]
