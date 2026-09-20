$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    if (!(Test-Path -LiteralPath 'generated/render.json')) { node tools/compile.mjs }
    Start-Process 'http://127.0.0.1:8787'
    node server.mjs
} finally { Pop-Location }
