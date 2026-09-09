param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
$rootResolved = (Resolve-Path $Root).Path
$files = @(Get-ChildItem -Path $rootResolved -Recurse -File -Filter "*.ps1" |
    Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" } |
    Sort-Object FullName)
if ($files.Count -eq 0) {
    Write-Error "POWERSHELL_PARSE_GATE_FAIL: nu exista fisiere PS1 in $rootResolved"
    exit 1
}

$failures = New-Object System.Collections.Generic.List[object]
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $failures.Add([ordered]@{
            fisier = $file.FullName
            linie = $parseError.Extent.StartLineNumber
            coloana = $parseError.Extent.StartColumnNumber
            cod = $parseError.ErrorId
            mesaj = $parseError.Message
            text = $parseError.Extent.Text
        })
    }
}

if ($failures.Count -gt 0) {
    $failures | ConvertTo-Json -Depth 6
    Write-Error "POWERSHELL_PARSE_GATE_FAIL: $($failures.Count) erori"
    exit 1
}

Write-Host "POWERSHELL_PARSE_GATE_PASS $($files.Count)"
exit 0
