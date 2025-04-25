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


# build web app
FROM node:20.12.0 AS web_builder

WORKDIR /app

RUN npm install -g pnpm@8.5.0
RUN git clone --depth 1 --branch main https://github.com/AppFlowy-IO/AppFlowy-Web.git .
RUN pnpm install
RUN sed -i 's|https://test.appflowy.cloud||g' src/components/main/app.hooks.ts
RUN pnpm run build


FROM ubuntu:24.04 AS runtime

# Base URL configuration
ENV FQDN=localhost
ENV SCHEME=http
ENV APPFLOWY_BASE_URL=${SCHEME}://${FQDN}

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
  m4 \
  nginx

RUN update-ca-certificates

RUN add-apt-repository ppa:xtradeb/apps
RUN apt-get install -y chromium


# install dinit
RUN git clone https://github.com/davmac314/dinit && \
    cd dinit && make && make install
  
# install redis
ENV REDIS_HOST=localhost
ENV REDIS_PORT=6379
EXPOSE 6379


# install postgres
ENV POSTGRES_HOST=localhost
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=password
ENV POSTGRES_PORT=5432
ENV POSTGRES_DB=postgres
ENV SUPABASE_PASSWORD=root
EXPOSE 5432
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=password
ENV POSTGRES_DB=postgres
COPY pg_hba.conf /etc/postgresql/16/main/pg_hba.conf
COPY postgresql.conf /etc/postgresql/16/main/postgresql.conf
COPY migrations/before /docker-entrypoint-initdb.d
WORKDIR /app

# install minio
ENV MINIO_HOST=localhost
ENV MINIO_PORT=9000
ENV AWS_ACCESS_KEY=minioadmin
ENV AWS_SECRET=minioadmin
ENV APPFLOWY_S3_CREATE_BUCKET=true
ENV APPFLOWY_S3_BUCKET=appflowy
ENV APPFLOWY_S3_USE_MINIO=true
ENV APPFLOWY_S3_MINIO_URL=http://${MINIO_HOST}:${MINIO_PORT}
ENV APPFLOWY_S3_ACCESS_KEY=${AWS_ACCESS_KEY}
ENV APPFLOWY_S3_SECRET_KEY=${AWS_SECRET}
ENV APPFLOWY_S3_REGION=us-east-1
ENV APPFLOWY_S3_PRESIGNED_URL_ENDPOINT=${APPFLOWY_BASE_URL}/minio-api
ENV MINIO_BROWSER_REDIRECT_URL=${APPFLOWY_BASE_URL}/minio
ENV MINIO_ROOT_USER=${APPFLOWY_S3_ACCESS_KEY}
ENV MINIO_ROOT_PASSWORD=${APPFLOWY_S3_SECRET_KEY}
RUN wget https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20250422221226.0.0_amd64.deb -O minio.deb
RUN dpkg -i minio.deb
RUN mkdir -p /data
EXPOSE 9000
EXPOSE 9001

