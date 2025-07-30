# WindowsScripts

## 移除预装 APP

以管理员权限运行 PowerShell，执行以下命令

```powershell
irm https://raw.githubusercontent.com/lwlf/WindowsScripts/main/RemoveWindowsProvisionedApps.ps1 | iex
```

或

```powershell
irm https://ghfast.top/https://raw.githubusercontent.com/lwlf/WindowsScripts/main/RemoveWindowsProvisionedApps.ps1 | iex
```

## 生成 隐藏QEMU设备 脚本

> ~~新增设备需要将 “Remove From Safely Remove Hardware List by Scripts” 计划禁用，重启电脑后执行，不然会找不到设备进行处理~~
> 新增设备直接执行，脚本会读取旧设备，重启电脑后执行

```powershell
irm https://gh-proxy.com/lwlf/WindowsScripts/raw/refs/heads/main/GenScript-HiddenQEMUDevices.ps1 | iex
```

或

```powershell
irm https://gh-proxy.com/https://github.com/lwlf/WindowsScripts/raw/refs/heads/main/GenScript-HiddenQEMUDevices.ps1 | iex
```
