using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Rghw.Rasterizer;

// Rasterizer host: `rasterizer version` prints the banner, `rasterizer serve`
// runs the gRPC server. Store mode is selected by RASTERIZER_STORE
// ("s3" default, "local" for the host integration harness).
if (args.Length >= 1 && args[0] == "version")
{
    Console.WriteLine(RasterizerBanner.Render());
    return 0;
}
if (args.Length >= 1 && args[0] == "serve")
{
    return await ServeAsync();
}
Console.Error.WriteLine("usage: rasterizer version | serve");
return 1;

static string Env(string name, string fallback) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value ? value : fallback;

static async Task<int> ServeAsync()
{
    // gRPC between the Go normalizer and this service is plaintext h2c.
    // Kestrel only serves cleartext HTTP/2 when HTTP/1 is disabled on the
    // endpoint (with Http1AndHttp2 it always falls back to HTTP/1 without
    // TLS), so this endpoint is HTTP/2 only.
    int port = int.Parse(Env("RASTERIZER_PORT", "50051"));
    string bucket = Env("RASTERIZER_BUCKET", "rube-goldberg-artifacts");
    IRasterStore store =
        Env("RASTERIZER_STORE", "s3") == "local"
            ? new LocalRasterStore(Env("RASTERIZER_LOCAL_DIR", ".local/rasterizer-store"))
            : new MinioRasterStore(
                new MinioPutClientAdapter(
                    Env("MINIO_ENDPOINT", "http://localhost:9000"),
                    Env("MINIO_ACCESS_KEY", "minioadmin"),
                    Env("MINIO_SECRET_KEY", "minioadmin")));

    Console.WriteLine($"{RasterizerBanner.Render()} (gRPC on :{port})");
    var builder = WebApplication.CreateBuilder();
    builder.WebHost.ConfigureKestrel(options =>
        options.ListenAnyIP(port, listen => listen.Protocols = HttpProtocols.Http2));
    builder.Services.AddGrpc();
    var limits = RasterLimits.FromEnvironment(Environment.GetEnvironmentVariable);
    builder.Services.AddSingleton(new RasterizerService(store, bucket, new RasterRenderer(), limits));

    string otlpEndpoint = Env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.rube-goldberg:4317");
    var resourceBuilder = ResourceBuilder.CreateDefault().AddService("rasterizer");
    try
    {
        builder.Services.AddOpenTelemetry()
            .WithTracing(tracing => tracing
                .SetResourceBuilder(resourceBuilder)
                .AddAspNetCoreInstrumentation()
                .AddOtlpExporter(o =>
                {
                    o.Endpoint = new Uri(otlpEndpoint);
                    o.Protocol = OtlpExportProtocol.Grpc;
                }))
            .WithLogging(logging => logging
                .SetResourceBuilder(resourceBuilder)
                .AddOtlpExporter(o =>
                 {
                     o.Endpoint = new Uri(otlpEndpoint);
                     o.Protocol = OtlpExportProtocol.Grpc;
                 }));
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"rasterizer: OpenTelemetry setup skipped (collector unreachable): {ex.Message}");
    }

    var app = builder.Build();
    app.MapGrpcService<RasterizerService>();

    var startupLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("rasterizer");
    startupLogger.LogInformation("rasterizer started; serving gRPC on port {Port}", port);

    await app.RunAsync();
    return 0;
}
