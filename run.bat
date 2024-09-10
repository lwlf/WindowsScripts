@echo off

%1 mshta vbscript:CreateObject("Shell.Application").ShellExecute("cmd.exe","/c %~s0 ::","","runas",1)(window.close)&&exit

cd /d "%~dp0"

set pscmdline='powershell Get-ExecutionPolicy -Scope CurrentUser'
for /f %%a in (%pscmdline%) do (set execution_policy=%%a)
echo %execution_policy%

(powershell Set-ExecutionPolicy -Scope CurrentUser RemoteSigned)

(powershell %~dp0/RemoveWindowsProvisionedApps.ps1)

(powershell Set-ExecutionPolicy -Scope CurrentUser %execution_policy%)

pause