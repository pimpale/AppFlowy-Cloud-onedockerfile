# syntax=docker/dockerfile:1
# Using cargo-chef to manage Rust build cache effectively
FROM lukemathwalker/cargo-chef:latest-rust-1.81 as shared_chef

WORKDIR /app
RUN apt update && apt install lld clang protobuf-compiler  -y

FROM shared_chef as shared_planner
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

FROM shared_chef as shared_builder


COPY --from=shared_planner /app/recipe.json recipe.json
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
RUN echo "Building Cloud"
RUN cargo build --bin appflowy_cloud

RUN echo "Building Worker"
WORKDIR /app/services/appflowy-worker
RUN cargo build --bin appflowy_worker

RUN echo "Building Admin Frontend"
WORKDIR /app/admin_frontend
RUN cargo build --bin admin_frontend

FROM golang as gotrue_builder
WORKDIR /go/src/supabase
RUN git clone https://github.com/pimpale/appflowy-auth-patch.git --branch magic_link_patch
RUN mv appflowy-auth-patch auth
WORKDIR /go/src/supabase/auth
RUN CGO_ENABLED=0 go build -o /auth .

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
COPY postgresql.conf /etc/postgresql/16/main/postgresql.conf
COPY migrations/before /docker-entrypoint-initdb.d
WORKDIR /app

# install minio
RUN wget https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20250422221226.0.0_amd64.deb -O minio.deb
RUN dpkg -i minio.deb
RUN mkdir -p /data
EXPOSE 9000
EXPOSE 9001

# install gotrue
RUN adduser supabase
USER supabase
COPY --from=gotrue_builder /auth /usr/local/bin/auth
COPY --from=gotrue_builder /go/src/supabase/auth/migrations /usr/local/etc/auth/migrations
ENV GOTRUE_DB_MIGRATIONS_PATH /usr/local/etc/auth/migrations
USER root
EXPOSE 9999

# install cloud
COPY --from=shared_builder /app/target/debug/appflowy_cloud /usr/local/bin/appflowy_cloud
ENV APP_ENVIRONMENT production
ENV RUST_BACKTRACE 1
EXPOSE 8000

# install worker
COPY --from=shared_builder /app/target/debug/appflowy_worker /usr/local/bin/appflowy_worker

# install admin frontend
COPY --from=shared_builder /app/target/debug/admin_frontend /usr/local/bin/admin_frontend
EXPOSE 3000

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
