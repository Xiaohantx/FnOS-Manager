# FnOS Manager for Windows - 快速启动与构建脚本
[CmdletBinding()]
param(
    [switch]$Build,
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "==> FnOS Manager for Windows (v1.0.2)" -ForegroundColor Cyan

if ($Build) {
    Write-Host "==> 正在编译打包独立可执行文件 (win-$Arch)..." -ForegroundColor Yellow
    dotnet publish "$ProjectRoot/src/FnOSManager.csproj" -c Release -r "win-$Arch" --self-contained true -p:PublishSingleFile=true -o "$ProjectRoot/publish"
    Write-Host "==> 编译完成: $ProjectRoot/publish/FnOSManager.exe" -ForegroundColor Green
    exit 0
}

$ExePath = "$ProjectRoot/publish/FnOSManager.exe"
if (Test-Path $ExePath) {
    Start-Process $ExePath
} else {
    Write-Host "==> 正在使用 dotnet run 启动调试..." -ForegroundColor Yellow
    dotnet run --project "$ProjectRoot/src/FnOSManager.csproj"
}
