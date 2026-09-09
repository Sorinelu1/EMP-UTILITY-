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

function Inlocuieste-Unic([string]$text, [string]$vechi, [string]$nou, [string]$eticheta) {
    $prima = $text.IndexOf($vechi, [StringComparison]::Ordinal)
    $ultima = $text.LastIndexOf($vechi, [StringComparison]::Ordinal)
    if ($prima -lt 0 -or $prima -ne $ultima) {
        throw "Corectia nu poate fi aplicata sigur ($eticheta): ancora nu este unica."
    }
    return $text.Replace($vechi, $nou)
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

# python.exe -I elimina directorul scriptului din sys.path. Lansatorul vechi
# pornea direct app\platforma_pte.py si acesta nu putea importa modulele-surori.
# Un bootstrap Python instalat adauga explicit app\ in sys.path, pastrand -I.
$oldLauncherCommand = '"%EMP_ROOT%\Runtime\Python\python.exe" -I "%~dp0app\platforma_pte.py" >>"%PTE_DIR_DATE%\loguri\pornire_jurnal.txt" 2>&1'
$newLauncherCommand = '"%EMP_ROOT%\Runtime\Python\python.exe" -I "%~dp0PORNESTE_EMP_UTILITY.py" >>"%PTE_DIR_DATE%\loguri\pornire_jurnal.txt" 2>&1'
$installerText = Inlocuieste-Unic $installerText $oldLauncherCommand $newLauncherCommand "comanda lansator izolat"
$launcherComment = '# lansator FARA consola: un .vbs porneste .bat-ul ascuns si arata un mesaj'
$launcherPythonBlock = @(
    '$lansatorPython = Join-Path $instalDir "PORNESTE_EMP_UTILITY.py"',
    "@'",
    'from __future__ import annotations',
    '',
    'import os',
    'import sys',
    '',
    '',
    'APP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "app")',
    'sys.path.insert(0, APP_DIR)',
    'os.chdir(APP_DIR)',
    '',
    'import platforma_pte',
    '',
    '',
    'if os.environ.get("EMP_UTILITY_HEADLESS", "").strip() == "1":',
    '    platforma_pte.porneste(deschide_browser=False)',
    'else:',
    '    platforma_pte._porneste_cu_jurnal()',
    "'@ | Out-File -Encoding UTF8 `$lansatorPython"
) -join "`r`n"
$installerText = Inlocuieste-Unic $installerText $launcherComment ($launcherPythonBlock.TrimEnd([char[]]"`r`n") + "`r`n" + $launcherComment) "bootstrap Python al lansatorului"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($installerPath, $installerText, $utf8Bom)

# Validatorul instalat probeaza cele trei puncte de pornire in mod headless.
# Fiecare proba are termen global finit si produce diagnostic de proces, port
# si jurnal inainte de FAIL; cererile loopback ocolesc explicit orice proxy CI.
$validatorPath = Join-Path $destinationResolved "src\resurse\teste\VALIDEAZA_BUILD_WINDOWS.ps1"
if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
    throw "Lipseste validatorul Windows care trebuie corectat."
}
$validatorText = Get-Content -LiteralPath $validatorPath -Raw -Encoding UTF8
$oldFunctionPattern = '(?s)function Porneste-Si-Verifica\(\[string\]\$cale\) \{.*?\r?\n\}\r?\n\r?\n(?=try \{)'
$functionMatches = [regex]::Matches($validatorText, $oldFunctionPattern)
if ($functionMatches.Count -ne 1) {
    throw "Corectia validatorului nu poate fi aplicata sigur: functia veche nu este unica."
}
$newFunctions = @'
function Cere-Http-Local([string]$cale, [int]$timeoutMs = 500) {
    $cerere = [Net.HttpWebRequest]::Create($cale)
    $cerere.Proxy = $null
    $cerere.Timeout = $timeoutMs
    $cerere.ReadWriteTimeout = $timeoutMs
    $raspuns = $cerere.GetResponse()
    try {
        $cititor = New-Object IO.StreamReader($raspuns.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $continut = $cititor.ReadToEnd() } finally { $cititor.Dispose() }
        return [pscustomobject]@{
            StatusCode = [int]$raspuns.StatusCode
            Content = $continut
        }
    } finally {
        $raspuns.Close()
    }
}

