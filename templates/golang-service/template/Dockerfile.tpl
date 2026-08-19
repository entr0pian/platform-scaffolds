FROM golang:1.22 AS build
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/{{ componentName }} ./cmd/server

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/{{ componentName }} /{{ componentName }}
EXPOSE 8080
ENTRYPOINT ["/{{ componentName }}"]
