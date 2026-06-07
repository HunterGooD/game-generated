# syntax=docker/dockerfile:1

FROM rust:1.82-alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev pkgconfig openssl-dev

COPY Cargo.toml Cargo.toml
COPY src src
COPY tests tests
COPY benches benches

RUN cargo build --release

FROM alpine:3.20
WORKDIR /app
RUN apk add --no-cache ca-certificates

COPY --from=builder /app/target/release/echoes-server /usr/local/bin/echoes-server

ENV HOST=0.0.0.0
ENV PORT=7777
EXPOSE 7777

ENTRYPOINT ["/usr/local/bin/echoes-server"]
