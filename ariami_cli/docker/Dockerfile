FROM ghcr.io/cirruslabs/flutter:3.44.0 AS cli-builder

WORKDIR /workspace
COPY ariami_core/ /workspace/ariami_core/
COPY ariami_cli/ /workspace/ariami_cli/

WORKDIR /workspace/ariami_cli
RUN flutter pub get \
    && flutter build web -t lib/web/main.dart \
    && dart build cli -o build/cli-out

FROM rust:1-bookworm AS sonic-builder

COPY sonic/ /workspace/sonic/
WORKDIR /workspace/sonic
RUN cargo build --release --features aac-fdk --lib

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/ariami/bin /opt/ariami/lib /opt/ariami/web /data /music

COPY --from=cli-builder /workspace/ariami_cli/build/cli-out/bundle/bin/ariami_cli /opt/ariami/bin/ariami_cli
COPY --from=cli-builder /workspace/ariami_cli/build/cli-out/bundle/lib/ /opt/ariami/lib/
COPY --from=sonic-builder /workspace/sonic/target/release/libsonic_transcoder.so /opt/ariami/lib/libsonic_transcoder.so
COPY --from=cli-builder /workspace/ariami_cli/build/web/ /opt/ariami/web/
COPY --from=cli-builder /workspace/ariami_cli/ariami_cli-launcher.sh /opt/ariami/ariami_cli
COPY --from=cli-builder /workspace/ariami_cli/SETUP.txt /opt/ariami/SETUP.txt
COPY --from=cli-builder /workspace/ariami_cli/HEADLESS.md /opt/ariami/HEADLESS.md

RUN chmod +x /opt/ariami/ariami_cli /opt/ariami/bin/ariami_cli

# Run as an unprivileged user: only /data (config, auth stores, caches) needs
# to be writable; the application binaries and the /music library stay
# read-only. Host-mounted volumes must be readable (and /data writable) by
# uid 10001 — see DOCKER.md.
RUN useradd --system --uid 10001 --home-dir /data --shell /usr/sbin/nologin ariami \
    && chown -R ariami:ariami /data

ENV ARIAMI_DATA_DIR=/data
ENV ARIAMI_CONTAINER=1

VOLUME ["/data", "/music"]
EXPOSE 8080
WORKDIR /opt/ariami
USER ariami

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/api/ping || exit 1

ENTRYPOINT ["/opt/ariami/bin/ariami_cli"]
CMD ["--server-mode", "--port", "8080"]