function Asteapta-Server-Local([int]$timeoutSecunde = 30) {
    $limita = [DateTime]::UtcNow.AddSeconds($timeoutSecunde)
    while ([DateTime]::UtcNow -lt $limita) {
        foreach ($port in 8765..8784) {
            try {
                $r = Cere-Http-Local "http://127.0.0.1:$port/api/versiune" 300
                if ($r.StatusCode -eq 200) {
                    $info = $r.Content | ConvertFrom-Json
                    if ($info.platforma -eq "EMP UTILITY") {
                        return [pscustomobject]@{ Port = $port; Versiune = $info.versiune }
                    }
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Scrie-Diagnostic-Lansator([string]$eticheta, [string]$cale) {
    $destinatie = Join-Path $Iesire ("DIAGNOSTIC_LANSATOR_" + $eticheta + ".txt")
    $linii = New-Object System.Collections.Generic.List[string]
    $linii.Add("data_ora_utc=" + (Get-Date).ToUniversalTime().ToString("o"))
    $linii.Add("lansator=" + $cale)
    $linii.Add("python_privat=" + $script:pyPrivat)
    $linii.Add("procese_python_private:")
    try {
        @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction Stop |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $script:pyPrivat }) |
            ForEach-Object { $linii.Add("PID=$($_.ProcessId) CMD=$($_.CommandLine)") }
    } catch {
        $linii.Add("PROCESE_INDISPONIBILE: $($_.Exception.Message)")
    }
    $linii.Add("porturi_locale_listen_8765_8784:")
    try {
        @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalPort -ge 8765 -and $_.LocalPort -le 8784 }) |
            ForEach-Object { $linii.Add("$($_.LocalAddress):$($_.LocalPort) PID=$($_.OwningProcess)") }
    } catch {
        $linii.Add("PORTURI_INDISPONIBILE: $($_.Exception.Message)")
    }
    $jurnalPornire = Join-Path (Join-Path $env:LOCALAPPDATA "EMPUtility\Data\loguri") "pornire_jurnal.txt"
    $linii.Add("jurnal_pornire=" + $jurnalPornire)
    if (Test-Path $jurnalPornire) {
        $linii.AddRange([string[]]@(Get-Content $jurnalPornire -Tail 200 -ErrorAction SilentlyContinue))
    } else {
        $linii.Add("JURNAL_PORNIRE_LIPSA")
    }
    $linii | Set-Content -Encoding UTF8 $destinatie
}

function Porneste-Si-Verifica([string]$cale, [string]$eticheta) {
    Opreste-Python-Privat
    $headlessInitial = $env:EMP_UTILITY_HEADLESS
    try {
        $env:EMP_UTILITY_HEADLESS = "1"
        Start-Process -FilePath $cale | Out-Null
        $server = Asteapta-Server-Local 30
        if (-not $server) {
            Scrie-Diagnostic-Lansator $eticheta $cale
            return $false
        }
        return $true
    } finally {
        if ($null -eq $headlessInitial) {
            Remove-Item Env:\EMP_UTILITY_HEADLESS -ErrorAction SilentlyContinue
        } else {
            $env:EMP_UTILITY_HEADLESS = $headlessInitial
        }
        Opreste-Python-Privat
    }
}

'@
$functieVeche = $functionMatches[0]
$validatorText = $validatorText.Substring(0, $functieVeche.Index) + $newFunctions +
    $validatorText.Substring($functieVeche.Index + $functieVeche.Length)
$validatorText = Inlocuieste-Unic $validatorText '$batPornire = Join-Path $app "PORNESTE_PLATFORMA.bat"' ('$batPornire = Join-Path $app "PORNESTE_PLATFORMA.bat"' + "`r`n" + '    $pythonPornire = Join-Path $app "PORNESTE_EMP_UTILITY.py"') "cale bootstrap Python"
$validatorText = Inlocuieste-Unic $validatorText '$continutBat = $(if (Test-Path $batPornire) { Get-Content $batPornire -Raw } else { "" })' ('$continutBat = $(if (Test-Path $batPornire) { Get-Content $batPornire -Raw } else { "" })' + "`r`n" + '    $continutPython = $(if (Test-Path $pythonPornire) { Get-Content $pythonPornire -Raw } else { "" })') "continut bootstrap Python"
$validatorText = Inlocuieste-Unic $validatorText '                  $continutBat -match ''pornire_jurnal\.txt'')' ('                  $continutBat -match ''PORNESTE_EMP_UTILITY\.py'' -and' + "`r`n" + '                  $continutBat -match ''pornire_jurnal\.txt'')') "semantica BAT"
$oldSemantic = '$semantic = ((Test-Path $vbs) -and (Test-Path $batPornire) -and'
$newSemantic = @'
$pythonIzolat = ($continutPython -match 'sys\.path\.insert\(0, APP_DIR\)' -and
                     $continutPython -match 'EMP_UTILITY_HEADLESS' -and
                     $continutPython -match 'deschide_browser=False')
    $semantic = ((Test-Path $vbs) -and (Test-Path $batPornire) -and (Test-Path $pythonPornire) -and
        $pythonIzolat -and
'@
$validatorText = Inlocuieste-Unic $validatorText $oldSemantic $newSemantic.TrimEnd([char[]]"`r`n") "semantica bootstrap izolat"
$validatorText = Inlocuieste-Unic $validatorText '$direct = Porneste-Si-Verifica $vbs' '$direct = Porneste-Si-Verifica $vbs "vbs"' "proba VBS"
$validatorText = Inlocuieste-Unic $validatorText '$direct = Porneste-Si-Verifica $vbs "vbs"' ('$direct = Porneste-Si-Verifica $vbs "vbs"' + "`r`n" + '        if (-not $direct) { throw "Lansatorul VBS nu a pornit serverul in 30 de secunde" }') "fail rapid VBS"
$validatorText = Inlocuieste-Unic $validatorText '$desktopOk = Porneste-Si-Verifica $desktop' '$desktopOk = Porneste-Si-Verifica $desktop "desktop"' "proba Desktop"
$validatorText = Inlocuieste-Unic $validatorText '$desktopOk = Porneste-Si-Verifica $desktop "desktop"' ('$desktopOk = Porneste-Si-Verifica $desktop "desktop"' + "`r`n" + '        if (-not $desktopOk) { throw "Scurtatura Desktop nu a pornit serverul in 30 de secunde" }') "fail rapid Desktop"
$validatorText = Inlocuieste-Unic $validatorText '$startOk = Porneste-Si-Verifica $start' '$startOk = Porneste-Si-Verifica $start "start_menu"' "proba Start"
$validatorText = Inlocuieste-Unic $validatorText '$startOk = Porneste-Si-Verifica $start "start_menu"' ('$startOk = Porneste-Si-Verifica $start "start_menu"' + "`r`n" + '        if (-not $startOk) { throw "Scurtatura Start nu a pornit serverul in 30 de secunde" }') "fail rapid Start"
[IO.File]::WriteAllText($validatorPath, $validatorText, $utf8Bom)
Write-Host "SOURCE_COMPATIBILITY_PATCH_PASS desktop=Windows10/11 ci=GitHubActions-WindowsServer"
Write-Host "SOURCE_LAUNCHER_PATCH_PASS isolated=1 headless_ci=1 timeout_seconds=30 diagnostics=1"
Write-Host "SOURCE_PAYLOAD_GATE_PASS $actualHash parts=$($parts.Count)"
