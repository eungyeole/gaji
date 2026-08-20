$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $ProjectRoot "apps/windows/Gaji.Windows.csproj"
$OutputRoot = Join-Path $ProjectRoot "dist/windows"

foreach ($Architecture in @("x64", "arm64")) {
    $Runtime = "win-$Architecture"
    $PublishDirectory = Join-Path $OutputRoot $Runtime
    $RustTarget = if ($Architecture -eq "arm64") { "aarch64-pc-windows-msvc" } else { "x86_64-pc-windows-msvc" }
    rustup target add $RustTarget
    cargo build --manifest-path (Join-Path $ProjectRoot "Cargo.toml") -p gaji-ffi --release --target $RustTarget
    dotnet publish $Project `
        --configuration Release `
        --runtime $Runtime `
        --self-contained true `
        --output $PublishDirectory `
        -p:Platform=$Architecture `
        -p:PublishReadyToRun=true

    $Archive = Join-Path $OutputRoot "Gaji-$Runtime.zip"
    Compress-Archive -Path (Join-Path $PublishDirectory "*") -DestinationPath $Archive -Force
}
