param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [Parameter(Mandatory = $true)]
    [string]$ArtifactsDirectory
)

$ErrorActionPreference = "Stop"
$zipResolved = (Resolve-Path $ZipPath).Path
New-Item -ItemType Directory -Force -Path $ArtifactsDirectory | Out-Null
$artifactsResolved = (Resolve-Path $ArtifactsDirectory).Path
$packageHash = (Get-FileHash $zipResolved -Algorithm SHA256).Hash.ToLower()
$sourceCommit = $env:GITHUB_SHA
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
$runIdentity = "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
$packageDir = Join-Path $env:RUNNER_TEMP "EMP-UTILITY-PACHET"
$empRoot = Join-Path $env:LOCALAPPDATA "EMPUtility"
$privatePython = Join-Path $empRoot "Runtime\Python\python.exe"
$privateTesseract = Join-Path $empRoot "Runtime\Tesseract\tesseract.exe"
$rules = New-Object System.Collections.Generic.List[string]
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [bool]$Ok, $Observed) {
    $script:checks.Add([ordered]@{nume=$Name; verdict=$(if ($Ok) {"PASS"} else {"FAIL"}); obtinut=$Observed})
    if (-not $Ok) { throw "$Name FAIL: $Observed" }
}

function Write-CiReport([string]$Verdict, $Failure = $null) {
    $report = [ordered]@{
        data_ora_utc = (Get-Date).ToUniversalTime().ToString("o")
        produs = "EMP UTILITY"
        versiune = "1.3"
        identificator_sursa = "EMP-UTILITY-v1.3-R4-GitHub-Actions"
        commit_sursa = $sourceCommit
        sistem_operare = $osCaption
        arhiva = $zipResolved
        sha256_arhiva = $packageHash
        cale_executabil_utilizat = $privatePython
        runner = [ordered]@{
            url = $runIdentity
            run_id = $env:GITHUB_RUN_ID
            run_attempt = $env:GITHUB_RUN_ATTEMPT
            runner_name = $env:RUNNER_NAME
            runner_os = $env:RUNNER_OS
            runner_arch = $env:RUNNER_ARCH
        }
        intrare_test = "ZIP construit in job si bootstrap 00_INSTALEAZA_SI_PORNESTE_EMP_UTILITY.bat"
        rezultat_asteptat = "toate portile automate Windows PASS"
        verificari = $script:checks
        eroare = $Failure
        verdict = $Verdict
    }
    $json = Join-Path $artifactsResolved "RAPORT_CI_WINDOWS.json"
    $report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $json
    $rows = foreach ($check in $script:checks) {
        "<tr><td>$([Net.WebUtility]::HtmlEncode($check.nume))</td><td>$($check.verdict)</td><td>$([Net.WebUtility]::HtmlEncode("$($check.obtinut)"))</td></tr>"
    }
    $html = @(
        "<!doctype html><html><head><meta charset='utf-8'><title>EMP UTILITY CI Windows</title></head><body>",
        "<h1>EMP UTILITY 1.3 - GitHub Actions Windows</h1>",
        "<p><b>OS:</b> $([Net.WebUtility]::HtmlEncode($osCaption))</p>",
        "<p><b>Run:</b> $([Net.WebUtility]::HtmlEncode($runIdentity))</p>",
        "<p><b>SHA-256:</b> $packageHash</p>",
        "<p><b>Verdict:</b> $Verdict</p>",
        "<table border='1' cellspacing='0' cellpadding='6'><tr><th>Poarta</th><th>Verdict</th><th>Obtinut</th></tr>",
        ($rows -join "`n"), "</table>",
        $(if ($Failure) { "<pre>$([Net.WebUtility]::HtmlEncode("$Failure"))</pre>" } else { "" }),
        "</body></html>"
    ) -join "`n"
    $html | Set-Content -Encoding UTF8 (Join-Path $artifactsResolved "RAPORT_CI_WINDOWS.html")
}

function Stop-PrivatePython {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $privatePython } |
        ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
}

function Invoke-LocalHttp([string]$Uri, [int]$TimeoutMs = 500) {
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.Proxy = $null
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $response = $request.GetResponse()
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Content = $content
            Headers = $response.Headers
        }
    } finally {
        $response.Close()
    }
}

