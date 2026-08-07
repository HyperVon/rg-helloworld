using Rghw.Rasterizer.V1;
using Xunit;

namespace Rghw.Rasterizer.Tests;

public class LocalRasterStoreTests
{
    [Fact]
    public async Task PutWritesFileUnderRoot()
    {
        string root = Path.Combine(Path.GetTempPath(), "rghw-raster-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new LocalRasterStore(root);
            byte[] content = { 1, 2, 3, 4 };
            await store.PutAsync("bucket", "runs/r/glyphs/0-x/raster-attempt-1-op.png", content, "image/png", CancellationToken.None);

            string path = Path.Combine(root, "runs", "r", "glyphs", "0-x", "raster-attempt-1-op.png");
            Assert.Equal(content, await File.ReadAllBytesAsync(path));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task PutCreatesNestedDirectories()
    {
        string root = Path.Combine(Path.GetTempPath(), "rghw-raster-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new LocalRasterStore(root);
            await store.PutAsync("bucket", "deep/nested/key.png", new byte[] { 9 }, "image/png", CancellationToken.None);
            Assert.True(File.Exists(Path.Combine(root, "deep", "nested", "key.png")));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}

public class MinioRasterStoreTests
{
    [Fact]
    public async Task PutForwardsArgumentsAndContent()
    {
        var fake = new FakePutClient();
        var store = new MinioRasterStore(fake);
        byte[] content = { 5, 6, 7 };
        await store.PutAsync("artifacts", "runs/r/glyphs/0-x/raster.png", content, "image/png", CancellationToken.None);

        Assert.Equal("artifacts", fake.Bucket);
        Assert.Equal("runs/r/glyphs/0-x/raster.png", fake.ObjectKey);
        Assert.Equal(content, fake.Content);
        Assert.Equal(content.Length, fake.Size);
        Assert.Equal("image/png", fake.ContentType);
    }

    [Fact]
    public async Task PutHonorsCancellationToken()
    {
        var fake = new FakePutClient();
        var store = new MinioRasterStore(fake);
        using var cts = new CancellationTokenSource();
        await store.PutAsync("b", "k", new byte[] { 1 }, "image/png", cts.Token);
        Assert.Equal(cts.Token, fake.Token);
    }
}

public sealed class FakePutClient : IMinioPutClient
{
    public string? Bucket { get; private set; }

    public string? ObjectKey { get; private set; }

    public byte[]? Content { get; private set; }

    public long Size { get; private set; }

    public string? ContentType { get; private set; }

    public CancellationToken Token { get; private set; }

    public Task PutObjectAsync(string bucketName, string objectKey, Stream stream, long size, string contentType, CancellationToken cancellationToken)
    {
        Bucket = bucketName;
        ObjectKey = objectKey;
        Size = size;
        ContentType = contentType;
        Token = cancellationToken;
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        Content = memory.ToArray();
        return Task.CompletedTask;
    }
}
