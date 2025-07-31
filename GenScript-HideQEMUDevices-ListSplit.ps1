function Get-Devices {
    param (
        [string]$Type
    )
    
    $Type = if ($Type.Trim() -eq "PCI") { "PCI" } else { "SCSI" }
    $deviceCapValue = if ($Type.Trim() -eq "PCI") { 6 } else { 102 }

    $devices = New-Object System.Collections.ArrayList

    $devicesInstance = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.PNPDeviceID -like "$Type\*" }
    $devicesInstance | ForEach-Object {
        $deviceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($_.PNPDeviceID)"
        $deviceInfo = Get-ItemProperty -LiteralPath $deviceRegPath -Name Capabilities -ErrorAction SilentlyContinue
        if ($deviceInfo.Capabilities -eq $deviceCapValue) {
            $devices.Add([PSCustomObject]@{
                    Name             = $_.Name
                    Type             = $Type
                    Capabilities     = $deviceInfo.Capabilities
                    HideCapabilities = ($deviceCapValue - 6)
                    Path             = ($deviceInfo.PSPath -replace "^Microsoft\.PowerShell\.Core\\Registry::", "")
                }) | Out-Null
        }
    }

    return , $devices
}

function Get-OldDevices {
    param (
        [string]$Type,
        [string]$FilePath
    )
    
    $Type = if ($Type.Trim() -eq "PCI") { "PCI" } else { "SCSI" }
    $FilePath = if (-not $FilePath.Trim()) { "$env:USERPROFILE\Scripts\HideDevices.csv" }

    $devices = [System.Collections.ArrayList]::new()

    if (-not (Test-Path -LiteralPath "$FilePath")) {
        return , $devices
    }

    Import-Csv -Path "$FilePath" -Encoding (Get-Encoding) | ForEach-Object {
        if ($_.Type -eq $Type) {
            $devices.Add($_) | Out-Null
        }
    }

    return , $devices
}

function Get-Encoding {
    $version = $PSVersionTable.PSVersion

    if ($version.Major -ge 7 -and $version.Minor -ge 4) {
        return [System.Text.Encoding]::GetEncoding("gb2312")
    }
    else {
        return "Default"
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "Running as administrator." -ForegroundColor Green
}
else {
    Write-Host "Running as a standard user (non-admin). Please run as administrator." -ForegroundColor Red
}

$batName = "HideQEMUDevices.bat"
$csvName = "HideQEMUDevices.csv"
$workPath = "$env:USERPROFILE\Scripts"

$batPath = Join-Path -Path "$workPath" -ChildPath "$batName"
$csvPath = Join-Path -Path "$workPath" -ChildPath "$csvName"

$PCIDevices = Get-OldDevices -Type "PCI" -FilePath "$csvPath"
$SCSIDevices = Get-OldDevices -Type "SCSI" -FilePath "$csvPath"

# Get devices.
$PCINewDevices = Get-Devices -Type "PCI"
$SCSINewDevices = Get-Devices -Type "SCSI"

$PCIDevices.AddRange($PCINewDevices) | Out-Null
$SCSIDevices.AddRange($SCSINewDevices) | Out-Null

# Export CSV.
$PCIDevices  | Sort-Object Name, Type, Path -Unique | Export-Csv -Path "$csvPath" -NoTypeInformation -Encoding (Get-Encoding) -Force
$SCSIDevices | Sort-Object Name, Type, Path -Unique | Export-Csv -Path "$csvPath" -NoTypeInformation -Encoding (Get-Encoding) -Append
Write-Host "Create a csv file: `"$csvPath`"" -ForegroundColor Green

# Export Script.
$batContent = @"
@echo off
@REM version: 0.0.1

set "FilePath=$csvPath"

for /f "usebackq skip=1 tokens=1-5 delims=," %%A in ("%FilePath%") do (
    @REM Name, Type, Cap, HideCap, Path
    @REM A, B, C, D, E
    echo Hiding device: %%A ...
    reg add "%%E" /v Capabilities /t reg_dword /d %%D /f && (echo Hiding completed.) || (echo Hiding failed.)
)
"@

if (-not (Test-Path -Path $workPath)) {
    New-Item -ItemType Directory -Path $workPath -Force | Out-Null
    Write-Host "Create a folder: `"$workPath`"" -ForegroundColor Green
}

Set-ItemProperty -Path "$workPath" -Name Attributes -Value ([System.IO.FileAttributes]::Hidden)

$batContent | Out-File -FilePath "$batPath" -Encoding (Get-Encoding) -Force
Write-Host "Create a script: `"$batPath`"" -ForegroundColor Green

# Create task
if ($isAdmin) {
    $taskName = "Remove From Safely Remove Hardware List (Split List) by Scripts"
    $taskPath = $batPath

    # Create task.
    schtasks /create /tn "$taskName" /sc ONSTART /ru SYSTEM /rl HIGHEST /tr "$taskPath" /F
    
    Write-Host "Scheduled task created successfully." -ForegroundColor Green
    Write-Host "Please reboot the system." -ForegroundColor Red
}
else {
    Write-Host "Failed to create the scheduled task. `nRunning as a standard user (non-admin)." -ForegroundColor Red
}