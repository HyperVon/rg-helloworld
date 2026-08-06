using System.Security.Cryptography;
using Grpc.Core;
using RgHello.Rasterizer.V1;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Xunit;

namespace RgHello.Rasterizer.Tests;

public class RasterizerServiceTests
{
    private static RasterizerService Service(out FakePutClient fake)
    {
        fake = new FakePutClient();
        return new RasterizerService(new MinioRasterStore(fake), "rube-goldberg-artifacts", new RasterRenderer(), new RasterLimits());
    }

    private static RenderGlyphRequest ValidRequest() => RenderValidatorTests.ValidRequest();

    [Fact]
    public async Task RenderGlyphStoresPngAndReturnsMetadata()
    {
        RasterizerService service = Service(out FakePutClient fake);
        var response = await service.RenderGlyph(ValidRequest(), new TestServerCallContext());

        Assert.Equal("image/png", response.ContentType);
        Assert.Equal((ulong)fake.Content!.Length, response.ByteCount);
        Assert.Equal(Convert.ToHexString(SHA256.HashData(fake.Content)).ToLowerInvariant(), response.Sha256);
        Assert.StartsWith($"runs/{ValidRequest().RunId}/glyphs/0-{ValidRequest().GlyphInstanceId}/raster-attempt-1-", response.ObjectKey);
        Assert.EndsWith(".png", response.ObjectKey);
        Assert.Equal(36, response.ArtifactId.Length);
        Assert.Equal("rube-goldberg-artifacts", fake.Bucket);

        using var image = Image.Load<Rgba32>(fake.Content);
        Assert.Equal((int)response.Width, image.Width);
        Assert.Equal((int)response.Height, image.Height);
        Assert.True(image.Width > 0 && image.Height > 0);
    }

    [Fact]
    public async Task DuplicateRequestsAreIdempotent()
    {
        RasterizerService service = Service(out FakePutClient fake);
        RenderGlyphRequest request = ValidRequest();
        var first = await service.RenderGlyph(request, new TestServerCallContext());
        var second = await service.RenderGlyph(request, new TestServerCallContext());

        Assert.Equal(first.ObjectKey, second.ObjectKey);
        Assert.Equal(first.ArtifactId, second.ArtifactId);
        Assert.Equal(first.Sha256, second.Sha256);
        Assert.Equal(first.ByteCount, second.ByteCount);
    }

    [Fact]
    public async Task InvalidRequestIsRejectedWithoutStoring()
    {
        RasterizerService service = Service(out FakePutClient fake);
        var request = ValidRequest();
        request.InputArtifactSha256 = "short";

        var exception = await Assert.ThrowsAsync<RpcException>(
            () => service.RenderGlyph(request, new TestServerCallContext()));
        Assert.Equal(StatusCode.InvalidArgument, exception.StatusCode);
        Assert.Null(fake.ObjectKey);
    }

    [Fact]
    public async Task CancellationTokenFlowsToStore()
    {
        RasterizerService service = Service(out FakePutClient fake);
        using var cts = new CancellationTokenSource();
        await service.RenderGlyph(ValidRequest(), new TestServerCallContext(cts.Token));
        Assert.Equal(cts.Token, fake.Token);
    }
}

public sealed class TestServerCallContext : ServerCallContext
{
    private readonly CancellationToken _cancellationToken;

    public TestServerCallContext(CancellationToken cancellationToken = default) => _cancellationToken = cancellationToken;

    protected override string MethodCore => "/rg.rasterizer.v1.Rasterizer/RenderGlyph";

    protected override string HostCore => "localhost";

    protected override string PeerCore => "test";

    protected override DateTime DeadlineCore => DateTime.MaxValue;

    protected override Metadata RequestHeadersCore => new();

    protected override CancellationToken CancellationTokenCore => _cancellationToken;

    protected override Metadata ResponseTrailersCore => new();

    protected override Status StatusCore { get => Status.DefaultSuccess; set { } }

    protected override WriteOptions? WriteOptionsCore { get => null; set { } }

    protected override AuthContext AuthContextCore =>
        new("test", new Dictionary<string, List<AuthProperty>>());

    protected override ContextPropagationToken CreatePropagationTokenCore(ContextPropagationOptions? options) =>
        throw new NotSupportedException();

    protected override Task WriteResponseHeadersAsyncCore(Metadata responseHeaders) => Task.CompletedTask;
}
