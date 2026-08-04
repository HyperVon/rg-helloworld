namespace RgHello.Rasterizer;

public static class RasterizerBanner
{
    public static string Render() =>
        $"{RasterizerVersion.ServiceName} {RasterizerVersion.Version} (Milestone 0 skeleton)";
}