function Wait-LocalServer([int]$TimeoutSeconds = 30) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        foreach ($port in 8765..8784) {
            try {
                $apiResult = Invoke-LocalHttp "http://127.0.0.1:$port/api/versiune" 300
                if ($apiResult.StatusCode -ne 200) { continue }
                $versionResult = $apiResult.Content | ConvertFrom-Json
                if ($versionResult.platforma -ne "EMP UTILITY") { continue }
                $pageResult = Invoke-LocalHttp "http://127.0.0.1:$port/" 700
                if ($pageResult.StatusCode -eq 200) {
                    return [pscustomobject]@{
                        Port = $port
                        Api = $apiResult
                        Page = $pageResult
                    }
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Write-ServerDiagnostic([string]$Reason) {
    $diagnosticPath = Join-Path $artifactsResolved "DIAGNOSTIC_SERVER_START.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("data_ora_utc=" + (Get-Date).ToUniversalTime().ToString("o"))
    $lines.Add("motiv=" + $Reason)
    $lines.Add("python_privat=" + $privatePython)
    $lines.Add("procese_python_private:")
    try {
        @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction Stop |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $privatePython }) |
            ForEach-Object { $lines.Add("PID=$($_.ProcessId) CMD=$($_.CommandLine)") }
    } catch {
        $lines.Add("PROCESE_INDISPONIBILE: $($_.Exception.Message)")
    }
    $lines.Add("porturi_locale_listen_8765_8784:")
    try {
        @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalPort -ge 8765 -and $_.LocalPort -le 8784 }) |
            ForEach-Object { $lines.Add("$($_.LocalAddress):$($_.LocalPort) PID=$($_.OwningProcess)") }
    } catch {
        $lines.Add("PORTURI_INDISPONIBILE: $($_.Exception.Message)")
    }
    $startupLog = Join-Path $empRoot "Data\loguri\pornire_jurnal.txt"
    $lines.Add("jurnal_pornire=" + $startupLog)
    if (Test-Path $startupLog) {
        $lines.AddRange([string[]]@(Get-Content $startupLog -Tail 250 -ErrorAction SilentlyContinue))
    } else {
        $lines.Add("JURNAL_PORNIRE_LIPSA")
    }
    $lines | Set-Content -Encoding UTF8 $diagnosticPath
}

