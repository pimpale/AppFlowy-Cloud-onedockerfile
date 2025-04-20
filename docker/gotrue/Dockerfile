# syntax=docker/dockerfile:1
FROM golang as base
WORKDIR /go/src/supabase
RUN pwd
RUN pwd
RUN git clone https://github.com/pimpale/appflowy-auth-patch.git --depth 1 --branch magic_link_patch
RUN mv appflowy-auth-patch auth
WORKDIR /go/src/supabase/auth
RUN CGO_ENABLED=0 go build -o /auth .

FROM alpine:3.20
RUN adduser -D -u 1000 supabase

RUN apk add --no-cache ca-certificates curl
USER supabase

COPY --from=base /auth .
COPY --from=base /go/src/supabase/auth/migrations ./migrations

COPY start.sh .
CMD ["./start.sh"]
