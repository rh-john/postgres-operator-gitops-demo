FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app main.go

FROM alpine:3.20
RUN apk --no-cache add ca-certificates
COPY --from=builder /app /app
USER 1001
EXPOSE 8080
ENTRYPOINT ["/app"]
