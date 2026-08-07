namespace Rghw.Rasterizer;

public static class RasterizerBanner
{
    public static string Render() =>
        $"{RasterizerVersion.ServiceName} {RasterizerVersion.Version}";
}
