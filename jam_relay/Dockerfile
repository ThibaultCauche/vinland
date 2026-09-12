# Build multi-etapes : compile le relais en executable AOT autonome, puis
# copie uniquement ce binaire dans une image d'execution minimale (pas besoin
# du SDK Dart complet ni des sources en prod).
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml .
RUN dart pub get
COPY bin/ bin/
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/bin/server /app/server
ENV PORT=8765
EXPOSE 8765
ENTRYPOINT ["/app/server"]
