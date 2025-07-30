enum DeviceType {
    PCI
    SCSI
}

$is_admin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($is_admin) {
    Write-Host "Running as administrator." -ForegroundColor Green
}
else {
    Write-Host "Running as a standard user (non-admin). Please run as administrator." -ForegroundColor Red
}

function Get-Devices {
    param (
        [DeviceType]$type
    )
    
    $device_root_path = "HKLM:\SYSTEM\CurrentControlSet\Enum"
    $device_type = "PCI"
    $device_display_value = 6

    if ($type -eq [DeviceType]::SCSI) {
        $device_type = "SCSI"
        $device_display_value = 102
    }

    $device_path = Join-Path -Path $device_root_path -ChildPath $device_type
    
    $device_items = Get-ChildItem -Path $device_path -Recurse -ErrorAction SilentlyContinue
    $devices = New-Object System.Collections.ArrayList

    foreach ($device_item in $device_items) {
        $device_info = Get-ItemProperty -Path $device_item.PSPath -Name "Capabilities" -ErrorAction SilentlyContinue
        
        if ($device_info -and $device_info.Capabilities -eq $device_display_value) {
            $device_hash = New-Object System.Collections.Hashtable

            $device_hash["Capabilities"] = $device_info.Capabilities
            $device_hash["HiddenCapabilities"] = $device_display_value - 6
            $device_hash["Path"] = $($device_item.PSPath -replace "Microsoft\.PowerShell\.Core\\Registry::", "").Trim()

            $devices.Add($device_hash) | Out-Null
        }
    }

    return $devices
}

function Get-OldDevices {
    param (
        [DeviceType]$Type,
        [string]$FilePath,
        [string]$SearchContentStart,
        [string]$SearchContentEnd
    )
    if (-not $FilePath) {   
        $FilePath = "$env:USERPROFILE\Scripts\HiddenQEMUDevices.bat"
    }
    
    if (-not $SearchContentStart) {
        $SearchContentStart = ($Type -eq [DeviceType]::PCI) ? ':: PCI Devices' : ':: SCSI Devices'
    }

    if (-not $SearchContentEnd) {
        $SearchContentEnd = ($Type -eq [DeviceType]::PCI) ? 'call :hiddenDevice "PCI"' : 'call :hiddenDevice "SCSI"'
    }

    $devices = [System.Collections.ArrayList]::new()

    if (-not (Test-Path -LiteralPath $FilePath)) { return , $devices }

    $start_line_num = (Select-String -LiteralPath $FilePath -Pattern "$SearchContentStart").LineNumber
    $end_line_num = (Select-String -LiteralPath $FilePath -Pattern "$SearchContentEnd").LineNumber

    if (-not $start_line_num -or -not $end_line_num -or $start_line_num -ge $end_line_num) { return , $devices }

    $raw = Get-Content -LiteralPath $FilePath | Select-Object -Skip $start_line_num -First ($end_line_num - $start_line_num - 1)

    foreach ($line in $raw) {
        [void]$devices.Add($line)
    }

    return , $devices
}

function Get-UniqueDevices {
    param (
        [System.Collections.ArrayList]$Devices
    )

    if (-not $Devices) {
        return , [System.Collections.ArrayList]::new()
    }

    if ($Devices.Count -eq 0) {
        return , $Devices
    }
    
    $unique = $Devices | Sort-Object -Unique

    return $unique -join "`n"
}

# Get PCI devices.
$pci_devices = Get-Devices -type ([DeviceType]::PCI)
# Get SCSI devices.
$scsi_devices = Get-Devices -type ([DeviceType]::SCSI)

# Script info.
$bat_name = "HiddenQEMUDevices.bat"
$bat_path = "$env:USERPROFILE\Scripts"
$bat_full_name = Join-Path -Path $bat_path -ChildPath $bat_name

# Get PCI old devices.
$pci_devices_string = Get-OldDevices -type ([DeviceType]::PCI)

# Get SCSI old devices.
$scsi_devices_string = Get-OldDevices -type ([DeviceType]::SCSI)

if (-not $pci_devices_string.Count -eq 0 -or -not $scsi_devices_string.Count -eq 0 ) {
    Remove-Item -Path "$bat_full_name" -Force
}

# Parse PCI devices.
foreach ($device in $pci_devices) {
    # $pci_devices_string.GetType()
    $pci_devices_string.Add("call ::addToDevices `"$($device.Path)`"") | Out-Null
}

# Parse SCSI devices.
foreach ($device in $scsi_devices) {
    $scsi_devices_string.Add("call ::addToDevices `"$($device.Path)`"") | Out-Null
}

# Unique devices.
$pci_devices_string = Get-UniqueDevices -Devices $pci_devices_string
$scsi_devices_string = Get-UniqueDevices -Devices $scsi_devices_string

# Bat content.
$bat_content = @"
@echo off
setlocal enabledelayedexpansion

call :resetCount

:: PCI Devices
$pci_devices_string
call :hiddenDevice "PCI"
call :resetCount

:: SCSI Devices
$scsi_devices_string
call :hiddenDevice "SCSI"
call :resetCount

goto :eof

:addToDevices
set /a DevicesCount+=1
set "Devices!DevicesCount!=%~1"
goto :eof

:hiddenDevice
if "%~1"=="PCI"  (set "HiddenValue=0")  else (set "HiddenValue=96")
for /l %%i in (1,1,!DevicesCount!) do (
    reg add "!Devices%%i!" /v Capabilities /t reg_dword /d !HiddenValue! /f
)
goto :eof

:resetCount
set "DevicesCount=0"
goto :eof
"@

if (-not (Test-Path -Path $bat_path)) {
    New-Item -ItemType Directory -Path $bat_path -Force | Out-Null
    Write-Host "Create a folder: `"$bat_path`"" -ForegroundColor Green
}

Set-ItemProperty -Path $bat_path -Name Attributes -Value ([System.IO.FileAttributes]::Hidden)

Write-Host "Create a script: `"$bat_full_name`"" -ForegroundColor Green
"$bat_content" | Out-File -FilePath "$bat_full_name" -Encoding Default

if ($is_admin) {
    $task_name = "Remove From Safely Remove Hardware List by Scripts"
    $task_path = $bat_full_name

    # Create task.
    schtasks /create /tn "$task_name" /sc ONSTART /ru SYSTEM /rl HIGHEST /tr "$task_path" /F
    
    Write-Host "Scheduled task created successfully." -ForegroundColor Green
    Write-Host "Please reboot the system." -ForegroundColor Red
}
else {
    Write-Host "Failed to create the scheduled task. `nRunning as a standard user (non-admin)." -ForegroundColor Red
}
