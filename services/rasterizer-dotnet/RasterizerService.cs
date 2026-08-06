using Grpc.Core;
using RgHello.Rasterizer.V1;
using RasterizerBase = global::RgHello.Rasterizer.V1.Rasterizer.RasterizerBase;

namespace RgHello.Rasterizer;

// gRPC handler for rg.rasterizer.v1.Rasterizer (architecture section 12).
// Validate -> render -> store -> respond; the response carries the artifact
// object key, SHA-256, dimensions, byte count, and content type. The request
// contains only segments and opaque identifiers, never an expected
// character, so nothing here can leak the requested plaintext.
public sealed class RasterizerService : RasterizerBase
{
    private readonly IRasterStore _store;
    private readonly string _bucket;
    private readonly RasterRenderer _renderer;
    private readonly RasterLimits _limits;

    public RasterizerService(IRasterStore store, string bucket, RasterRenderer renderer, RasterLimits limits)
    {
        _store = store;
        _bucket = bucket;
        _renderer = renderer;
        _limits = limits;
    }

    public override async Task<RenderGlyphResponse> RenderGlyph(RenderGlyphRequest request, ServerCallContext context)
    {
        RenderValidator.Validate(request, _limits);
        RasterResult result = _renderer.Render(request);
        string operationId = OperationKeys.OperationId(
            request.RunId, request.GlyphInstanceId, request.Attempt, request.InputArtifactSha256);
        string objectKey = OperationKeys.ObjectKey(
            request.RunId, request.Position, request.GlyphInstanceId, request.Attempt, operationId);
        await _store.PutAsync(_bucket, objectKey, result.Bytes, RasterRenderer.ContentType, context.CancellationToken);
        return new RenderGlyphResponse
        {
            ArtifactId = OperationKeys.ArtifactUuid(operationId),
            ObjectKey = objectKey,
            Sha256 = result.Sha256Hex,
            Width = (uint)result.Width,
            Height = (uint)result.Height,
            ByteCount = (ulong)result.Bytes.Length,
            ContentType = RasterRenderer.ContentType,
        };
    }
}
