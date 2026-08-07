using System.Globalization;
using Grpc.Core;
using Rghw.Rasterizer.V1;

namespace Rghw.Rasterizer;

// Request validation at the gRPC trust boundary. The rasterizer receives
// only geometric segments and opaque identifiers; every field is checked so
// malformed or oversized requests fail with InvalidArgument before any
// rendering or storage work happens.
public static class RenderValidator
{
    public static void Validate(RenderGlyphRequest request, RasterLimits limits)
    {
        if (request is null)
        {
            throw Invalid("request is null");
        }
        if (string.IsNullOrWhiteSpace(request.RunId))
        {
            throw Invalid("run_id is required");
        }
        if (string.IsNullOrWhiteSpace(request.StepId))
        {
            throw Invalid("step_id is required");
        }
        if (string.IsNullOrWhiteSpace(request.GlyphInstanceId))
        {
            throw Invalid("glyph_instance_id is required");
        }
        if (request.Position < 0)
        {
            throw Invalid("position must be >= 0");
        }
        if (request.Attempt < 1)
        {
            throw Invalid("attempt must be >= 1");
        }
        if (!IsHexSha256(request.InputArtifactSha256))
        {
            throw Invalid("input_artifact_sha256 must be 64 hexadecimal characters");
        }

        var canvas = request.Canvas;
        if (canvas is null)
        {
            throw Invalid("canvas is required");
        }
        if (canvas.Width < 1 || canvas.Height < 1)
        {
            throw Invalid("canvas width and height must be >= 1");
        }
        if (canvas.Width > limits.MaxCanvasDimension || canvas.Height > limits.MaxCanvasDimension)
        {
            throw Invalid($"canvas exceeds the {limits.MaxCanvasDimension} pixel limit");
        }
        if (!double.IsFinite(canvas.Baseline) || canvas.Baseline < 0)
        {
            throw Invalid("canvas baseline must be finite and >= 0");
        }

        var segments = request.Segments;
        if (segments is null || segments.Count == 0)
        {
            throw Invalid("at least one segment is required");
        }
        if (segments.Count > limits.MaxSegments)
        {
            throw Invalid($"segment count {segments.Count} exceeds the {limits.MaxSegments} limit");
        }
        foreach (var segment in segments)
        {
            if (segment is null ||
                !double.IsFinite(segment.X1) || !double.IsFinite(segment.Y1) ||
                !double.IsFinite(segment.X2) || !double.IsFinite(segment.Y2))
            {
                throw Invalid("segment coordinates must be finite");
            }
        }

        var profile = request.Profile;
        if (profile is null)
        {
            throw Invalid("profile is required");
        }
        if (!double.IsFinite(profile.StrokeWidth) || profile.StrokeWidth <= 0 || profile.StrokeWidth > limits.MaxStrokeWidth)
        {
            throw Invalid($"stroke_width must be in (0, {limits.MaxStrokeWidth}]");
        }
        if (Array.IndexOf(RasterLimits.AllowedLineCaps, profile.LineCap?.ToLowerInvariant()) < 0)
        {
            throw Invalid($"line_cap must be one of {string.Join(", ", RasterLimits.AllowedLineCaps)}");
        }
        if (Array.IndexOf(RasterLimits.AllowedSupersampling, (int)profile.Supersampling) < 0)
        {
            throw Invalid("supersampling must be one of 1, 2, or 4");
        }
    }

    private static bool IsHexSha256(string value) =>
        value is { Length: 64 } && value.All(Uri.IsHexDigit);

    private static RpcException Invalid(string message) =>
        new(new Status(StatusCode.InvalidArgument, message));
}
