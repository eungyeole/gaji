# Rift for Windows

Rift for Windows is a native WinUI 3 desktop application targeting .NET 10 and
Windows App SDK 2.3.1. It currently opens repositories, shows history and working
copy state, renders commit patches, commits, and runs fetch/pull/push.

On Windows 10 1809 or newer with the .NET 10 SDK:

```powershell
dotnet build Rift.Windows.csproj
dotnet run --project Rift.Windows.csproj
```
