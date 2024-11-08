# gRPC Server Builder
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:6.0-alpine3.19 AS grpc-server-builder
RUN apk update && apk add --no-cache gcompat
WORKDIR /build
COPY src/AccelByte.Extend.Vivox.Authentication.Server/*.csproj .
RUN dotnet restore -r linux-musl-x64
COPY src/AccelByte.Extend.Vivox.Authentication.Server .
RUN dotnet publish -c Release -r linux-musl-x64 -o /output


# gRPC Gateway Gen
FROM --platform=$BUILDPLATFORM rvolosatovs/protoc:4.1.0 AS grpc-gateway-gen
WORKDIR /build
COPY gateway gateway
COPY src src
COPY proto.sh .
RUN bash proto.sh


# gRPC Gateway Builder
FROM --platform=$BUILDPLATFORM golang:1.20-alpine3.19 AS grpc-gateway-builder
ARG TARGETOS
ARG TARGETARCH
ARG GOOS=$TARGETOS
ARG GOARCH=$TARGETARCH
ARG CGO_ENABLED=0
WORKDIR /build
COPY gateway/go.mod gateway/go.sum .
RUN go mod download
COPY gateway/ .
RUN rm -rf gateway/pkg/pb
COPY --from=grpc-gateway-gen /build/gateway/pkg/pb ./pkg/pb
RUN go build -v -o /output/$TARGETOS/$TARGETARCH/grpc_gateway .


# Extend App
FROM mcr.microsoft.com/dotnet/aspnet:6.0-alpine3.19
ARG TARGETOS
ARG TARGETARCH
RUN apk --no-cache add bash
WORKDIR /app
COPY --from=grpc-gateway-builder /output/$TARGETOS/$TARGETARCH/grpc_gateway .
COPY --from=grpc-gateway-gen /build/gateway/apidocs ./apidocs
COPY gateway/third_party ./third_party
COPY --from=grpc-server-builder /output/* .
COPY wrapper.sh .
RUN chmod +x wrapper.sh
# gRPC server port, gRPC gateway port, Prometheus /metrics port
EXPOSE 6565 8000 8080
CMD ./wrapper.sh
