param(
    [string]$PartsDirectory = (Join-Path $PSScriptRoot "..\payload_parts"),
    [string]$Destination = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = "Stop"
$partsDirectoryResolved = (Resolve-Path $PartsDirectory).Path
$destinationResolved = (Resolve-Path $Destination).Path
$parts = @(Get-ChildItem $partsDirectoryResolved -File -Filter "EMP-UTILITY-SOURCE.zip.part*" |
    Sort-Object Name)
if ($parts.Count -eq 0) { throw "Nu exista partile arhivei sursa." }

$expectedLine = (Get-Content (Join-Path $partsDirectoryResolved "SOURCE_PAYLOAD.sha256") -Raw).Trim()
if ($expectedLine -notmatch "^([0-9a-f]{64})  EMP-UTILITY-SOURCE.zip$") {
    throw "SOURCE_PAYLOAD.sha256 are format invalid."
}
$expectedHash = $matches[1]
$archivePath = Join-Path $env:RUNNER_TEMP "EMP-UTILITY-SOURCE.zip"
$output = [IO.File]::Open($archivePath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
try {
    foreach ($part in $parts) {
        $input = [IO.File]::OpenRead($part.FullName)
        try { $input.CopyTo($output) } finally { $input.Dispose() }
    }
} finally {
    $output.Dispose()
}

$actualHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLower()
if ($actualHash -ne $expectedHash) {
    throw "Arhiva sursa reasamblata are hash gresit: $actualHash; asteptat $expectedHash"
}
if (Test-Path (Join-Path $destinationResolved "src")) {
    Remove-Item -Recurse -Force (Join-Path $destinationResolved "src")
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $destinationResolved -Force
if (-not (Test-Path (Join-Path $destinationResolved "src\MANIFEST_PACHET.sha256"))) {
    throw "Arhiva sursa nu a produs arborele src asteptat."
}
Write-Host "SOURCE_PAYLOAD_GATE_PASS $actualHash parts=$($parts.Count)"
