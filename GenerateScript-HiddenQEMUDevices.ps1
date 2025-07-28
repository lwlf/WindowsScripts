# 定义枚举
enum DeviceType {
    PCI
    SCSI
}

$lang_resources = @{
    "en-US" = @{
        is_not_admin = "Not currently running with admin privileges! Please run as an administrator."
        is_admin = "√ Granted admin privileges."
        press_enter_exit = "Press Enter to exit..."
        create_hidden_folder = "Create a hidden folder: "
        create_script = "Create a script: "
        reboot = "Please reboot the system."
        }

    "zh-CN" = @{
        is_not_admin = "当前未以管理员权限运行！请以管理员身份运行。"
        is_admin = "√ 已获得管理员权限"
        press_enter_exit = "按 Enter 退出..."
        create_hidden_folder = "创建隐藏文件夹："
        create_script = "创建脚本："
        reboot = "请重启系统。"
        }
}

$messages = $lang_resources[$PSUICulture]

if (-not $messages) {
    $messages = $lang_resources["en-US"]
}

# 管理员权限检测函数
function Test-AdminPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 主逻辑
if (-not (Test-AdminPrivilege)) {
    # 非管理员权限时显示警告
    Write-Warning $messages.is_not_admin
    
    Read-Host $messages.press_enter_exit
    exit 1
}

# 管理员权限下的操作
Write-Host $messages.is_admin -ForegroundColor Green

# 保存脚本信息
$bat_name = "HiddenQEMUDevices.bat"
$bat_path = "$env:USERPROFILE\Scripts"
$bat_full_name = Join-Path -Path $bat_path -ChildPath $bat_name

# PCI 及 SCSI 设备标记
$start_pci_content = ':: PCI Devices'
$end_pci_content = 'call :hiddenDevice "PCI"'

$start_scsi_content = ':: SCSI Devices'
$end_scsi_content = 'call :hiddenDevice "SCSI"'

# 定义一个函数，使用枚举作为参数
function Get-DeviceInfo {
    param (
        [DeviceType]$type
    )

    $device_root_path = "HKLM:\SYSTEM\CurrentControlSet\Enum"
    $device_type = "PCI"
    $device_display_value = 6

    # 使用 switch 语句，并显式指定枚举类型
    switch ($type) {
        { $_ -eq [DeviceType]::SCSI } {
            $device_type = "SCSI"
            $device_display_value = 102
        }
    }

    $device_path = Join-Path -Path $device_root_path -ChildPath $device_type

    # 获取目标路径下的所有子项
    $device_items = Get-ChildItem -Path $device_path -Recurse -ErrorAction SilentlyContinue
    $devices = New-Object System.Collections.ArrayList

    # 遍历子项，查找 Capabilities 对应值的项
    foreach ($item in $device_items) {
        $device_capabilities = Get-ItemProperty -Path $item.PSPath -Name "Capabilities" -ErrorAction SilentlyContinue

        if ($device_capabilities -and $device_capabilities.Capabilities -eq $device_display_value) {
            $device_device_desc = Get-ItemProperty -Path $item.PSPath -Name "DeviceDesc" -ErrorAction SilentlyContinue
            $device_friendly_name = Get-ItemProperty -Path $item.PSPath -Name "FriendlyName" -ErrorAction SilentlyContinue
            
            $device_hash = New-Object System.Collections.Hashtable
            
            $device_hash["Capabilities"] = $device_capabilities.Capabilities
            $device_hash["HiddenCapabilities"] = $device_display_value - 6
            $device_hash["Path"] = $($item.PSPath -replace "Microsoft\.PowerShell\.Core\\Registry::", "").Trim()
    
            if ($device_device_desc) {
                $device_hash["DeviceDesc"] = $($device_device_desc.DeviceDesc.Split(';')[-1].Trim())
            }
    
            if ($device_friendly_name) {
                $device_hash["FriendlyName"] = $($device_friendly_name.FriendlyName.Split(';')[-1].Trim())
            }
    
            $devices.Add($device_hash) | Out-Null
        }
    }

    return $devices
}

# 设备去重
function Get-UniqueDevices {
    param (
        [array]$DeviceList
    )

    if (-not $DeviceList) {
        return $DeviceList
    }

    $content = $DeviceList

    # 处理去重
    $unique_content = @{}
    $output_lines = [System.Collections.ArrayList]::new()
    $lines = $content -split "`n"

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $current_line = $lines[$i].Trim()
        $nextLine = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { $null }

        # 当检测到设备注释行且下一行是调用行时
        if ($current_line.StartsWith(':: Device:') -and 
            $nextLine -match '^call :addToDevices "(.*)"') {
        
            $path = $matches[1]
            if (-not $unique_content.ContainsKey($path)) {
                $output_lines.Add($current_line) | Out-Null
                $output_lines.Add($nextLine) | Out-Null
                $unique_content[$path] = $true
            }
            $i++  # 额外跳过下一行（已处理）
        }
        else {
            $output_lines.Add($current_line) | Out-Null # 非设备组或未重复的行直接添加
        }
    }

    return $output_lines -join "`n"
}

