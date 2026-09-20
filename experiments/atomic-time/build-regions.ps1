$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installation) { throw 'Visual Studio C++ tools were not found.' }
    $compiler = Get-ChildItem "$installation\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1
    New-Item -ItemType Directory -Force build | Out-Null
    & nvcc -std=c++17 -O3 -arch=native -ccbin "$($compiler.FullName)\bin\Hostx64\x64" region_cache.cu -o build/region_cache.exe
    if ($LASTEXITCODE -ne 0) { throw 'CUDA compilation failed.' }
    & ./build/region_cache.exe
    if ($LASTEXITCODE -ne 0) { throw 'Region validation failed.' }
} finally { Pop-Location }