try {
    if (Test-Path $packageDir) { Remove-Item -Recurse -Force $packageDir }
    New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
    Expand-Archive -LiteralPath $zipResolved -DestinationPath $packageDir -Force
    $manifestReportPath = Join-Path $artifactsResolved "RAPORT_MANIFEST_ZIP_WINDOWS.json"
    & (Join-Path $PSScriptRoot "Test-ZipManifest.ps1") -ZipPath $zipResolved -ReportPath $manifestReportPath
    $manifestReport = Get-Content $manifestReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Check "Hash si manifest din ZIP" ($manifestReport.verdict -eq "PASS" -and $manifestReport.sha256_arhiva -eq $packageHash) $packageHash

    $parseLog = & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Invoke-PowerShellParseGate.ps1") -Root $packageDir 2>&1
    Add-Check "Parser Windows PowerShell pentru toate fisierele PS1" ($LASTEXITCODE -eq 0) ($parseLog -join "`n")

    if (Test-Path $empRoot) { Remove-Item -Recurse -Force $empRoot }
    $programsToBlock = @(
        "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe",
        $privatePython,
        $privateTesseract
    )
    foreach ($program in $programsToBlock) {
        $ruleName = "EMPUtility-CI-$([guid]::NewGuid().ToString('N'))"
        New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Action Block -Program $program -Profile Any | Out-Null
        $rules.Add($ruleName)
    }
    $env:HTTP_PROXY = "http://127.0.0.1:9"
    $env:HTTPS_PROXY = "http://127.0.0.1:9"
    $env:NO_PROXY = "127.0.0.1,localhost"
    $env:EMP_UTILITY_CLEAN_RUNNER = "1"
    $env:EMP_UTILITY_HEADLESS = "1"

    $bootstrap = Join-Path $packageDir "00_INSTALEAZA_SI_PORNESTE_EMP_UTILITY.bat"
    $bootstrapOutput = & $env:ComSpec /d /c "`"$bootstrap`"" 2>&1
    $bootstrapOutput | Set-Content -Encoding UTF8 (Join-Path $artifactsResolved "LOG_BOOTSTRAP_WINDOWS.txt")
    Add-Check "Bootstrap prin punctul unic de pornire" ($LASTEXITCODE -eq 0) ($bootstrapOutput -join "`n")

    $requiredReports = @(
        "RAPORT_BOOTSTRAP.json", "RAPORT_BUILD.json", "RAPORT_IMPORT_GATE.json",
        "RAPORT_WINDOWS_CURAT.json", "RAPORT_INSTALARE.html", "RAPORT_OCR.json",
        "RAPORT_GIS.json", "RAPORT_F1_F5.json", "RAPORT_IZOLARE_PROIECTE.json",
        "RAPORT_EXPORTURI.json", "RAPORT_OFFLINE.json", "LOGURI_WINDOWS.zip",
        "DOCUMENTE_TEST_GENERATE.zip"
    )
    $reportsDir = Join-Path $empRoot "rapoarte"
    foreach ($name in $requiredReports) {
        $path = Join-Path $reportsDir $name
        Add-Check "Raport generat: $name" (Test-Path $path) $path
        Copy-Item $path $artifactsResolved -Force
    }
    foreach ($name in $requiredReports | Where-Object { $_ -like "*.json" }) {
        $obj = Get-Content (Join-Path $reportsDir $name) -Raw -Encoding UTF8 | ConvertFrom-Json
        Add-Check "Raport PASS pe Windows: $name" ($obj.verdict -eq "PASS" -and "$($obj.sistem_operare)" -match "Windows") "$($obj.verdict); $($obj.sistem_operare)"
    }

    $serverResult = Wait-LocalServer 30
    if (-not $serverResult) {
        Write-ServerDiagnostic "Niciun server EMP UTILITY nu a raspuns in maximum 30 de secunde."
        throw "Serverul local nu a pornit in maximum 30 de secunde; vezi DIAGNOSTIC_SERVER_START.txt"
    }
    $api = $serverResult.Api; $page = $serverResult.Page; $portFound = $serverResult.Port
    Add-Check "Server HTTP local" ($api.StatusCode -eq 200 -and $page.StatusCode -eq 200) "port=$portFound api=$($api.StatusCode) pagina=$($page.StatusCode)"
    $versionObject = $api.Content | ConvertFrom-Json
    Add-Check "Identitate si versiune API" ($versionObject.platforma -eq "EMP UTILITY" -and "$($versionObject.versiune)" -match "^1\.3(?:\s|$)") ($api.Content)
    # Antetele anti-cache apartin raspunsului HTML de la /, nu raspunsului JSON
    # de la /api/versiune. WebHeaderCollection trateaza numele fara distinctie
    # intre litere mari si mici.
    $cacheHeader = "$($page.Headers['Cache-Control'])"
    $pragmaHeader = "$($page.Headers['Pragma'])"
    $cacheOk = (
        $cacheHeader -match "(?i)\bno-store\b" -and
        $cacheHeader -match "(?i)\bno-cache\b" -and
        $cacheHeader -match "(?i)\bmust-revalidate\b" -and
        $pragmaHeader -match "(?i)\bno-cache\b"
    )

    # Comentariile HTML pot contine istoric tehnic legitim (de exemplu 4.12.1)
    # si nu sunt continut public randat. Le eliminam inainte de controlul identitatii,
    # dar pastram scripturile si textele active in domeniul verificat.
    $activePageContent = [regex]::Replace($page.Content, "(?s)<!--.*?-->", "")
    $oldReferencePattern = "(?i)\bPlatforma[ -]PTE\b|\bEMP UTILITY\s+1\.[012](?![0-9])|\bv?4\.1[0-9](?:\.[0-9]+)?\b"
    $oldReferences = @(
        [regex]::Matches($activePageContent, $oldReferencePattern) |
            ForEach-Object { $_.Value } |
            Sort-Object -Unique
    )
    $oldPublicReference = ($oldReferences.Count -gt 0)
    $pageIdentityOk = ($activePageContent -match "(?i)\bEMP UTILITY\b")
    Add-Check "Pagina curenta si cache vechi exclus" ($pageIdentityOk -and $cacheOk -and -not $oldPublicReference) "cache=$cacheHeader; pragma=$pragmaHeader; referinte_vechi=$($oldReferences -join ', ')"

    $sentinel = Join-Path $empRoot "Data\proiecte\CI_REINSTALL_SENTINEL.txt"
    "DATE_PASTRATE" | Set-Content -Encoding ASCII $sentinel
    Stop-PrivatePython
    $installer = Join-Path $packageDir "resurse\instalator\instaleaza_platforma.ps1"
    $reinstallOutput = & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer -Actiune instaleaza -FaraPornire 2>&1
    $reinstallOutput | Set-Content -Encoding UTF8 (Join-Path $artifactsResolved "LOG_REINSTALARE_WINDOWS.txt")
    Add-Check "Reinstalare nesupravegheata" ($LASTEXITCODE -eq 0) ($reinstallOutput -join "`n")
    Add-Check "Date pastrate la reinstalare" ((Test-Path $sentinel) -and ((Get-Content $sentinel -Raw) -match "DATE_PASTRATE")) $sentinel
    $importAfter = & $privatePython -I -c "import typing_extensions; import docx; print('IMPORT_GATE_PASS')" 2>&1
    Add-Check "Import gate dupa reinstalare" ($LASTEXITCODE -eq 0 -and "$importAfter" -match "IMPORT_GATE_PASS") ($importAfter -join "`n")

    $partials = @(Get-ChildItem $empRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "(?i)\.(partial|tmp)$|_in_lucru" })
    Add-Check "Zero fisiere temporare reziduale" ($partials.Count -eq 0) ($partials.FullName -join "; ")
    Write-CiReport "PASS"
    Write-Host "BUILD WINDOWS VALIDAT PE DATE SINTETICE"
} catch {
    Write-CiReport "FAIL" $_.Exception.ToString()
    Write-Error $_
    exit 1
} finally {
    Stop-PrivatePython
    if (Test-Path (Join-Path $empRoot "rapoarte")) {
        Copy-Item (Join-Path $empRoot "rapoarte\*") $artifactsResolved -Force -ErrorAction SilentlyContinue
    }
    foreach ($rule in $rules) {
        Remove-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
    }
}
