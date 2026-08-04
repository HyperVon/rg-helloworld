# rasterizer-dotnet

C#/.NET gRPC rasterizer (Milestone 0 skeleton). Converts normalized line
geometry into PNGs via SkiaSharp in later milestones.

## Commands

```bash
dotnet build --nologo            # build
dotnet test --nologo             # unit tests (xUnit)
dotnet format whitespace         # format
dotnet format --verify-no-changes  # format check
```

## Coverage

```bash
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura /p:Threshold=90
```

Package versions are managed centrally in `Directory.Packages.props` at the
repository root: xunit 2.9.3, Microsoft.NET.Test.Sdk 18.8.1,
xunit.runner.visualstudio 3.1.5, coverlet.msbuild 10.0.1. The SDK version is
pinned by `global.json` at the repository root.
