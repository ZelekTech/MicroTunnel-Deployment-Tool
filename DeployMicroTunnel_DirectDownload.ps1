<# 
.SYNOPSIS
    Downloads the MicroTunnel installer and runs it with the provided parameters.

.USAGE
    powershell -ExecutionPolicy Bypass -File .\DeployMicroTunnel_DirectDownload.ps1 -OrgId <YOUR_ORG_ID> -ws
    powershell -ExecutionPolicy Bypass -File .\DeployMicroTunnel_DirectDownload.ps1 -OrgId <YOUR_ORG_ID> -svr
#>

param(
    [string]$OrgId,
    [switch]$ws,
    [switch]$svr
)

function Show-Usage {
    Clear-Host
    Write-Host "Usage:" -ForegroundColor Green
    Write-Host "  .\DeployMicroTunnel_DirectDownload.ps1 -OrgId <YOUR_ORG_ID> -ws" -ForegroundColor Yellow
    Write-Host "  .\DeployMicroTunnel_DirectDownload.ps1 -OrgId <YOUR_ORG_ID> -svr" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Green
    Write-Host "  -OrgId <string>   Required. Organization ID to pass to the installer." -ForegroundColor Yellow
    Write-Host "  -ws               Optional. Install as workstation." -ForegroundColor Yellow
    Write-Host "  -svr              Optional. Install as server." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Note:" -ForegroundColor Green
    Write-Host "  Exactly one of -ws or -svr must be specified.`n" -ForegroundColor Magenta
}

function Get-MicroTunnelInstaller {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    try {

        # Ensure only a single download that follows HTTP redirects and saves the final binary
        $uri = 'https://packages.microtunnel.app/MicroTunnelInstaller.exe'

        Write-Host "Downloading MicroTunnel installer..."

        $headers = @{
            'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell MicroTunnelDownloader'
        }

        # Build parameters compatible with both Windows PowerShell 5.1 and PowerShell 7+
        $invokeParams = @{
            Uri                = $uri
            OutFile            = $DestinationPath
            MaximumRedirection = 10
            ErrorAction        = 'Stop'
            Headers            = $headers
        }

        if ($PSVersionTable.PSEdition -eq 'Desktop') {
            $invokeParams.UseBasicParsing = $true
        }

        Invoke-WebRequest @invokeParams | Out-Null

        if (-not (Test-Path -LiteralPath $DestinationPath) -or ((Get-Item -LiteralPath $DestinationPath).Length -le 0)) {
            Write-Host "Downloaded file is missing or empty: $($DestinationPath)" -ForegroundColor Red
            return $false
        }

        return $true
    }
    catch {
        Write-Host "Failed to download MicroTunnel installer: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-FirstRunWizardBypass {
    # Ensure IE First Run Customize is disabled via policy
    $keyPath = 'Registry::HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\Internet Explorer\Main'
    $propertyName = 'DisableFirstRunCustomize'
    $desiredValue = 1

    try {
        if (-not (Test-Path -Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }

        $current = $null
        $reg = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue
        if ($reg -and ($reg.PSObject.Properties.Name -contains $propertyName)) {
            $current = [int]$reg.$propertyName
        }

        if ($null -eq $current -or $current -ne $desiredValue) {
            New-ItemProperty -Path $keyPath -Name $propertyName -PropertyType DWord -Value $desiredValue -Force | Out-Null
        }
        return $true
    }
    catch {
        return $false
    }
}

Set-FirstRunWizardBypass

# Validate parameters.
if ([string]::IsNullOrWhiteSpace($OrgId) `
        -or (($PSBoundParameters.ContainsKey('ws') -and $PSBoundParameters.ContainsKey('svr')) `
            -or (-not $PSBoundParameters.ContainsKey('ws') -and -not $PSBoundParameters.ContainsKey('svr')))) {
    Show-Usage
    exit 1
}

Clear-Host

try {
    # Construct a unique path for the installer in the temp directory.
    $tempDir = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $installerPath = Join-Path $tempDir "MicroTunnelInstaller_$timestamp.exe"

    # In the unlikely event the same timestamp is generated twice and a file downloaded to it that name, remove it.
    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    # Download the MicroTunnel installer to the constructed file path.
    $downloadSuccess = Get-MicroTunnelInstaller -DestinationPath $installerPath

    if ($downloadSuccess) {
        # Build the argument list for the installer.
        $argsList = @('-orgId', $OrgId)
        if ($ws) { $argsList += '-ws' }
        if ($svr) { $argsList += '-svr' }

        Write-Host "Launching installer..."
        $proc = Start-Process -FilePath $installerPath -ArgumentList $argsList -Wait -PassThru
        $exitCode = if ($proc) { $proc.ExitCode } else { 0 }

        if ($exitCode -ne 0) { Write-Error "Installer exited with code $($exitCode)" }

        exit $exitCode
    }
    else {
        Write-Error "Failed to download MicroTunnel installer."
        exit 1
    }

}
catch {
    Write-Error $_.Exception.Message
    exit 2
}
finally {
    if ($installerPath -and (Test-Path -LiteralPath $installerPath)) {
        Write-Host "Cleaning up temporary files..."
        Start-Sleep -Seconds 1
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        if ($exitCode -eq 0) {
            Write-Host "Installation completed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Installation success unknown. Please check 'C:\Program Files\Zelek\logs\MicroTunnelInstaller.log' for details." -ForegroundColor Red
        }
    }
}
