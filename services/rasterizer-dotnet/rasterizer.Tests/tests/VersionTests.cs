using Rghw.Rasterizer;
using Xunit;

namespace Rghw.Rasterizer.Tests;

public class VersionTests
{
    [Fact]
    public void VersionMatchesMilestone6() =>
        Assert.Equal("0.1.0-milestone11", RasterizerVersion.Version);

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
        Assert.StartsWith("rasterizer 0.1.0-milestone11", banner);
    }

    [Fact]
    public void RenderIsDeterministic() => Assert.Equal(RasterizerBanner.Render(), RasterizerBanner.Render());
}

public class RasterLimitsTests
{
    [Fact]
    public void DefaultsAreBounded()
    {
        var limits = new RasterLimits();
        Assert.Equal(8192, limits.MaxSegments);
        Assert.Equal(2048, limits.MaxCanvasDimension);
        Assert.Equal(256.0, limits.MaxStrokeWidth);
    }

    [Fact]
    public void FromEnvironmentAppliesValidOverrides()
    {
        var limits = RasterLimits.FromEnvironment(name =>
            name == "RASTERIZER_MAX_SEGMENTS" ? "100" :
            name == "RASTERIZER_MAX_CANVAS" ? "64" : null);
        Assert.Equal(100, limits.MaxSegments);
        Assert.Equal(64, limits.MaxCanvasDimension);
    }

    [Fact]
    public void FromEnvironmentIgnoresInvalidValues()
    {
        var limits = RasterLimits.FromEnvironment(_ => "not-a-number");
        Assert.Equal(8192, limits.MaxSegments);
        Assert.Equal(2048, limits.MaxCanvasDimension);
    }
}
