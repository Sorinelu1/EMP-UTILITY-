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

# Sursa de baza ramane byte-identica si verificata mai sus. Aceasta corectie
# determinista permite Windows Server exclusiv in runnerul GitHub Actions;
# instalarea obisnuita ramane limitata la Windows 10/11.
$installerPath = Join-Path $destinationResolved "src\resurse\instalator\instaleaza_platforma.ps1"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Lipseste instalatorul care trebuie corectat pentru runnerul CI."
}
$installerText = Get-Content -LiteralPath $installerPath -Raw -Encoding UTF8
$oldCheck = '$eWin = $os.Caption -match "Windows (10|11)"'
$oldReport = 'Pas 1 "Detectare Windows 10/11" ($(if ($eWin) {"PASS"} else {"FAIL"})) $os.Caption'
if ($installerText.IndexOf($oldCheck, [StringComparison]::Ordinal) -lt 0 -or $installerText.IndexOf($oldCheck, [StringComparison]::Ordinal) -ne $installerText.LastIndexOf($oldCheck, [StringComparison]::Ordinal)) {
    throw "Corectia CI nu poate fi aplicata sigur: verificarea Windows de baza nu este unica."
}
if ($installerText.IndexOf($oldReport, [StringComparison]::Ordinal) -lt 0 -or $installerText.IndexOf($oldReport, [StringComparison]::Ordinal) -ne $installerText.LastIndexOf($oldReport, [StringComparison]::Ordinal)) {
    throw "Corectia CI nu poate fi aplicata sigur: raportarea Windows de baza nu este unica."
}
$newCheck = @'
$desktopSupported = $os.Caption -match "Windows (10|11)"
$ciServerSupported = ($os.Caption -match "Windows Server" -and $env:EMP_UTILITY_CLEAN_RUNNER -eq "1" -and $env:GITHUB_ACTIONS -eq "true" -and $env:RUNNER_OS -eq "Windows")
$eWin = $desktopSupported -or $ciServerSupported
$windowsMode = if ($desktopSupported) { "desktop" } elseif ($ciServerSupported) { "github-actions-server" } else { "nesuportat" }
'@
$newReport = 'Pas 1 "Detectare Windows compatibil" ($(if ($eWin) {"PASS"} else {"FAIL"})) "$($os.Caption); mod=$windowsMode"'
$installerText = $installerText.Replace($oldCheck, $newCheck.TrimEnd([char[]]"`r`n"))
$installerText = $installerText.Replace($oldReport, $newReport)
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($installerPath, $installerText, $utf8Bom)
Write-Host "SOURCE_COMPATIBILITY_PATCH_PASS desktop=Windows10/11 ci=GitHubActions-WindowsServer"
Write-Host "SOURCE_PAYLOAD_GATE_PASS $actualHash parts=$($parts.Count)"
