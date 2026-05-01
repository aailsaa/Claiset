# EKS nodes are linux/amd64; building on Apple Silicon without this yields arm64-only manifests.
FROM --platform=linux/amd64 golang:1.23-alpine AS build
WORKDIR /src
RUN apk add --no-cache ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate

FROM --platform=linux/amd64 alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /out/migrate /migrate
ENTRYPOINT ["/migrate"]

