using Minio;
using Minio.DataModel.Args;

namespace RgHello.Rasterizer;

public interface IRasterStore
{
    Task PutAsync(string bucket, string objectKey, byte[] content, string contentType, CancellationToken cancellationToken);
}

// File-backed store used by the host integration harness and unit tests:
// objects land under the configured root directory, keyed by object key.
public sealed class LocalRasterStore : IRasterStore
{
    private readonly string _root;

    public LocalRasterStore(string root) => _root = root;

    public Task PutAsync(string bucket, string objectKey, byte[] content, string contentType, CancellationToken cancellationToken)
    {
        string path = Path.Combine(_root, objectKey);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, content);
        return Task.CompletedTask;
    }
}

// The only Minio-specific surface, kept narrow so the store logic stays
// unit-testable with a fake.
public interface IMinioPutClient
{
    Task PutObjectAsync(string bucketName, string objectKey, Stream stream, long size, string contentType, CancellationToken cancellationToken);
}

// Thin, untested adapter over the Minio .NET client (generated-code style
// glue; excluded from coverage like the protobuf surface).
[System.Diagnostics.CodeAnalysis.ExcludeFromCodeCoverage]
public sealed class MinioPutClientAdapter : IMinioPutClient
{
    private readonly IMinioClient _client;

    public MinioPutClientAdapter(string endpoint, string accessKey, string secretKey) =>
        _client = new MinioClient()
            .WithEndpoint(new Uri(endpoint))
            .WithCredentials(accessKey, secretKey)
            .Build();

    public Task PutObjectAsync(string bucketName, string objectKey, Stream stream, long size, string contentType, CancellationToken cancellationToken) =>
        _client.PutObjectAsync(
            new PutObjectArgs()
                .WithBucket(bucketName)
                .WithObject(objectKey)
                .WithStreamData(stream)
                .WithObjectSize(size)
                .WithContentType(contentType),
            cancellationToken);
}

public sealed class MinioRasterStore : IRasterStore
{
    private readonly IMinioPutClient _client;

    public MinioRasterStore(IMinioPutClient client) => _client = client;

    public async Task PutAsync(string bucket, string objectKey, byte[] content, string contentType, CancellationToken cancellationToken)
    {
        using var stream = new MemoryStream(content);
        await _client.PutObjectAsync(bucket, objectKey, stream, content.Length, contentType, cancellationToken);
    }
}
