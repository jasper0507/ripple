FROM golang:1.27.2-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server \
 && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate \
 && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/rebuild ./cmd/rebuild

FROM alpine:3.23
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/ /usr/local/bin/
COPY deploy/config.yaml /app/config.yaml
ENV RIPPLE_CONFIG_FILE=/app/config.yaml GIN_MODE=release
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/server"]
