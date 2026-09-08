param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $repoRoot
$outDir = Join-Path $projectRoot "public/wasm"
$outJs = Join-Path $outDir "contextvault.js"

$emcc = Get-Command em++ -ErrorAction SilentlyContinue
if (-not $emcc) {
    $emcc = Get-Command emcc -ErrorAction SilentlyContinue
}
if (-not $emcc) {
    throw "em++/emcc was not found on PATH. Activate an Emscripten SDK environment before running this script."
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$sources = @(
    "wasm/contextvault_browser_lib.cpp",
    "src/tokenizer.cpp",
    "src/io.cpp",
    "src/predictor.cpp",
    "src/builder.cpp",
    "src/codec.cpp",
    "src/c_api.cpp",
    "src/atomizer.cpp",
    "src/txt_importer.cpp"
)

$exports = "['_cv_digest_chatgpt_json_summary','_cv_digest_chatgpt_json_summary_out','_cv_digest_chatgpt_json_to_markdown','_cv_digest_chatgpt_json_to_markdown_out','_cv_free_browser_digest_result','_cv_free_browser_digest_result_ptr','_malloc','_free']"

Push-Location $repoRoot
try {
    & $emcc.Source @sources `
        -Iinclude `
        -Isrc `
        -Iwasm `
        -O3 `
        -std=c++20 `
        -s MODULARIZE=1 `
        -s EXPORT_ES6=1 `
        -s ALLOW_MEMORY_GROWTH=1 `
        -s ENVIRONMENT=web,worker `
        -s EXPORT_ALL=1 `
        -s EXPORTED_FUNCTIONS=$exports `
        -o $outJs

    if ($LASTEXITCODE -ne 0) {
        throw "Emscripten build failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}

Write-Host "Wrote $outJs"
Write-Host "Wrote $($outJs -replace '\.js$','.wasm')"
