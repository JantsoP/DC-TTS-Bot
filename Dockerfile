FROM rust:nightly-bookworm AS builder

ENV RUSTFLAGS="-C target-cpu=native"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /bot

# Cache dependency builds separately from the full workspace source.
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY tts_commands/Cargo.toml ./tts_commands/Cargo.toml
COPY tts_commands/src ./tts_commands/src
COPY tts_core/Cargo.toml ./tts_core/Cargo.toml
COPY tts_core/src ./tts_core/src
COPY tts_events/Cargo.toml ./tts_events/Cargo.toml
COPY tts_events/src ./tts_events/src
COPY tts_migrations/Cargo.toml ./tts_migrations/Cargo.toml
COPY tts_migrations/src ./tts_migrations/src
COPY tts_tasks/Cargo.toml ./tts_tasks/Cargo.toml
COPY tts_tasks/src ./tts_tasks/src

RUN mkdir -p target && \
    cargo build --release --locked && \
    rm -rf target

# Copy the full source tree for the final build.
COPY . .

RUN cargo build --release --locked

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --home-dir /bot --shell /usr/sbin/nologin ttsbot

WORKDIR /bot

COPY --from=builder /bot/target/release/tts_bot /usr/local/bin/tts_bot

USER ttsbot

CMD ["/usr/local/bin/tts_bot"]