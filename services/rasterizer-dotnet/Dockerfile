# Rasterizer: C#/.NET gRPC service. Base images are tag-pinned (never
# "latest"); the SDK 10.0.302 builder produces a self-contained publish and
# the aspnet 10.0.9 runtime runs it. Generated gRPC code is committed, so
# the build needs no network beyond NuGet restore (pinned by lock files).
FROM mcr.microsoft.com/dotnet/sdk:10.0.302 AS builder

WORKDIR /src
COPY services/rasterizer-dotnet /src/services/rasterizer-dotnet
WORKDIR /src/services/rasterizer-dotnet/cli
RUN dotnet publish -c Release -o /app --nologo

# The aspnet runtime image ships a built-in non-root `app` user.
FROM mcr.microsoft.com/dotnet/aspnet:10.0.9

WORKDIR /app
COPY --from=builder /app ./

ENV RASTERIZER_PORT=50051
ENV RASTERIZER_STORE=s3
ENV RASTERIZER_BUCKET=rube-goldberg-artifacts
ENV MINIO_ENDPOINT=http://minio.rube-goldberg.svc.cluster.local:9000

EXPOSE 50051
ENTRYPOINT ["dotnet", "rasterizer.Cli.dll", "serve"]
