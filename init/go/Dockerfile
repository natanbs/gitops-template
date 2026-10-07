FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o server main.go

FROM alpine:3.21
RUN addgroup -S app && adduser -S -G app app
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
USER app
CMD ["./server"]
