FROM rust:1.88-slim-bookworm AS builder

WORKDIR /app

COPY Cargo.toml ./
COPY src ./src

RUN cargo build --release

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/target/release/torque-rust-service /usr/local/bin/torque-rust-service

EXPOSE 3001

ENV RUST_BIND_ADDR=0.0.0.0:3001

CMD ["/usr/local/bin/torque-rust-service"]
