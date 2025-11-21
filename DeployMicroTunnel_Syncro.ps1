<#
.SYNOPSIS
Installs the MicroTunnel application.

.DESCRIPTION
Downloads the MicroTunnel installer from the official endpoint, performs a silent install as either Workstation or Server based on installType, logs/alerts to
Syncro RMM when the Syncro module is available, and removes the temporary installer. Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER orgId
The MicroTunnel organization identifier used during installation.

.PARAMETER installType
The installation type. Accepted values: Workstation, Server.

.INPUTS
None. Values are read from predefined variables (e.g., provided by RMM) rather than script parameters.

.OUTPUTS
None. Writes status to the console and optionally to Syncro RMM.
Exit codes: 1 for parameter/unknown errors; 2 for installer launch failures.

.EXAMPLE
$orgId = 'ORG-123'; $installType = 'Workstation'; .\DeployMicroTunnel_Syncro.ps1

.EXAMPLE
$orgId = 'ORG-123'; $installType = 'Server'; .\DeployMicroTunnel_Syncro.ps1

.NOTES
Author: Jeremy McMahan, Zelek Tech
Last Updated: 2025-09-26
Revision: 1.1
Revision History:
    1.0 - Initial version.
    1.1 - Added additional Syncro RMM logging and alerting.
Requirements:
    - Windows PowerShell 5.1 or PowerShell 7+
    - Local administrator privileges
    - Internet access to https://packages.microtunnel.app/

.LINK
https://packages.microtunnel.app/
#>

if ($env:SyncroModule) {
    Import-Module $env:SyncroModule
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
            $script:alertMessage += "Downloaded file is missing or empty: $($DestinationPath)`n"
            return $false
        }

        return $true
    }
    catch {
        Write-Host "Failed to download MicroTunnel installer: $($_.Exception.Message)" -ForegroundColor Red
        $script:alertMessage += "Failed to download MicroTunnel installer: $($_.Exception.Message)`n"
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

$alertMessage = $null

# Validate parameters.
if ([string]::IsNullOrWhiteSpace($orgId) -or [string]::IsNullOrWhiteSpace($installType)) {
    Write-Host "Required parameters are missing."
    if ($env:SyncroModule) { Log-Activity -Message "Could not install. Required parameters are missing." -EventName "MicroTunnel Deployment" }
    if ($env:SyncroModule) { Rmm-Alert -Category 'MicroTunnel Deployment' -Body "Required parameters are missing." }
    exit 1
}

# Run the installation process.
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
        try {
            # Launch the silent installer.
            Write-Host "Launching installer..."
            If ($installType -eq 'Workstation') {
                Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Start-Sleep -Seconds 1; & `'$installerPath`' -ws -orgId `'$orgId`'`"" -Wait
            }
            else {
                Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Start-Sleep -Seconds 1; & `'$installerPath`' -svr -orgId `'$orgId`'`"" -Wait
            }
        }
        catch {
            Write-Error "Failed to launch installer: $($_.Exception.Message)"
            $alertMessage += "Failed to launch installer: $($_.Exception.Message)`n"
            if ($env:SyncroModule) { Log-Activity -Message "Failed to launch installer: $($_.Exception.Message)" -EventName "MicroTunnel Deployment" }
            exit 2
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    if ($env:SyncroModule) { Log-Activity -Message "Unknown error downloading installer." -EventName "MicroTunnel Deployment" }
    $alertMessage += "Unknown error downloading installer.`n"
    exit 1
}
finally {
    if ($installerPath -and (Test-Path -LiteralPath $installerPath)) {
        Write-Host "Cleaning up temporary files..."
        Start-Sleep -Seconds 1
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        Write-Host "Microtunnel Workstation installed to organization $($orgId)." -ForegroundColor Red
        if ($env:SyncroModule) { Log-Activity -Message "Microtunnel Workstation installed to organization $($orgId)." -EventName "MicroTunnel Deployment" }
    }
    if ($null -ne $alertMessage) {
        if ($env:SyncroModule) { Rmm-Alert -Category 'MicroTunnel Deployment' -Body $alertMessage }
    }
}