# 获取 PCI 设备信息
$pci_devices = $(Get-DeviceInfo -type ([DeviceType]::PCI))
# 获取 SCSI 设备信息
$scsi_devices = $(Get-DeviceInfo -type ([DeviceType]::SCSI))

$pci_devices_string = New-Object System.Collections.ArrayList
$scsi_devices_string = New-Object System.Collections.ArrayList

# 添加搜索开始标识符
$pci_devices_string.Add("$start_pci_content") | Out-Null
$scsi_devices_string.Add("$start_scsi_content") | Out-Null

if (Test-Path -Path "$bat_full_name" -PathType Leaf) {
    # 获取旧 PCI 及 SCSI 设备清单
    $pci_list_line_start = (Select-String -Path "$bat_full_name" -Pattern $start_pci_content)
    $pci_list_line_end = (Select-String -Path "$bat_full_name" -Pattern $end_pci_content)

    if ($pci_list_line_start -and $pci_list_line_end) {
        $pci_list_line_start_num = $pci_list_line_start.LineNumber
        $pci_list_line_end_num = $pci_list_line_end.LineNumber

        $pci_list_line = (Get-Content -Path "$bat_full_name" -TotalCount ($pci_list_line_end_num - 1) | Select-Object -Last ($pci_list_line_end_num - $pci_list_line_start_num - 1))
        $pci_list_line | ForEach-Object {
            $pci_devices_string.Add("$_") | Out-Null }
    }


    $scsi_list_line_start = (Select-String -Path "$bat_full_name" -Pattern $start_scsi_content)
    $scsi_list_line_end = (Select-String -Path "$bat_full_name" -Pattern $end_scsi_content)

    if ($scsi_list_line_start -and $scsi_list_line_end) {
        $scsi_list_line_start_num = $scsi_list_line_start.LineNumber
        $scsi_list_line_end_num = $scsi_list_line_end.LineNumber

        $scsi_list_line = (Get-Content -Path "$bat_full_name" -TotalCount ($scsi_list_line_end_num - 1) | Select-Object -Last ($scsi_list_line_end_num - $scsi_list_line_start_num - 1))
        $scsi_list_line | ForEach-Object {
            $scsi_devices_string.Add($_) | Out-Null }
    }
        
    else {
        Remove-Item -Path "$bat_full_name" -Force
    }
}


# 处理 PCI 设备信息
foreach ($device in $pci_devices) {
    $name = "$($device.DeviceDesc)"
    if (-not [string]::IsNullOrEmpty($device.FriendlyName)) {
        $name += " (" + $device.FriendlyName + ")"
    }

    $pci_devices_string.Add(":: Device: $name") | Out-Null
    $pci_devices_string.Add("call :addToDevices `"$($device.Path)`"") | Out-Null
}

# 处理 SCSI 设备信息
foreach ($device in $scsi_devices) {
    $name = "$($device.DeviceDesc)"
    if (-not [string]::IsNullOrEmpty($device.FriendlyName)) {
        $name += " (" + $device.FriendlyName + ")"
    }

    $scsi_devices_string.Add(":: Device: $name") | Out-Null
    $scsi_devices_string.Add("call :addToDevices `"$($device.Path)`"") | Out-Null
}

# 设备清单去重
$pci_devices_string = Get-UniqueDevices($pci_devices_string)
$scsi_devices_string = Get-UniqueDevices($scsi_devices_string)

# 脚本内容
$bat_content = @"
@echo off
setlocal enabledelayedexpansion

$pci_devices_string
call :hiddenDevice "PCI"
call :resetCount

$scsi_devices_string
call :hiddenDevice "SCSI"
call :resetCount

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


if (-not (Test-Path -Path $bat_path)) {
    # 创建脚本隐藏工作路径：%USERPROFILE%\Scripts
    New-Item -ItemType Directory -Attributes Hidden -Path $bat_path | Out-Null
    Write-Output "$($messages.create_hidden_folder)$bat_path"
}
elseif (-not ((Get-Item -Path $bat_path -Force).Attributes -match "Hidden")) {
    # 存在工作路径且非隐藏，则隐藏工作路径
    Set-ItemProperty -Path $bat_path -Name Attributes -Value ([System.IO.FileAttributes]::Hidden)
}

Write-Output "$($messages.create_script)$bat_full_name"
Set-Content -Path "$bat_full_name" -Value $bat_content -Encoding UTF8 -Force

# 定义任务名称和路径
$task_name = "Remove From Safely Remove Hardware List by Scripts"
$task_path = $bat_full_name

# 创建计划任务
schtasks /create /tn "$task_name" /sc ONSTART /ru SYSTEM /rl HIGHEST /tr "$task_path" /F

Write-Output $messages.reboot
