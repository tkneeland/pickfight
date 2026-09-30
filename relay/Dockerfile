# Room-code relay (issue #238). Build from the repository root:
#   docker build -f relay/Dockerfile -t pickfight-relay .
FROM debian:bookworm-slim
ARG GODOT_VERSION=4.6.2
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/godot.zip \
       "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip /tmp/godot.zip -d /tmp && mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot && rm /tmp/godot.zip
WORKDIR /app
COPY . /app
EXPOSE 9080
CMD ["godot", "--headless", "--path", "/app", "-s", "relay/relay_main.gd", "--", "--port=9080"]
