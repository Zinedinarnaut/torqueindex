FROM hexpm/elixir:1.17.3-erlang-26.2.5.4-debian-bookworm-20260202 AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs .formatter.exs ./
COPY config ./config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib ./lib
COPY priv ./priv

RUN mix compile
RUN mix release

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=4000
ENV PHX_HOST=localhost
ENV SECRET_KEY_BASE=change_me
ENV RUST_SERVICE_URL=http://rust-service:3001
ENV CACHE_TTL_MS=60000

COPY --from=build /app/_build/prod/rel/torque_gateway ./

EXPOSE 4000

CMD ["bin/torque_gateway", "start"]
