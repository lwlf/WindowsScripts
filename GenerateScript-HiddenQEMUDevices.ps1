# 定义枚举
enum DeviceType {
    PCI
    SCSI
}

# 定义一个函数，使用枚举作为参数
function Get-DeviceInfo {
    param (
        [DeviceType]$type
    )

    $deviceRootPath = "HKLM:\SYSTEM\CurrentControlSet\Enum"
    $deviceType = "PCI"
    $deviceDisplayValue = 6

    # 使用 switch 语句，并显式指定枚举类型
    switch ($type) {
        { $_ -eq [DeviceType]::SCSI } {
            $deviceType = "SCSI"
            $deviceDisplayValue = 102
        }
    }

    $devicePath = Join-Path -Path $deviceRootPath -ChildPath $deviceType

    # 获取目标路径下的所有子项
    $deviceItems = Get-ChildItem -Path $devicePath -Recurse -ErrorAction SilentlyContinue
    $devices = New-Object System.Collections.ArrayList

    # 遍历子项，查找 Capabilities 对应值的项
    foreach ($item in $deviceItems) {
        $deviceCapabilities = Get-ItemProperty -Path $item.PSPath -Name "Capabilities" -ErrorAction SilentlyContinue

        # Write-Output $deviceCapabilities.Capabilities
        if ($deviceCapabilities -and $deviceCapabilities.Capabilities -eq $deviceDisplayValue) {
            $deviceDeviceDesc = Get-ItemProperty -Path $item.PSPath -Name "DeviceDesc" -ErrorAction SilentlyContinue
            $deviceFriendlyName = Get-ItemProperty -Path $item.PSPath -Name "FriendlyName" -ErrorAction SilentlyContinue
            
            $deviceHash = New-Object System.Collections.Hashtable
            
            $deviceHash["Capabilities"] = $deviceCapabilities.Capabilities
            $deviceHash["HiddenCapabilities"] = $deviceDisplayValue - 6
            $deviceHash["Path"] = $($item.PSPath -replace "Microsoft\.PowerShell\.Core\\Registry::", "").Trim()
    
            if ($deviceDeviceDesc) {
                $deviceHash["DeviceDesc"] = $($deviceDeviceDesc.DeviceDesc.Split(';')[-1].Trim())
            }
    
            if ($deviceFriendlyName) {
                $deviceHash["FriendlyName"] = $($deviceFriendlyName.FriendlyName.Split(';')[-1].Trim())
            }
    
            $devices.Add($deviceHash) | Out-Null
        }
    }

    return $devices
}

# 获取 PCI 设备信息
$pciDeivces = $(Get-DeviceInfo -type ([DeviceType]::PCI))
# 获取 SCSI 设备信息
$scsiDevices = $(Get-DeviceInfo -type ([DeviceType]::SCSI))

$pciDeivcesString = New-Object System.Collections.ArrayList
$scsiDeivcesString = New-Object System.Collections.ArrayList

$pciDeivcesString.Add(":: PCI Devices") | Out-Null
$scsiDeivcesString.Add(":: SCSI Devices") | Out-Null

# 处理 PCI 设备信息
foreach ($device in $pciDeivces) {
    $name = "$($device.DeviceDesc)"
    if (-not [string]::IsNullOrEmpty($device.FriendlyName)) {
        $name += " (" + $device.FriendlyName + ")"
    }

    $pciDeivcesString.Add(@"

:: Device: $name
call :addToDevices "$($device.Path)"
"@) | Out-Null
}

$pciDeivcesString.Add(@"

call :hiddenDevice "PCI"
call :resetCount
"@) | Out-Null

# 处理 SCSI 设备信息
foreach ($device in $scsiDevices) {
    $name = "$($device.DeviceDesc)"
    if (-not [string]::IsNullOrEmpty($device.FriendlyName)) {
        $name += " (" + $device.FriendlyName + ")"
    }

    $scsiDeivcesString.Add(@"

:: Device: $name
call :addToDevices "$($device.Path)"
"@) | Out-Null
}

$scsiDeivcesString.Add(@"

call :hiddenDevice "SCSI"
call :resetCount
"@) | Out-Null

$batContent = @"
@echo off
setlocal enabledelayedexpansion

$pciDeivcesString

$scsiDeivcesString

goto :eof
:hiddenDevice
if "%~1" equ "PCI" (
    set "HiddenValue=0"
) else if "%~1" equ "SCSI" (
    set "HiddenValue=96"
) else (
    set "HiddenValue=0"
)

for /l %%i in (1,1,!DevicesCount!) do (
    reg add "!Devices%%i!" /v Capabilities /t reg_dword /d !HiddenValue! /f
)
goto :eof

goto :eof
:resetCount
set "DevicesCount=0"
goto :eof

call :resetCount

goto :eof
:addToDevices
set /a DevicesCount+=1
set "Devices!DevicesCount!=%~1"
goto :eof
"@

# 保存脚本信息
$batName = "HiddenQEMUDevices.bat"
$batPath = "$env:USERPROFILE\Scripts"
$batFullName = Join-Path -Path $batPath -ChildPath $batName

Set-Content -Path $batFullName -Value $batContent -Encoding UTF8

# 定义任务名称和路径
$taskName = "Remove From Safely Remove Hardware List by Scripts"
$taskPath = $batFullName

# 创建计划任务
schtasks /create /tn "$taskName" /sc ONSTART /ru SYSTEM /rl HIGHEST /tr "$taskPath"