# Build watchtower with --defer-days (PR containrrr/watchtower#1884, not in latest release yet).
FROM golang:1.23-alpine AS build
RUN apk add --no-cache git ca-certificates
WORKDIR /src
RUN git clone --depth 1 https://github.com/containrrr/watchtower.git . \
    && git fetch --depth 1 origin pull/1884/head:defer-pr \
    && git checkout defer-pr
RUN CGO_ENABLED=0 go build -o /watchtower .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=build /watchtower /watchtower
ENTRYPOINT ["/watchtower"]
