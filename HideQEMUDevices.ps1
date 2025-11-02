$TaskName = 'Remove From Safely Remove Hardware List (Split List) by Scripts'

# 创建开机任务
$TaskAction_1 = New-ScheduledTaskAction -Execute 'C:\Windows\Setup\Scripts\HideQEMUDevices\HideQEMUDevices.bat'
$TaskAction_2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '"C:\Windows\Setup\Scripts\HideQEMUDevices\UpdateHideQEMUDevices.ps1"'
$TaskTrigger  = New-ScheduledTaskTrigger -AtStartup
$TaskSet  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "$TaskName" -Action $TaskAction_1,$TaskAction_2 -Trigger $TaskTrigger -Settings $TaskSet -User 'SYSTEM' -RunLevel Highest -Force

$BatFile = "C:\Windows\Setup\Scripts\HideQEMUDevices\HideQEMUDevices.bat"
$PSFile = "C:\Windows\Setup\Scripts\HideQEMUDevices\UpdateHideQEMUDevices.ps1"

New-Item -Path 'C:\Windows\Setup\Scripts\HideQEMUDevices' -ItemType Directory -Force | Out-Null

$BatFile_Content = @'
@echo off
@REM version: 0.0.1

set "FilePath=C:\Windows\Setup\Scripts\HideQEMUDevices\HideQEMUDevices.csv"

for /f "usebackq skip=1 tokens=1-5 delims=," %%A in ("%FilePath%") do (
    @REM Name, Cap, HideCap, Path
    @REM A, B, C, D
    echo Hiding device: %%A ...
    reg add "%%D" /v Capabilities /t reg_dword /d %%C /f && (echo Hiding completed.) || (echo Hiding failed.)
)
'@

$PSFile_Content = @'
$HideQEMUDevices_Foler = "C:\Windows\Setup\Scripts\HideQEMUDevices";
$HideQEMUDevices_CSV = Join-Path -Path "$HideQEMUDevices_Foler" -ChildPath "HideQEMUDevices.csv";

function Get-Devices {
    param (
        [string]$Path
    )
    $RegRootPathPrefix = "Registry::"
    $RegRootPath = "HKLM\SYSTEM\CurrentControlSet\Enum"

    $Devices = New-Object System.Collections.ArrayList;

    if (Test-Path -Path "$Path") {
        $Old_Devices = Import-Csv -Path "$Path";

        if ($Old_Devices) {
            $Devices.AddRange($Old_Devices)
        }
    }

    $Device_List = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.DeviceID -like "PCI\*" -or $_.DeviceID -like "SCSI\*" };

    foreach ($Device in $Device_List) {
        $Device_Path = "${RegRootPathPrefix}${RegRootPath}\$($Device.DeviceID)";
        $Device_Capabilities = (Get-ItemProperty -Path $Device_Path -Name Capabilities).Capabilities;
        if ( $Device_Capabilities -eq 102 -or $Device_Capabilities -eq 6 ) {
            [void]$Devices.Add([PSCustomObject]@{
                    Name             = $Device.name
                    Capabilities     = $Device_Capabilities
                    HideCapabilities = $($Device_Capabilities - 6)
                    Path             = "$RegRootPath\$($Device.DeviceID)"
                })
        }
    }

    $Devices = $($Devices | Sort-Object -Property Path -Unique);

    return $Devices
}

function Export-Devices {
    param (
        [string]$Path,
        [System.Collections.ArrayList]$Devices
    )
    
    if ($Devices) {
        $Devices | Export-Csv -Path "$Path" -NoTypeInformation
    }
}

Export-Devices -Path "$HideQEMUDevices_CSV" -Devices (Get-Devices -Path "$HideQEMUDevices_CSV")
'@

if ($PSVersionTable.PSVersion -ge '6.0') {
    $BatFile_Content | Out-File -LiteralPath "$BatFile" -Encoding utf8NoBom
    $PSFile_Content | Out-File -LiteralPath "$PSFile" -Encoding utf8NoBom
} else {
    [System.IO.File]::WriteAllText("$BatFile", $BatFile_Content, [System.Text.Encoding]::default)
    [System.IO.File]::WriteAllText("$PSFile", $PSFile_Content, [System.Text.Encoding]::default)
}

powershell.exe "$PSFile"