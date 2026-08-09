using System.Security.Cryptography;
using Rghw.Rasterizer.V1;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using Xunit;

namespace Rghw.Rasterizer.Tests;

public class RasterRendererTests
{
    private static RenderGlyphRequest RequestWith(params (double X1, double Y1, double X2, double Y2)[] segments) =>
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
            Segments = { segments.Select(s => new Segment { X1 = s.X1, Y1 = s.Y1, X2 = s.X2, Y2 = s.Y2 }) },
        };

    private static readonly (double, double, double, double)[] SampleGlyph =
    {
        (32.0, 784.0, 32.0, 16.0),
        (992.0, 784.0, 992.0, 16.0),
        (32.0, 400.0, 992.0, 400.0),
    };

    [Fact]
    public void RenderProducesValidPngBytes()
    {
        var result = new RasterRenderer().Render(RequestWith(SampleGlyph));
        byte[] magic = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        Assert.True(result.Bytes.AsSpan().StartsWith(magic));
        Assert.Equal(Convert.ToHexString(SHA256.HashData(result.Bytes)).ToLowerInvariant(), result.Sha256Hex);
    }

    [Fact]
    public void RenderIsDeterministic()
    {
        var renderer = new RasterRenderer();
        RasterResult first = renderer.Render(RequestWith(SampleGlyph));
        RasterResult second = renderer.Render(RequestWith(SampleGlyph));
        Assert.Equal(first.Bytes, second.Bytes);
        Assert.Equal(first.Width, second.Width);
        Assert.Equal(first.Height, second.Height);
    }

    [Fact]
    public void RenderHasContent()
    {
        var result = new RasterRenderer().Render(RequestWith(SampleGlyph));
        using var image = Image.Load<Rgba32>(result.Bytes);
        int opaque = CountOpaque(image);
        Assert.True(opaque > 500, $"expected visible strokes, saw {opaque} opaque pixels");
    }

    [Fact]
    public void SmallGlyphIsCroppedWithOcrMargin()
    {
        var result = new RasterRenderer().Render(RequestWith((500.0, 400.0, 524.0, 400.0)));
        Assert.True(result.Width < 512, $"expected a crop, got full canvas {result.Width}x{result.Height}");
        Assert.True(result.Width > 0 && result.Height > 0);
    }

    [Fact]
    public void FullWidthGlyphStaysWithinCanvas()
    {
        var result = new RasterRenderer().Render(RequestWith(SampleGlyph));
        Assert.True(result.Width <= 512 && result.Height <= 512);
    }

    [Fact]
    public void ThickerStrokeDrawsMorePixels()
    {
        var renderer = new RasterRenderer();
        var thin = RequestWith(SampleGlyph);
        thin.Profile = new RenderProfile { StrokeWidth = 8, Antialias = true, LineCap = "round", Supersampling = 2 };
        var thick = RequestWith(SampleGlyph);
        thick.Profile = new RenderProfile { StrokeWidth = 80, Antialias = true, LineCap = "round", Supersampling = 2 };
        int thinPixels = CountOpaque(Image.Load<Rgba32>(renderer.Render(thin).Bytes));
        int thickPixels = CountOpaque(Image.Load<Rgba32>(renderer.Render(thick).Bytes));
        Assert.True(thickPixels > thinPixels, $"thick {thickPixels} <= thin {thinPixels}");
    }

    [Fact]
    public void AllSupersamplingFactorsProduceContent()
    {
        var renderer = new RasterRenderer();
        foreach (uint ss in new[] { 1u, 2u, 4u })
        {
            var request = RequestWith(SampleGlyph);
            request.Profile = new RenderProfile { StrokeWidth = 28, Antialias = true, LineCap = "round", Supersampling = ss };
            var result = renderer.Render(request);
            Assert.True(result.Width > 0 && result.Height > 0, $"ss={ss} produced empty image");
            Assert.True(CountOpaque(Image.Load<Rgba32>(result.Bytes)) > 100, $"ss={ss} produced blank image");
        }
    }

    [Fact]
    public void ButtCapRendersWithoutRoundOverhang()
    {
        var request = RequestWith((100.0, 400.0, 200.0, 400.0));
        request.Profile = new RenderProfile { StrokeWidth = 40, Antialias = false, LineCap = "butt", Supersampling = 1 };
        var result = new RasterRenderer().Render(request);
        Assert.True(CountOpaque(Image.Load<Rgba32>(result.Bytes)) > 50);
    }

    internal static int CountOpaque(Image<Rgba32> image)
    {
        int count = 0;
        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                if (image[x, y].A > 0)
                {
                    count++;
                }
            }
        }
        return count;
    }
}
