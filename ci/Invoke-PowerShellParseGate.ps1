param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$rootResolved = (Resolve-Path $Root).Path
$artifactsDirectory = Join-Path $rootResolved "artifacts"
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $artifactsDirectory "RAPORT_PARSE_POWERSHELL.json"
}
elseif (-not [IO.Path]::IsPathRooted($ReportPath)) {
    $ReportPath = Join-Path $rootResolved $ReportPath
}
New-Item -ItemType Directory -Force (Split-Path -Parent $ReportPath) | Out-Null

function Escape-WorkflowData([string]$Value, [switch]$Property) {
    if ($null -eq $Value) { return "" }
    $escaped = $Value.Replace("%", "%25").Replace("`r", "%0D").Replace("`n", "%0A")
    if ($Property) {
        $escaped = $escaped.Replace(":", "%3A").Replace(",", "%2C")
    }
    return $escaped
}

function Write-ParseReport([string]$Verdict, [object[]]$Failures, [int]$FileCount) {
    $osCaption = try {
        (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
    }
    catch {
        [Environment]::OSVersion.VersionString
    }
    [ordered]@{
        data_ora_utc = (Get-Date).ToUniversalTime().ToString("o")
        sistem_operare = $osCaption
        powershell = $PSVersionTable.PSVersion.ToString()
        cale_executabil = (Get-Process -Id $PID).Path
        radacina_verificata = $rootResolved
        fisiere_ps1 = $FileCount
        verdict = $Verdict
        erori = @($Failures)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}

$files = @(Get-ChildItem -Path $rootResolved -Recurse -File -Filter "*.ps1" |
    Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" } |
    Sort-Object FullName)
if ($files.Count -eq 0) {
    $failure = [ordered]@{
        fisier = ""
        linie = 0
        coloana = 0
        cod = "NoPowerShellFiles"
        mesaj = "Nu exista fisiere PS1 in radacina verificata."
        text = ""
    }
    Write-ParseReport "FAIL" @($failure) 0
    Write-Host "::error::POWERSHELL_PARSE_GATE_FAIL%3A nu exista fisiere PS1 in radacina verificata"
    exit 1
}

$failures = @()
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in @($errors)) {
        $relativePath = $file.FullName.Substring($rootResolved.Length).TrimStart('\', '/')
        $failure = [ordered]@{
            fisier = $relativePath
            linie = $parseError.Extent.StartLineNumber
            coloana = $parseError.Extent.StartColumnNumber
            cod = $parseError.ErrorId
            mesaj = $parseError.Message
            text = $parseError.Extent.Text
        }
        $failures += $failure

        $annotationPath = Escape-WorkflowData $relativePath -Property
        $annotationMessage = Escape-WorkflowData (
            "$($parseError.ErrorId): $($parseError.Message) | text=$($parseError.Extent.Text)")
        Write-Host (
            "::error file=$annotationPath,line=$($failure.linie),col=$($failure.coloana)::$annotationMessage")
    }
}

if ($failures.Count -gt 0) {
    Write-ParseReport "FAIL" @($failures) $files.Count
    $failures | ConvertTo-Json -Depth 8
    [Console]::Error.WriteLine("POWERSHELL_PARSE_GATE_FAIL: $($failures.Count) erori; raport=$ReportPath")
    exit 1
}

Write-ParseReport "PASS" @() $files.Count
Write-Host "POWERSHELL_PARSE_GATE_PASS $($files.Count)"
exit 0
