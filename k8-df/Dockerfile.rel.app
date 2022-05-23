# Build Stage using a pre-build release
FROM  bitwalker/alpine-elixir:latest AS build
# RUN elixir -v
# Accept MIX_ENV as build arg
ARG MIX_ENV=${MIX_ENV:-dev}
ARG BUILD_NAME=myapp
# ENV HEX_MIRROR=https://repo.hex.pm

# Set current working directory for next steps
WORKDIR /opt/release

COPY mix.exs mix.lock ./
COPY config config
# Run dependencies && Create a release with quiet to skip writing progress
RUN mix do deps.get --only $MIX_ENV && mix deps.compile
COPY lib ./lib
COPY rel ./rel
RUN mix release $BUILD_NAME --quiet
# Create a non-root user && Transfer ownership to app user
RUN adduser -h /opt/app -D app \
   && chown -R app: _build/

################################@@ Final Stage
FROM alpine:latest AS app

# Accept MIX_ENV as build arg
ARG MIX_ENV=${MIX_ENV:-dev}
ENV BUILD_NAME=myapp
# Install system dependencies required for your app at runtime
RUN apk --update --no-cache add bash grep openssl ncurses-libs tini libstdc++ libgcc
# Create a non-root user
RUN adduser -h /opt/app -D app
# Switch to non-root user
USER app
# Set current working directory to app dir
WORKDIR /opt/app

ENV RELEASE_DISTRIBUTION=name
ENV POD_IP=127.0.0.1 
# <- will be overridden 
ENV RELEASE_NODE=${BUILD_NAME}@${POD_IP}

# Copy release dir from build stage
COPY --from=build /opt/release/_build/${MIX_ENV}/rel/${BUILD_NAME} ./

ENTRYPOINT [ "./bin/myapp" ]
# the entrypoint will be run, then we don't have a default command but args are in k8 manifest
