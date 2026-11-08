# Caramel installer for Windows.
#
#   irm https://ruz.one/caramel.ps1 | iex                  # install / update
#   $env:CARAMEL_UNINSTALL=1; irm https://ruz.one/caramel.ps1 | iex   # remove
#
# Optional: $env:CARAMEL_VERSION = "0.1.0" to install a specific version.

function Install-Caramel {
    param([switch]$Uninstall)

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072

    $repo = 'ruzgarengel/caramel-releases'
    if ($env:CARAMEL_VERSION) {
        $base = "https://github.com/$repo/releases/download/v$($env:CARAMEL_VERSION.TrimStart('v'))"
    } else {
        $base = "https://github.com/$repo/releases/latest/download"
    }
    if ($env:CARAMEL_BASE_URL) { $base = $env:CARAMEL_BASE_URL }

    $dir = Join-Path $env:LOCALAPPDATA 'Programs\Caramel'
    $exe = Join-Path $dir 'Caramel.exe'
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Caramel.lnk'
    $uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Caramel'

    function Say($m) { Write-Host "caramel " -ForegroundColor Yellow -NoNewline; Write-Host $m }
    function Ok($m) { Write-Host "  + " -ForegroundColor Green -NoNewline; Write-Host $m }

    Get-Process -Name caramel -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300

    if ($Uninstall) {
        Say 'removing Caramel'
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
        Remove-Item -Force $startMenu -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $uninstallKey -ErrorAction SilentlyContinue
        $path = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($path) {
            $new = ($path -split ';' | Where-Object { $_ -and ($_ -ne $dir) }) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $new, 'User')
        }
        Ok "removed (your macros are kept in $env:APPDATA\caramel)"
        return
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
    Say "installing Caramel for Windows ($arch)"

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("caramel-" + [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $sums = (Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS").Content
        if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }
        $asset = "caramel-windows-$arch.zip"
        if ($sums -notmatch [regex]::Escape($asset)) { $asset = 'caramel-windows-x86_64.zip' }  # x64 runs under emulation on ARM

        $zip = Join-Path $tmp $asset
        Invoke-WebRequest -UseBasicParsing "$base/$asset" -OutFile $zip
        $want = ($sums -split "`n" | Where-Object { $_ -match "\s\*?$([regex]::Escape($asset))\s*$" } | Select-Object -First 1) -replace '\s.*$', ''
        $got = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
        if (-not $want -or $want.ToLower() -ne $got) { throw "checksum mismatch for $asset" }
        Ok "downloaded and verified $asset"

        Expand-Archive -Force -Path $zip -DestinationPath $tmp
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item -Force (Join-Path $tmp 'Caramel.exe') $exe
        Unblock-File $exe
        Ok "installed $exe"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    # Start menu shortcut
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($startMenu)
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $dir
    $lnk.Description = 'Keyboard & mouse macro recorder'
    $lnk.Save()
    Ok 'Start menu shortcut added'

    # Command line: add the install folder to the user PATH
    $path = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($path -split ';') -contains $dir)) {
        [Environment]::SetEnvironmentVariable('Path', (@($path, $dir) | Where-Object { $_ }) -join ';', 'User')
        Ok "added to PATH (new terminals can run 'caramel')"
    }

    # "Apps & features" entry
    $uninstallCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:CARAMEL_UNINSTALL=1; irm https://ruz.one/caramel.ps1 | iex"'
    New-Item -Force -Path $uninstallKey | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name DisplayName -Value 'Caramel'
    Set-ItemProperty -Path $uninstallKey -Name DisplayIcon -Value $exe
    Set-ItemProperty -Path $uninstallKey -Name Publisher -Value 'Caramel'
    Set-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $dir
    Set-ItemProperty -Path $uninstallKey -Name UninstallString -Value $uninstallCmd
    Set-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -Type DWord

    Say 'done. Starting Caramel...'
    Start-Process $exe
}

Install-Caramel -Uninstall:($env:CARAMEL_UNINSTALL -eq '1')
