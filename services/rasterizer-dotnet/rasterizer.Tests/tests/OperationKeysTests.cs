using System.Security.Cryptography;
using System.Text;
using Xunit;

namespace Rghw.Rasterizer.Tests;

public class OperationKeysTests
{
    private const string RunId = "22222222-2222-4222-8222-222222222222";
    private const string GlyphId = "55555555-5555-4555-8555-555555555555";
    private const string InputHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    [Fact]
    public void OperationIdMatchesKnownAnswer()
    {
        // SHA-256(runId + "rasterize-glyph" + glyphId + "1" + inputHash)
        string expected = "e37d2492663e163e7af62c2b41c937f1b1f806860ae4d7656765e40e3ed3bf62";
        Assert.Equal(expected, OperationKeys.OperationId(RunId, GlyphId, 1, InputHash));
    }

    [Fact]
    public void OperationIdIsDeterministic()
    {
        string first = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        string second = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        Assert.Equal(first, second);
    }

    [Fact]
    public void OperationIdChangesWithAttempt()
    {
        string first = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        string second = OperationKeys.OperationId(RunId, GlyphId, 2, InputHash);
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void ObjectKeyEmbedsOperationId()
    {
        string operationId = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        string key = OperationKeys.ObjectKey(RunId, 0, GlyphId, 1, operationId);
        Assert.Equal(
            $"runs/{RunId}/glyphs/0-{GlyphId}/raster-attempt-1-{operationId}.png",
            key);
    }

    [Fact]
    public void ArtifactUuidIsRfc4122Version4()
    {
        string operationId = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        string uuid = OperationKeys.ArtifactUuid(operationId);
        Assert.Equal(36, uuid.Length);
        Assert.Equal('4', uuid[14]);
        Assert.Contains(uuid[19], new[] { '8', '9', 'a', 'b' });
    }

    [Fact]
    public void ArtifactUuidIsDeterministic()
    {
        string operationId = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        Assert.Equal(OperationKeys.ArtifactUuid(operationId), OperationKeys.ArtifactUuid(operationId));
    }

    [Fact]
    public void ArtifactUuidMatchesGoDerivation()
    {
        // Mirrors the Go uuidFromOperationID layout: bytes in order, version
        // nibble at byte index 6, variant nibble at byte index 8, formatted
        // as 8-4-4-4-12 lowercase hex.
        string operationId = OperationKeys.OperationId(RunId, GlyphId, 1, InputHash);
        byte[] digest = SHA256.HashData(Encoding.UTF8.GetBytes(
            RunId + OperationKeys.StepName + GlyphId + "1" + InputHash));
        var expected = new byte[16];
        Array.Copy(digest, expected, 16);
        expected[6] = (byte)((expected[6] & 0x0F) | 0x40);
        expected[8] = (byte)((expected[8] & 0x3F) | 0x80);
        string goStyle =
            Convert.ToHexString(expected).ToLowerInvariant()
            .Insert(8, "-").Insert(13, "-").Insert(18, "-").Insert(23, "-");
        Assert.Equal(goStyle, OperationKeys.ArtifactUuid(operationId));
    }
}
