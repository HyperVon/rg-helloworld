using RgHello.Rasterizer;
using Xunit;

namespace RgHello.Rasterizer.Tests;

public class VersionTests
{
    [Fact]
    public void VersionMatchesSkeleton() =>
        Assert.Equal("0.0.0-skeleton", RasterizerVersion.Version);

    [Fact]
    public void VersionIsNotEmpty() =>
        Assert.False(string.IsNullOrWhiteSpace(RasterizerVersion.Version));

    [Fact]
    public void ServiceNameIsSet() => Assert.Equal("rasterizer", RasterizerVersion.ServiceName);
}

public class BannerTests
{
    [Fact]
    public void RenderIncludesServiceAndVersion()
    {
        var banner = RasterizerBanner.Render();
        Assert.StartsWith("rasterizer 0.0.0-skeleton", banner);
        Assert.Contains("Milestone 0", banner);
    }

    [Fact]
    public void RenderIsDeterministic() => Assert.Equal(RasterizerBanner.Render(), RasterizerBanner.Render());
}
