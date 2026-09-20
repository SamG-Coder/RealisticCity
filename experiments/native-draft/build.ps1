$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $finder = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $installation = & $finder -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installation) { throw 'Visual Studio C++ tools are required.' }
    $compiler = Get-ChildItem "$installation\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1
    New-Item -ItemType Directory -Force build | Out-Null
    & nvcc -std=c++17 -O3 -arch=native -ccbin "$($compiler.FullName)\bin\Hostx64\x64" building.cu -o build/building.exe -Xlinker user32.lib -Xlinker gdi32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native CUDA build failed.' }
    & ./build/building.exe --self-test
    if ($LASTEXITCODE -ne 0) { throw 'Walkthrough validation failed.' }
} finally { Pop-Location }
