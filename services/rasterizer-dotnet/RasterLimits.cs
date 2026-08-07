namespace Rghw.Rasterizer;

// Trust-boundary limits for RenderGlyph requests (architecture section 12):
// bounded segment count, bounded canvas, bounded stroke width, and closed
// sets for the profile string fields so every request stays deterministic.
public sealed class RasterLimits
{
    public int MaxSegments { get; set; } = 8192;

    public int MaxCanvasDimension { get; set; } = 2048;

    public double MaxStrokeWidth { get; set; } = 256.0;

    public static readonly string[] AllowedLineCaps = { "round", "butt", "square" };

    public static readonly int[] AllowedSupersampling = { 1, 2, 4 };

    public static RasterLimits FromEnvironment(Func<string, string?> getenv)
    {
        var limits = new RasterLimits();
        if (int.TryParse(getenv("RASTERIZER_MAX_SEGMENTS"), out int segments) && segments > 0)
        {
            limits.MaxSegments = segments;
        }
        if (int.TryParse(getenv("RASTERIZER_MAX_CANVAS"), out int canvas) && canvas > 0)
        {
            limits.MaxCanvasDimension = canvas;
        }
        return limits;
    }
}
