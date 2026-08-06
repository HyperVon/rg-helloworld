using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace RgHello.Rasterizer;

// Deterministic identity for raster artifacts (architecture section 13.5):
// the operation ID is SHA-256 over run, step, glyph, attempt, and the input
// artifact hash; object keys embed it so reprocessing the same request maps
// to the same logical artifact. The Go normalizer computes the identical
// operation ID from its own inputs, which keeps event IDs deterministic.
public static class OperationKeys
{
    public const string StepName = "rasterize-glyph";

    public static string OperationId(string runId, string glyphInstanceId, int attempt, string inputArtifactSha256)
    {
        string input = runId + StepName + glyphInstanceId +
            attempt.ToString(CultureInfo.InvariantCulture) + inputArtifactSha256;
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input))).ToLowerInvariant();
    }

    public static string ObjectKey(string runId, int position, string glyphInstanceId, int attempt, string operationId) =>
        $"runs/{runId}/glyphs/{position}-{glyphInstanceId}/raster-attempt-{attempt}-{operationId}.png";

    // Stable RFC 4122 version-4 UUID from the first 16 bytes of the
    // operation ID, formatted byte-for-byte to match the Go
    // uuidFromOperationID derivation (Guid(byte[]) would reorder fields).
    public static string ArtifactUuid(string operationId)
    {
        var bytes = new byte[16];
        for (int i = 0; i < 16; i++)
        {
            bytes[i] = Convert.ToByte(operationId.Substring(2 * i, 2), 16);
        }
        bytes[6] = (byte)((bytes[6] & 0x0F) | 0x40);
        bytes[8] = (byte)((bytes[8] & 0x3F) | 0x80);
        return string.Create(36, bytes, (span, value) =>
        {
            int pos = 0;
            for (int i = 0; i < 16; i++)
            {
                if (i is 4 or 6 or 8 or 10)
                {
                    span[pos++] = '-';
                }
                value[i].TryFormat(span.Slice(pos, 2), out _, "x2");
                pos += 2;
            }
        });
    }
}
