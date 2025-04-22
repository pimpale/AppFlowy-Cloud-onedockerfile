# syntax=docker/dockerfile:1
# Using cargo-chef to manage Rust build cache effectively
FROM lukemathwalker/cargo-chef:latest-rust-1.81 as chef

WORKDIR /app
RUN apt update && apt install lld clang -y

FROM chef as planner
# the reason we have so many COPY commands is because we don't want to copy the whole repo
# as this would force a rebuild of all the dependencies even if we only change a single file
COPY admin_frontend admin_frontend
COPY services services
COPY script script
COPY src src
COPY libs libs
COPY assets assets
COPY xtask xtask
COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock
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
ENV CARGO_BUILD_JOBS=32
RUN cargo chef cook --release --recipe-path recipe.json

COPY admin_frontend admin_frontend
COPY services services
COPY script script
COPY src src
COPY libs libs
COPY assets assets
COPY xtask xtask
COPY .sqlx .sqlx
COPY migrations migrations
COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock
ENV SQLX_OFFLINE true

# Build the project
RUN echo "Building with profile: ${PROFILE}, features: ${FEATURES}, "
RUN cargo build --profile=${PROFILE} --features "${FEATURES}" --bin appflowy_cloud



FROM ubuntu:24.04 AS runtime

# Update and install dependencies
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \ 
  openssl \
  ca-certificates \
  curl \
  wget \
  software-properties-common \
  sudo \
  bash \
  fluxbox \
  git \
  net-tools \
  novnc \
  supervisor \
  x11vnc \
  xterm \
  xvfb \
  make \
  redis-server \
  postgresql-16-pgvector \
  g++ \
  m4 
RUN update-ca-certificates

RUN add-apt-repository ppa:xtradeb/apps
RUN apt-get install -y chromium


# install dinit
RUN git clone https://github.com/davmac314/dinit && \
    cd dinit && make && make install
  
# install redis
EXPOSE 6379
# install postgres
EXPOSE 5432
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=password
ENV POSTGRES_DB=postgres
COPY pg_hba.conf /etc/postgresql/16/main/pg_hba.conf

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



# Setup and start dinit
COPY dinit.d/ /etc/dinit.d/
RUN mkdir -p /var/log/dinit
CMD ["dinit", "--container", "-d", "/etc/dinit.d/"]