# install gotrue
ENV GOTRUE_HOST=localhost
ENV GOTRUE_JWT_SECRET=hello456
ENV GOTRUE_JWT_EXP=7200
ENV GOTRUE_MAILER_AUTOCONFIRM=true
ENV GOTRUE_MAILER_TEMPLATES_MAGIC_LINK=
ENV GOTRUE_RATE_LIMIT_EMAIL_SENT=100
ENV GOTRUE_SMTP_HOST=smtp.gmail.com
ENV GOTRUE_SMTP_PORT=465
ENV GOTRUE_SMTP_USER=email_sender@some_company.com
ENV GOTRUE_SMTP_PASS=email_sender_password
ENV GOTRUE_SMTP_ADMIN_EMAIL=comp_admin@some_company.com
ENV GOTRUE_ADMIN_EMAIL=admin@example.com
ENV GOTRUE_ADMIN_PASSWORD=password
ENV GOTRUE_DISABLE_SIGNUP=false
ENV API_EXTERNAL_URL=${APPFLOWY_BASE_URL}/gotrue
ENV GOTRUE_DATABASE_URL=postgres://supabase_auth_admin:${SUPABASE_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
ENV GOTRUE_EXTERNAL_GOOGLE_ENABLED=false
ENV GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID=
ENV GOTRUE_EXTERNAL_GOOGLE_SECRET=
ENV GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI=${API_EXTERNAL_URL}/callback
ENV GOTRUE_EXTERNAL_GITHUB_ENABLED=false
ENV GOTRUE_EXTERNAL_GITHUB_CLIENT_ID=
ENV GOTRUE_EXTERNAL_GITHUB_SECRET=
ENV GOTRUE_EXTERNAL_GITHUB_REDIRECT_URI=${API_EXTERNAL_URL}/callback
ENV GOTRUE_EXTERNAL_DISCORD_ENABLED=false
ENV GOTRUE_EXTERNAL_DISCORD_CLIENT_ID=
ENV GOTRUE_EXTERNAL_DISCORD_SECRET=
ENV GOTRUE_EXTERNAL_DISCORD_REDIRECT_URI=${API_EXTERNAL_URL}/callback
ENV GOTRUE_EXTERNAL_APPLE_ENABLED=false
ENV GOTRUE_EXTERNAL_APPLE_CLIENT_ID=
ENV GOTRUE_EXTERNAL_APPLE_SECRET=
ENV GOTRUE_EXTERNAL_APPLE_REDIRECT_URI=${API_EXTERNAL_URL}/callback
ENV GOTRUE_SAML_ENABLED=false
ENV GOTRUE_SAML_PRIVATE_KEY=
ENV DATABASE_URL=${GOTRUE_DATABASE_URL}
ENV GOTRUE_SITE_URL=appflowy-flutter://
ENV GOTRUE_URI_ALLOW_LIST=**
ENV GOTRUE_JWT_ADMIN_GROUP_NAME=supabase_admin
ENV GOTRUE_DB_DRIVER=postgres
ENV GOTRUE_MAILER_URLPATHS_CONFIRMATION=/gotrue/verify
ENV GOTRUE_MAILER_URLPATHS_INVITE=/gotrue/verify
ENV GOTRUE_MAILER_URLPATHS_RECOVERY=/gotrue/verify
ENV GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE=/gotrue/verify
ENV GOTRUE_SMTP_MAX_FREQUENCY=1ns
RUN adduser supabase
USER supabase
COPY --from=gotrue_builder /auth /usr/local/bin/auth
COPY --from=gotrue_builder /go/src/supabase/auth/migrations /usr/local/etc/auth/migrations
ENV GOTRUE_DB_MIGRATIONS_PATH /usr/local/etc/auth/migrations
USER root
EXPOSE 9999

