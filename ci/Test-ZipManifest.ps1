param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [Parameter(Mandatory = $true)]
    [string]$ReportPath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipResolved = (Resolve-Path $ZipPath).Path
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipResolved)
try {
    $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
    $manifestEntry = $entries | Where-Object { $_.FullName -eq "MANIFEST_PACHET.sha256" }
    if (@($manifestEntry).Count -ne 1) { throw "Manifest absent sau duplicat in ZIP." }
    $reader = New-Object IO.StreamReader($manifestEntry.Open(), [Text.Encoding]::ASCII)
    try { $lines = @($reader.ReadToEnd() -split "`r?`n" | Where-Object { $_ }) }
    finally { $reader.Dispose() }
    $expected = @{}
    foreach ($line in $lines) {
        if ($line -notmatch "^([0-9a-f]{64})  (.+)$") { throw "Linie manifest invalida: $line" }
        if ($expected.ContainsKey($matches[2])) { throw "Intrare duplicata in manifest: $($matches[2])" }
        $expected[$matches[2]] = $matches[1]
    }
    $actualNames = @($entries | Where-Object { $_.FullName -ne "MANIFEST_PACHET.sha256" } |
        ForEach-Object { $_.FullName })
    $duplicates = @($actualNames | Group-Object | Where-Object { $_.Count -ne 1 })
    if ($duplicates.Count) { throw "ZIP-ul contine intrari duplicate." }
    $missing = @($expected.Keys | Where-Object { $_ -notin $actualNames })
    $extra = @($actualNames | Where-Object { $_ -notin $expected.Keys })
    if ($missing.Count -or $extra.Count) {
        throw "Manifest/ZIP difera: lipsa=$($missing -join ','); extra=$($extra -join ',')"
    }
    $wrong = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entries | Where-Object { $_.FullName -ne "MANIFEST_PACHET.sha256" }) {
        $stream = $entry.Open()
        try {
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLower() }
            finally { $sha.Dispose() }
        } finally { $stream.Dispose() }
        if ($hash -ne $expected[$entry.FullName]) { $wrong.Add($entry.FullName) }
    }
    if ($wrong.Count) { throw "Hash-uri gresite in ZIP: $($wrong -join ', ')" }
    $report = [ordered]@{
        data_ora_utc = (Get-Date).ToUniversalTime().ToString("o")
        sistem_operare = (Get-CimInstance Win32_OperatingSystem).Caption
        arhiva = $zipResolved
        sha256_arhiva = (Get-FileHash $zipResolved -Algorithm SHA256).Hash.ToLower()
        intrari_manifest = $expected.Count
        intrari_verificate = $actualNames.Count
        verdict = "PASS"
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $ReportPath
    Write-Host "ZIP_MANIFEST_WINDOWS_PASS $($expected.Count)/$($expected.Count)"
} finally {
    $archive.Dispose()
}
