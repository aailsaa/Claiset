FROM golang:1.23-alpine AS build
WORKDIR /src
RUN apk add --no-cache ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/items-service ./cmd/items-service

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /out/items-service /items-service
EXPOSE 8081
ENTRYPOINT ["/items-service"]

