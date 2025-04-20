# syntax=docker/dockerfile:1
# Using cargo-chef to manage Rust build cache effectively
FROM lukemathwalker/cargo-chef:latest-rust-1.81 as chef

WORKDIR /app
RUN apt update && apt install lld clang -y

FROM chef as planner
COPY . .
# Compute a lock-like file for our project
RUN cargo chef prepare --recipe-path recipe.json

FROM chef as builder

# Update package lists and install protobuf-compiler along with other build dependencies
RUN apt update && apt install -y protobuf-compiler lld clang

# Specify a default value for FEATURES; it could be an empty string if no features are enabled by default
ARG FEATURES=""
ARG PROFILE="release"

COPY --from=planner /app/recipe.json recipe.json
# Build our project dependencies
ENV CARGO_BUILD_JOBS=16
RUN cargo chef cook --release --recipe-path recipe.json

COPY . .
ENV SQLX_OFFLINE true

# Build the project
RUN echo "Building with profile: ${PROFILE}, features: ${FEATURES}, "
RUN cargo build --profile=${PROFILE} --features "${FEATURES}" --bin appflowy_cloud

FROM ubuntu:24.04 AS runtime

# Update and install dependencies
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends openssl ca-certificates curl \
  && update-ca-certificates

# Install supervisor, novnc, x11vnc, xvfb, fluxbox, git, net-tools, xterm
RUN apt-get install -y \
  bash \
  fluxbox \
  git \
  net-tools \
  novnc \
  supervisor \
  x11vnc \
  xterm \
  xvfb \
  firefox
  
# install redis
RUN apt-get install -y redis-server


WORKDIR /app


COPY --from=builder /app/target/release/appflowy_cloud /usr/local/bin/appflowy_cloud
ENV APP_ENVIRONMENT production
ENV RUST_BACKTRACE 1

ARG APPFLOWY_APPLICATION_PORT
ARG PORT
ENV PORT=${APPFLOWY_APPLICATION_PORT:-${PORT:-8000}}
EXPOSE $PORT

ENV HOME=/root \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=C.UTF-8 \
    DISPLAY=:0.0 \
    DISPLAY_WIDTH=1024 \
    DISPLAY_HEIGHT=768

EXPOSE 8080


# Setup and start supervisor
COPY supervisord_conf.d/ /etc/supervisord_conf.d/
COPY supervisord.conf /etc/supervisord.conf
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
