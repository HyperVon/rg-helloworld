using Grpc.Core;
using Rghw.Rasterizer.V1;
using Xunit;

namespace Rghw.Rasterizer.Tests;

public class RenderValidatorTests
{
    private readonly RasterLimits _limits = new();

    internal static RenderGlyphRequest ValidRequest() =>
        new()
        {
            RunId = "22222222-2222-4222-8222-222222222222",
            StepId = "44444444-4444-4444-8444-444444444444",
            GlyphInstanceId = "55555555-5555-4555-8555-555555555555",
            Position = 0,
            Attempt = 1,
            InputArtifactSha256 = new string('a', 64),
            Canvas = new Canvas { Width = 512, Height = 512, Baseline = 400 },
            Profile = new RenderProfile { StrokeWidth = 28, Antialias = true, LineCap = "round", Supersampling = 2 },
            Segments = { new Segment { X1 = 0.1, Y1 = 0.0, X2 = 0.1, Y2 = 1.0 } },
        };

    [Fact]
    public void ValidRequestPasses() =>
        RenderValidator.Validate(ValidRequest(), _limits);

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void RunIdMustBePresent(string value)
    {
        var request = ValidRequest();
        request.RunId = value;
        AssertRejected(request);
    }

    [Theory]
    [InlineData("")]
    public void StepIdMustBePresent(string value)
    {
        var request = ValidRequest();
        request.StepId = value;
        AssertRejected(request);
    }

    [Theory]
    [InlineData("")]
    public void GlyphInstanceIdMustBePresent(string value)
    {
        var request = ValidRequest();
        request.GlyphInstanceId = value;
        AssertRejected(request);
    }

    [Fact]
    public void NegativePositionRejected()
    {
        var request = ValidRequest();
        request.Position = -1;
        AssertRejected(request);
    }

    [Fact]
    public void ZeroAttemptRejected()
    {
        var request = ValidRequest();
        request.Attempt = 0;
        AssertRejected(request);
    }

    [Theory]
    [InlineData("")]
    [InlineData("abc")]
    [InlineData("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
    [InlineData("gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg")]
    public void InputArtifactSha256MustBe64Hex(string value)
    {
        var request = ValidRequest();
        request.InputArtifactSha256 = value;
        AssertRejected(request);
    }

    [Fact]
    public void MissingCanvasRejected()
    {
        var request = ValidRequest();
        request.Canvas = null;
        AssertRejected(request);
    }

    [Theory]
    [InlineData(0u, 512u)]
    [InlineData(512u, 0u)]
    public void ZeroSizedCanvasRejected(uint width, uint height)
    {
        var request = ValidRequest();
        request.Canvas = new Canvas { Width = width, Height = height, Baseline = 400 };
        AssertRejected(request);
    }

    [Fact]
    public void OversizedCanvasRejected()
    {
        var request = ValidRequest();
        request.Canvas = new Canvas { Width = 2049, Height = 512, Baseline = 400 };
        AssertRejected(request);
    }

    [Fact]
    public void NonFiniteBaselineRejected()
    {
        var request = ValidRequest();
        request.Canvas = new Canvas { Width = 512, Height = 512, Baseline = double.NaN };
        AssertRejected(request);
    }

    [Fact]
    public void EmptySegmentsRejected()
    {
        var request = ValidRequest();
        request.Segments.Clear();
        AssertRejected(request);
    }

    [Fact]
    public void TooManySegmentsRejected()
    {
        var request = ValidRequest();
        request.Segments.Clear();
        for (int i = 0; i <= _limits.MaxSegments; i++)
        {
            request.Segments.Add(new Segment { X1 = 0, Y1 = 0, X2 = 1, Y2 = 1 });
        }
        AssertRejected(request);
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void NonFiniteSegmentCoordinateRejected(double value)
    {
        var request = ValidRequest();
        request.Segments.Clear();
        request.Segments.Add(new Segment { X1 = value, Y1 = 0, X2 = 1, Y2 = 1 });
        AssertRejected(request);
    }

    [Fact]
    public void MissingProfileRejected()
    {
        var request = ValidRequest();
        request.Profile = null;
        AssertRejected(request);
    }

    [Theory]
    [InlineData(0.0)]
    [InlineData(-5.0)]
    [InlineData(300.0)]
    public void StrokeWidthOutOfRangeRejected(double width)
    {
        var request = ValidRequest();
        request.Profile = new RenderProfile { StrokeWidth = width, Antialias = true, LineCap = "round", Supersampling = 1 };
        AssertRejected(request);
    }

    [Fact]
    public void UnknownLineCapRejected()
    {
        var request = ValidRequest();
        request.Profile = new RenderProfile { StrokeWidth = 28, Antialias = true, LineCap = "triangle", Supersampling = 1 };
        AssertRejected(request);
    }

    [Fact]
    public void UppercaseLineCapAccepted()
    {
        var request = ValidRequest();
        request.Profile = new RenderProfile { StrokeWidth = 28, Antialias = true, LineCap = "ROUND", Supersampling = 1 };
        RenderValidator.Validate(request, _limits);
    }

    [Theory]
    [InlineData(0u)]
    [InlineData(3u)]
    [InlineData(8u)]
    public void UnsupportedSupersamplingRejected(uint factor)
    {
        var request = ValidRequest();
        request.Profile = new RenderProfile { StrokeWidth = 28, Antialias = true, LineCap = "round", Supersampling = factor };
        AssertRejected(request);
    }

    [Fact]
    public void NullRequestRejected() =>
        AssertRejected(null!);

    private static void AssertRejected(RenderGlyphRequest request)
    {
        var exception = Assert.Throws<RpcException>(() => RenderValidator.Validate(request, new RasterLimits()));
        Assert.Equal(StatusCode.InvalidArgument, exception.StatusCode);
    }
}