# install cloud
ENV APPFLOWY_APPLICATION_PORT=8000
ENV APPFLOWY_GOTRUE_BASE_URL=http://${GOTRUE_HOST}:9999
ENV APPFLOWY_DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
ENV APPFLOWY_ACCESS_CONTROL=true
ENV APPFLOWY_WEBSOCKET_MAILBOX_SIZE=6000
ENV APPFLOWY_DATABASE_MAX_CONNECTIONS=40
ENV APPFLOWY_REDIS_URI=redis://${REDIS_HOST}:${REDIS_PORT}
ENV APPFLOWY_MAILER_SMTP_HOST=smtp.gmail.com
ENV APPFLOWY_MAILER_SMTP_PORT=465
ENV APPFLOWY_MAILER_SMTP_USERNAME=email_sender@some_company.com
ENV APPFLOWY_MAILER_SMTP_EMAIL=email_sender@some_company.com
ENV APPFLOWY_MAILER_SMTP_PASSWORD=email_sender_password
ENV APPFLOWY_MAILER_SMTP_TLS_KIND=wrapper
ENV RUST_LOG=debug
ENV AI_OPENAI_API_KEY=
ENV AI_OPENAI_API_SUMMARY_MODEL=
ENV APPFLOWY_EMBEDDING_CHUNK_SIZE=1000
ENV APPFLOWY_EMBEDDING_CHUNK_OVERLAP=200
ENV AI_AZURE_OPENAI_API_KEY=
ENV AI_AZURE_OPENAI_API_BASE=
ENV AI_AZURE_OPENAI_API_VERSION=
ENV AI_ANTHROPIC_API_KEY=
ENV AI_SERVER_PORT=5001
ENV AI_SERVER_HOST=ai
ENV AI_DATABASE_URL=postgresql+psycopg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
ENV AI_REDIS_URL=redis://${REDIS_HOST}:${REDIS_PORT}
ENV AI_TEST_ENABLED=false
ENV AI_APPFLOWY_BUCKET_NAME=${APPFLOWY_S3_BUCKET}
ENV AI_APPFLOWY_HOST=${APPFLOWY_BASE_URL}
ENV AI_MINIO_URL=http://${MINIO_HOST}:${MINIO_PORT}
ENV APPFLOWY_INDEXER_ENABLED=true
ENV APPFLOWY_INDEXER_DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
ENV APPFLOWY_INDEXER_REDIS_URL=redis://${REDIS_HOST}:${REDIS_PORT}
ENV APPFLOWY_INDEXER_EMBEDDING_BUFFER_SIZE=5000
ENV APPFLOWY_COLLABORATE_MULTI_THREAD=false
ENV APPFLOWY_COLLABORATE_REMOVE_BATCH_SIZE=100
ENV APPFLOWY_ADMIN_FRONTEND_PATH_PREFIX=/console
ENV APPFLOWY_WEB_URL=${APPFLOWY_BASE_URL}
ENV APPFLOWY_GOTRUE_EXT_URL=${API_EXTERNAL_URL}
COPY --from=shared_builder /app/target/debug/appflowy_cloud /usr/local/bin/appflowy_cloud
ENV APP_ENVIRONMENT production
ENV RUST_BACKTRACE 1
EXPOSE 8000

# install worker
ENV APPFLOWY_WORKER_REDIS_URL=redis://${REDIS_HOST}:${REDIS_PORT}
ENV APPFLOWY_WORKER_DATABASE_URL=postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
ENV APPFLOWY_WORKER_DATABASE_NAME=${POSTGRES_DB}
COPY --from=shared_builder /app/target/debug/appflowy_worker /usr/local/bin/appflowy_worker

# install admin frontend
ENV ADMIN_FRONTEND_HOST=0.0.0.0
ENV ADMIN_FRONTEND_PORT=4000
ENV ADMIN_FRONTEND_REDIS_URL=redis://${REDIS_HOST}:${REDIS_PORT}
ENV ADMIN_FRONTEND_GOTRUE_URL=http://${GOTRUE_HOST}:9999
ENV ADMIN_FRONTEND_APPFLOWY_CLOUD_URL=http://${APPFLOWY_HOST}:8000
ENV ADMIN_FRONTEND_PATH_PREFIX=/console
COPY --from=shared_builder /app/target/debug/admin_frontend /usr/local/bin/admin_frontend
COPY --from=shared_builder /app/admin_frontend/assets /app/admin_frontend_assets
EXPOSE 4000

# install web app
COPY --from=web_builder /app/dist /usr/share/nginx/html/
COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80

ENV HOME=/root \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=C.UTF-8 \
    DISPLAY=:0.0 \
    DISPLAY_WIDTH=1024 \
    DISPLAY_HEIGHT=768

EXPOSE 6080



# Setup and start dinit
COPY dinit.d/ /etc/dinit.d/
RUN mkdir -p /var/log/dinit
CMD ["dinit", "--container", "-d", "/etc/dinit.d/"]
