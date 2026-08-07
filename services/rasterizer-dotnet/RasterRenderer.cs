using System.Security.Cryptography;
using Rghw.Rasterizer.V1;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Drawing;
using SixLabors.ImageSharp.Drawing.Processing;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;

namespace Rghw.Rasterizer;

public sealed record RasterResult(byte[] Bytes, string Sha256Hex, int Width, int Height, double PixelDensity);

// Stage 4 rendering: normalized em-square segments (1024 units, baseline at
// 800) are drawn onto a transparent canvas with rounded caps, configurable
// antialiasing and stroke width, and deterministic integer supersampling
// with box downsampling. The image is cropped to the drawn content plus an
// OCR margin, then encoded as PNG. Every step is pure arithmetic on the
// request, so identical requests produce byte-identical PNGs.
public sealed class RasterRenderer
{
    public const double EmSize = 1024.0;
    public const double Baseline = 800.0;
    public const double OcrMarginRatio = 0.05;
    public const double MinOcrMarginPx = 8.0;
    public const string ContentType = "image/png";

    public RasterResult Render(RenderGlyphRequest request)
    {
        var canvas = request.Canvas;
        var profile = request.Profile;
        double scale = Math.Min(canvas.Width / EmSize, canvas.Height / EmSize);
        double offsetX = (canvas.Width - EmSize * scale) / 2.0;
        double offsetY = (canvas.Height - EmSize * scale) / 2.0;
        int ss = (int)profile.Supersampling;
        int renderWidth = (int)canvas.Width * ss;
        int renderHeight = (int)canvas.Height * ss;
        float strokePx = (float)(profile.StrokeWidth * scale * ss);

        using var image = new Image<Rgba32>(renderWidth, renderHeight);
        var pen =
            new SolidPen(
                new PenOptions(Color.Black, strokePx)
                {
                    EndCapStyle = CapFor(profile.LineCap),
                    JointStyle = JointStyle.Round,
                });
        var options = new DrawingOptions { GraphicsOptions = { Antialias = profile.Antialias } };
        image.Mutate(ctx =>
        {
            foreach (var segment in request.Segments)
            {
                ctx.DrawLine(
                    options,
                    pen,
                    new[]
                    {
                        ToRenderPoint(segment.X1, segment.Y1, scale, offsetX, offsetY, ss),
                        ToRenderPoint(segment.X2, segment.Y2, scale, offsetX, offsetY, ss),
                    });
            }
        });

        (int left, int top, int right, int bottom) = CropBounds(request, scale, offsetX, offsetY, ss, renderWidth, renderHeight);
        int outWidth = Math.Max(1, (right - left) / ss);
        int outHeight = Math.Max(1, (bottom - top) / ss);
        byte[] png = DownsampleAndEncode(image, left, top, outWidth, outHeight, ss);
        string sha = Convert.ToHexString(SHA256.HashData(png)).ToLowerInvariant();
        double density = EmSize / Math.Max(outWidth, outHeight);
        return new RasterResult(png, sha, outWidth, outHeight, density);
    }

    private static EndCapStyle CapFor(string lineCap) =>
        lineCap.Equals("round", StringComparison.OrdinalIgnoreCase) ? EndCapStyle.Round :
        lineCap.Equals("square", StringComparison.OrdinalIgnoreCase) ? EndCapStyle.Square :
        EndCapStyle.Butt;

    private static PointF ToRenderPoint(double x, double y, double scale, double offsetX, double offsetY, int ss) =>
        new(
            (float)((x * scale + offsetX) * ss),
            (float)((y * scale + offsetY) * ss));

    // Content bounding box in em units, expanded by half the stroke and the
    // OCR margin, clamped to the em square, then mapped to render pixels.
    private static (int Left, int Top, int Right, int Bottom) CropBounds(
        RenderGlyphRequest request, double scale, double offsetX, double offsetY, int ss,
        int renderWidth, int renderHeight)
    {
        double xMin = double.MaxValue, yMin = double.MaxValue, xMax = double.MinValue, yMax = double.MinValue;
        foreach (var segment in request.Segments)
        {
            xMin = Math.Min(xMin, Math.Min(segment.X1, segment.X2));
            yMin = Math.Min(yMin, Math.Min(segment.Y1, segment.Y2));
            xMax = Math.Max(xMax, Math.Max(segment.X1, segment.X2));
            yMax = Math.Max(yMax, Math.Max(segment.Y1, segment.Y2));
        }
        double halfStroke = request.Profile.StrokeWidth / 2.0;
        double marginEm = Math.Max(MinOcrMarginPx, OcrMarginRatio * Math.Max(request.Canvas.Width, request.Canvas.Height)) / scale;
        xMin = Math.Max(0, xMin - halfStroke - marginEm);
        yMin = Math.Max(0, yMin - halfStroke - marginEm);
        xMax = Math.Min(EmSize, xMax + halfStroke + marginEm);
        yMax = Math.Min(EmSize, yMax + halfStroke + marginEm);

        int left = Math.Clamp((int)Math.Floor((xMin * scale + offsetX) * ss), 0, renderWidth);
        int top = Math.Clamp((int)Math.Floor((yMin * scale + offsetY) * ss), 0, renderHeight);
        int right = Math.Clamp((int)Math.Ceiling((xMax * scale + offsetX) * ss), 0, renderWidth);
        int bottom = Math.Clamp((int)Math.Ceiling((yMax * scale + offsetY) * ss), 0, renderHeight);
        if (right <= left || bottom <= top)
        {
            return (0, 0, renderWidth, renderHeight);
        }
        return (left, top, right, bottom);
    }

    // Box downsample the cropped render region by the supersampling factor
    // (plain RGBA averaging: deterministic, no resampler heuristics) and
    // encode the PNG.
    private static byte[] DownsampleAndEncode(Image<Rgba32> source, int left, int top, int outWidth, int outHeight, int ss)
    {
        using var output = new Image<Rgba32>(outWidth, outHeight);
        int block = ss * ss;
        for (int y = 0; y < outHeight; y++)
        {
            for (int x = 0; x < outWidth; x++)
            {
                int r = 0, g = 0, b = 0, a = 0;
                for (int dy = 0; dy < ss; dy++)
                {
                    for (int dx = 0; dx < ss; dx++)
                    {
                        Rgba32 pixel = source[left + x * ss + dx, top + y * ss + dy];
                        r += pixel.R;
                        g += pixel.G;
                        b += pixel.B;
                        a += pixel.A;
                    }
                }
                output[x, y] = new Rgba32((byte)(r / block), (byte)(g / block), (byte)(b / block), (byte)(a / block));
            }
        }
        using var stream = new MemoryStream();
        output.SaveAsPng(stream);
        return stream.ToArray();
    }
}
