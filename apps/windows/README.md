# Gaji for Windows

Gaji for Windows is a native WinUI 3 desktop application targeting .NET 10 and
Windows App SDK 2.3.1. It currently opens repositories, shows history and working
copy state, renders commit patches, commits, and runs fetch/pull/push.

On Windows 10 1809 or newer with the .NET 10 SDK and stable Rust toolchain:

```powershell
dotnet build Gaji.Windows.csproj
dotnet run --project Gaji.Windows.csproj
```

Create self-contained x64 and ARM64 ZIP packages from PowerShell:

```powershell
./scripts/package-windows.ps1
```
