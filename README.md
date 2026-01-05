# SNVM - Simple Node Version Manager

## Description

SNVM is a powershell script tool to manage NodeJS versions on Windows Environments.

## Installation

To install snvm, perform the following steps:
1. Download the script and place it inside the Windows user's home folder. 
- Download snvm from <a target="_blank" href="https://github.com/lucianobritodev/snvm/releases">releases</a>. 
- Unzip the downloaded file and move the `snvm.ps1` script into the user folder in `C:\Users\$env:USERNAME\`.
2. Create a PowerShell profile file if you haven't already. 
- In `C:\Users\$env:USERNAME\Documents\WindowsPowerShell\` create the following file `Microsoft.PowerShell_profile.ps1`
3. Within the profile file, assign an alias to the script as follows:

```powershell
Set-Alias snvm "C:\Users\$env:USERNAME\snvm.ps1"
```

## Execution

```powershell
snvm list
```
