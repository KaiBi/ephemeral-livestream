@echo off
for %%X in (pwsh.exe) do (SET PWSHAVAILABLE=%%~$PATH:X)
if defined PWSHAVAILABLE (
    start pwsh.exe -c src/setup.ps1
) else (
    start powershell.exe -c src/setup.ps1
)