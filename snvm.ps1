
<#
#-----------------------------------------------------------------------------------------------------------------#
#
# .NAME
#  SNVM - Simple Node Version Manager
#
#-----------------------------------------------------------------------------------------------------------------#
#
# .AUTHOR
#  name: Luciano Brito
#  link: github.com/lucianobritodev
#
#-----------------------------------------------------------------------------------------------------------------#
#
# .DESCRIPTION
#  Gerencia versoes do Node.js usando o JSON oficial de releases
#  e binarios .zip do site do Node. Repositorio local: $HOME\.snvm
#
#
#-----------------------------------------------------------------------------------------------------------------#
#
# .NOTES
#  - Baixa somente .zip
#  - Usa junction (link de diretorio) em $HOME\.snvm\current
#  - PATH: adiciona $HOME\.snvm\current quando define 'default'
#
#-----------------------------------------------------------------------------------------------------------------#
#
# .USE
# 
# - Para listar as versoes disponiveis, por exemplo:
# .\snvm.ps1 list
#
# - Para instalar a versao 12 do NodeJS, por exemplo:
# .\snvm.ps1 install <v12|12|12.22.1>
#
# - Para obter informacoes de uso, por exemplo:
# .\snvm.ps1 help
#
# - Para obter a versao do script, por exemplo:
# .\snvm.ps1 version
#
#-----------------------------------------------------------------------------------------------------------------#
#
# .VERSIONS
#
#  - v1.0.0 : Criacao do script com funcionalidades principais 'install', 'use', 'default', 'remove', 'list', 'current', 'help', 'version'.
#
#
#
#
#
#-----------------------------------------------------------------------------------------------------------------#
#>


param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('install', 'use', 'default', 'remove', 'list', 'current', 'help', 'version')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$VersionTag # 'v12' | 'v12.22.12' | '12' (aceito)
)

#region Variaveis Locais
$VERSION = "1.0.0"                                              # versao deste script
$RepoRoot = Join-Path $HOME ".snvm"
$VersionsDir = Join-Path $RepoRoot "versions"
$CurrentLink = Join-Path $RepoRoot "current"
$IndexCache = Join-Path $RepoRoot "index.json"
$IndexUrl = "https://nodejs.org/download/release/index.json"    # fonte oficial
$CurlExe = "curl.exe"
#endregion


#region Utilitarios
function Ensure-Curl() {
    if (-not (Get-Command $CurlExe -ErrorAction SilentlyContinue)) {
        throw "Dependencia ausente: 'curl.exe' nao encontrado no PATH. Instale o cURL ou ajuste o PATH."
    }
}


function Ensure-Repo() {
    foreach ($p in @($RepoRoot, $VersionsDir)) {
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
    }
}


# Retorna win-x64 | win-x86 | win-arm64
function Get-PlatformTag() {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') { return 'win-arm64' }
    elseif ([Environment]::Is64BitOperatingSystem -and $arch -eq 'AMD64') { return 'win-x64' }
    else { return 'win-x86' }
}


function Update-IndexJson() {
    Ensure-Curl
    Ensure-Repo
    # Forcar atualizacao sempre que chamado
    & $CurlExe -sSL $IndexUrl -o $IndexCache
    if (-not (Test-Path $IndexCache)) {
        throw "Falha ao baixar indice de versoes do Node."
    }
}


function Test-ZipExists([string]$fullVersion, [string]$platformTag) {
    # Verifica existencia do ZIP sem baixar
    $url = Get-ZipUrl -fullVersion $fullVersion -platformTag $platformTag
    $result = & $CurlExe -sSIL $url 2>$null
    # curl -I retorna cabecalhos; se status 200, $LASTEXITCODE tende a 0
    return ($LASTEXITCODE -eq 0)
}


function Load-Index() {
    if (-not (Test-Path $IndexCache)) { Update-IndexJson }
    $raw = Get-Content -Path $IndexCache -Raw
    return ($raw | ConvertFrom-Json)
}


function Normalize-Tag([string]$tag) {
    if (-not $tag) { return $null }
    $t = $tag.Trim()
    if ($t -match '^[vV]\d+$') { return ('v' + ($t -replace '^[vV]')) }
    elseif ($t -match '^\d+$') { return 'v' + $t }
    elseif ($t -match '^v\d+\.\d+\.\d+$') { return $t.ToLower() }
    elseif ($t -match '^[vV]\d+\.\d+$') { return ('v' + ($t -replace '^[vV]')) }
    else { return $t.ToLower() }
}


function Parse-VersionParts([string]$v) {
    $clean = ($v -replace '^v', '')
    $parts = $clean.Split('.')
    $maj = [int]$parts[0]
    $min = if ($parts.Count -ge 2) { [int]$parts[1] } else { 0 }
    $pat = if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 }
    return @{ Major = $maj; Minor = $min; Patch = $pat }
}


function Sort-ByVersionDesc($items) {
    return $items | Sort-Object @{Expression = {
            $p = Parse-VersionParts $_.version
            ($p.Major * 1000000) + ($p.Minor * 1000) + $p.Patch
        }; Descending                        = $true
    }
}


function Supports-Platform($release, [string]$platformTag) {
    if (-not $release -or -not $release.files) { return $false }
    $patterns = @(
        $platformTag,
        "$platformTag-zip",
        "$platformTag-msi",
        "$platformTag-exe",
        "$platformTag-7z"
    )
    foreach ($p in $patterns) {
        if ($release.files -contains $p) { return $true }
    }
    return $false
}


# Converte "v24.12.0" -> @{ Major=24; Minor=12; Patch=0 }
function Parse-VersionParts([string]$v) {

    $clean = ($v -replace '^v', '')
    $parts = $clean.Split('.')
    $maj = [int]$parts[0]
    $min = if ($parts.Count -ge 2) { [int]$parts[1] } else { 0 }
    $pat = if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 }
    return @{ Major = $maj; Minor = $min; Patch = $pat }
}


function Compare-VersionDesc($a, $b) {
    $pa = Parse-VersionParts $a
    $pb = Parse-VersionParts $b
    if ($pa.Major -ne $pb.Major) { return ($pb.Major - $pa.Major) }
    elseif ($pa.Minor -ne $pb.Minor) { return ($pb.Minor - $pa.Minor) }
    else { return ($pb.Patch - $pa.Patch) }
}


# Permite a tag completa ou parcial
function Resolve-FullVersion([string]$majorOrFull, [string]$platformTag) {
    Update-IndexJson
    $idx = Load-Index

    $wanted = Normalize-Tag $majorOrFull
    if (-not $wanted) { throw "Informe uma tag de versao: ex.: v12" }

    if ($wanted -match '^v\d+$') {
        $major = $wanted
        $match = $idx | Where-Object { $_.version -like "$major.*" } |
        Sort-Object { $_.version -replace '^v', '' } -Descending |
        Select-Object -First 1
        if (-not $match) { throw "Nenhuma versao encontrada para $major." }

        $full = $match.version

        if (Test-ZipExists -fullVersion $full -platformTag $platformTag) {
            return $full
        }
        else {
            $fallbackPlat = if ($platformTag -eq 'win-x64') { 'win-x86' } else { 'win-x64' }
            if (Test-ZipExists -fullVersion $full -platformTag $fallbackPlat) {
                throw "ZIP nao encontrado para $platformTag em $full. Tente com $fallbackPlat ou use 'snvm use v12' apos 'snvm install v12'."
            }
            else {
                throw "Nenhuma build ZIP encontrada para $full em $platformTag (nem em $fallbackPlat)."
            }
        }
    }
    else {
        # Tag completa ou parcial vX.Y(.Z)
        $full = $idx | Where-Object { $_.version -like "$wanted*" } |
        Sort-Object { $_.version -replace '^v', '' } -Descending |
        Select-Object -First 1
        if (-not $full) { throw "Versao '$wanted' nao encontrada." }

        $ver = $full.version
        if (Test-ZipExists -fullVersion $ver -platformTag $platformTag) {
            return $ver
        }
        else {
            $fallbackPlat = if ($platformTag -eq 'win-x64') { 'win-x86' } else { 'win-x64' }
            if (Test-ZipExists -fullVersion $ver -platformTag $fallbackPlat) {
                throw "ZIP nao encontrado para $platformTag em $ver. Tente com $fallbackPlat."
            }
            else {
                throw "Nenhuma build ZIP encontrada para $ver em $platformTag (nem em $fallbackPlat)."
            }
        }
    }
}


# Formato oficial: node-vX.Y.Z-win-<arch>.zip
function Get-ZipUrl([string]$fullVersion, [string]$platformTag) {
    return ("https://nodejs.org/download/release/{0}/node-{0}-{1}.zip" -f $fullVersion, $platformTag)
}


# Retorna a pasta de instalacao
function Get-InstallBase([string]$fullVersion, [string]$platformTag) {
    return (Join-Path (Join-Path $VersionsDir $fullVersion) $platformTag)
}


# Extrai o node dentro de C:\Users\<MATRICULA>\.snvm\versions
function Expand-Zip([string]$zipPath, [string]$destDir) {
    if (Test-Path $destDir) { Remove-Item -Recurse -Force $destDir }
    New-Item -ItemType Directory -Path $destDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
}


function Get-ExtractedFolder([string]$destDir, [string]$fullVersion, [string]$platformTag) {

    # Normalmente: node-vX.Y.Z-win-<arch>
    $expected = Join-Path $destDir ("node-{0}-{1}" -f $fullVersion, $platformTag)
    if (Test-Path $expected) { 
        return $expected 
    }

    # fallback: primeiro diretorio filho
    $child = Get-ChildItem -Path $destDir -Directory | Select-Object -First 1
    if ($child) { return $child.FullName }
    throw "Nao foi possivel localizar a pasta extraida do zip."
}


# Criacao de link simbolico (ou junction no Windows)
function Create-Junction([string]$target, [string]$junctionPath) {
    if (Test-Path $junctionPath) {
        Remove-Item -LiteralPath $junctionPath -Force -Recurse -Confirm:$false
    }
    New-Item -ItemType Junction -Path $junctionPath -Target $target | Out-Null
}


function Ensure-PathHasCurrent([switch]$Persist) {
    $currentDir = $CurrentLink
    # processo atual
    if (-not ($env:Path -split ';' | Where-Object { $_ -eq $currentDir })) {
        $env:Path = "$currentDir;$env:Path"
    }

    if ($Persist) {
        # Persistir no PATH do usuario (HKCU)
        $regPath = 'HKCU:\Environment'
        $userPath = (Get-ItemProperty -Path $regPath -Name Path -ErrorAction SilentlyContinue).Path
        if (-not $userPath) { $userPath = '' }
        $paths = $userPath -split ';'

        if (-not ($paths | Where-Object { $_ -eq $currentDir })) {
            $newPath = "$currentDir;" + $userPath
            Set-ItemProperty -Path $regPath -Name Path -Value $newPath

            # Broadcast da alteracao (WM_SETTINGCHANGE)
            $sig = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, int Msg, IntPtr wParam, string lParam, int fuFlags, int uTimeout, out IntPtr lpdwResult);
}
"@
            Add-Type $sig | Out-Null
            $result = [IntPtr]::Zero
            [void][Win32]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]0, "Environment", 0, 5000, [ref]$result)
        }
    }
}


function Read-Config() {
    $cfgPath = Join-Path $RepoRoot "config.json"
    if (Test-Path $cfgPath) {
        try { return (Get-Content -Path $cfgPath -Raw | ConvertFrom-Json) } catch { return @{} }
    }
    else { return @{} }
}


function Write-Config($obj) {
    $cfgPath = Join-Path $RepoRoot "config.json"
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -Path $cfgPath -Encoding UTF8
}
#endregion



#region Operacoes
function Install-Version([string]$tag) {
    Ensure-Repo; Ensure-Curl
    $plat = Get-PlatformTag
    $full = Resolve-FullVersion -majorOrFull $tag -platformTag $plat
    $zipUrl = Get-ZipUrl -fullVersion $full -platformTag $plat
    $destBase = Get-InstallBase -fullVersion $full -platformTag $plat
    $tmpZip = Join-Path $env:TEMP ("node-{0}-{1}.zip" -f $full, $plat)

    Write-Host "Baixando $zipUrl ..."
    & $CurlExe --progress-bar -fSL $zipUrl -o $tmpZip
    if (-not (Test-Path $tmpZip)) { throw "Falha no download do zip." }

    Write-Host "Extraindo para $destBase ..."
    Expand-Zip -zipPath $tmpZip -destDir $destBase
    Remove-Item $tmpZip -Force

    $extracted = Get-ExtractedFolder -destDir $destBase -fullVersion $full -platformTag $plat
    Write-Host "Instalacao concluida: $extracted"
}


function Use-Version([string]$tag, [switch]$PersistDefault = $false) {
    Ensure-Repo
    $plat = Get-PlatformTag
    $full = Resolve-FullVersion -majorOrFull $tag -platformTag $plat
    $destBase = Get-InstallBase -fullVersion $full -platformTag $plat
    $extracted = Get-ExtractedFolder -destDir $destBase -fullVersion $full -platformTag $plat

    Create-Junction -target $extracted -junctionPath $CurrentLink
    Ensure-PathHasCurrent -Persist:$PersistDefault

    Write-Host "Versao ativa: $full ($plat)"
}


function Set-DefaultVersion([string]$tag) {
    Use-Version -tag $tag -PersistDefault

    $plat = Get-PlatformTag
    $full = Resolve-FullVersion -majorOrFull $tag -platformTag $plat
    $cfg = Read-Config
    $cfg.default = $full
    $cfg.platform = $plat
    Write-Config $cfg
    Write-Host "Padrao definido: $full ($plat). O PATH do usuario inclui '$($CurrentLink)'."
}


function Remove-Version([string]$tag) {
    Ensure-Repo
    $plat = Get-PlatformTag
    $full = Resolve-FullVersion -majorOrFull $tag -platformTag $plat
    $destBase = Get-InstallBase -fullVersion $full -platformTag $plat

    if (Test-Path $destBase) {
        if ((Test-Path $CurrentLink) -and ((Get-Item $CurrentLink).Target -like "$destBase*")) {
            Write-Host "Removendo link ativo para $full ..."
            Remove-Item -LiteralPath $CurrentLink -Force -Recurse -Confirm:$false
        }
        Remove-Item -LiteralPath $destBase -Recurse -Force -Confirm:$false
        Write-Host "Versao removida: $full ($plat)"
    }
    else {
        Write-Host "Versao nao instalada: $full ($plat)"
    }
}


# Lista e ordena de forma decrescente as versões instaladas/suportadas e marca a versão ativa, caso exista.
function List-Versions() {
    $plat = Get-PlatformTag
    $idx = Load-Index

    $allLts = $idx | Where-Object { $_.lts -and $_.lts -ne $false }
    $ltsForPlat = $allLts | Where-Object { Supports-Platform $_ $plat }

    Write-Host "=== Versoes LTS suportadas para $plat (Repo oficial) ==="
    if (-not $ltsForPlat -or $ltsForPlat.Count -eq 0) {
        Write-Host "Nenhuma LTS encontrada para $plat no indice."
    } else {
        $majors = @{}
        foreach ($r in $ltsForPlat) {
            $m = (Parse-VersionParts $r.version).Major
            if (-not $majors.ContainsKey($m)) { $majors[$m] = @() }
            $majors[$m] += $r
        }

        $orderedMajors = ($majors.Keys | Sort-Object -Descending)

        foreach ($m in $orderedMajors) {
            $list = Sort-ByVersionDesc $majors[$m]
            $latest = $list | Select-Object -First 1
            Write-Host ("v{0}.x -> {1} (LTS: {2})" -f $m, $latest.version, $latest.lts)
        }
    }

    Write-Host "`n=== Versoes instaladas ==="

    if (Test-Path $VersionsDir) {
        $ltsNameByVersion = @{}
        foreach ($r in $allLts) { $ltsNameByVersion[$r.version] = $r.lts }

        $platformFolders = @('win-x64', 'win-x86', 'win-arm64')

        $activeTarget = $null
        if (Test-Path $CurrentLink) {
            try { $activeTarget = (Get-Item $CurrentLink).Target } catch { $activeTarget = $null }
        }

        $installedAll = @()

        # Procura todas as versoes no repositorio local
        Get-ChildItem -Path $VersionsDir -Directory | ForEach-Object {
            $ver = $_.Name  # ex.: v24.12.0

            $platFound = $null
            $platFullPath = $null
            foreach ($pf in $platformFolders) {
                $p = Join-Path $_.FullName $pf
                if (Test-Path $p) { $platFound = $pf; $platFullPath = $p; break }
            }

            if ($platFound) {
                $activeMark = ""
                if ($activeTarget) {
                    $pattern = (Join-Path $platFullPath "node-*")
                    if ($activeTarget.ToLower() -like $pattern.ToLower()) {
                        $activeMark = "  <- ativa"
                    }
                }

                $ltsName = if ($ltsNameByVersion.ContainsKey($ver)) { $ltsNameByVersion[$ver] } else { "" }

                $installedAll += [pscustomobject]@{
                    version  = $ver
                    platform = $platFound
                    lts      = $ltsName # Existente somente se for LTS
                    active   = $activeMark
                }
            }
        }

        if ($installedAll.Count -eq 0) {
            Write-Host "Nenhuma versao instalada encontrada."
        }
        else {
            $installedAll = $installedAll | Sort-Object @{Expression = {
                    $p = Parse-VersionParts $_.version
                    ($p.Major * 1000000) + ($p.Minor * 1000) + $p.Patch
                }; Descending                                        = $true
            }

            foreach ($i in $installedAll) {
                $ltsLabel = if ([string]::IsNullOrEmpty($i.lts)) { "" } else { " LTS:" + $i.lts }
                Write-Host ("{0} ({1}){2}{3}" -f $i.version, $i.platform, $ltsLabel, $i.active)
            }
        }
    }
    else {
        Write-Host "Repositorio local nao encontrado: $VersionsDir"
    }
}


function Show-Current() {
    if (-not (Test-Path $CurrentLink)) {
        Write-Host "Nenhuma versao ativa no momento. Use o comando 'snvm use v<major>' ou 'snvm default v<major>' para ativar uma versao."
        return
    }

    # Obter alvo do link simbolico (junction)
    $item = Get-Item $CurrentLink
    $target = $item.Target
    if (-not $target -or -not (Test-Path $target)) {
        Write-Host "O link 'current' existe, mas o destino nao foi encontrado. Reative com o comando 'snvm use v<major>'."
        return
    }

    # Ex.: ...\.snvm\versions\v12.22.12\win-x64\node-v12.22.12-win-x64
    $parent = Split-Path -Path $target -Parent
    $plat = Split-Path -Path $parent -Leaf            # win-x64 | win-x86 | win-arm64
    $verDir = Split-Path -Path (Split-Path -Path $parent -Parent) -Leaf  # v12.22.12

    Write-Host "Versao atual do Node:"
    Write-Host ("  Versao    : {0}" -f $verDir)
    Write-Host ("  Plataforma: {0}" -f $plat)
    Write-Host ("  Caminho   : {0}" -f $target)

    # Mostrar node -v/npm -v diretamente do diretorio atual (independente do PATH)
    try {
        $nodeExe = Join-Path $target "node.exe"
        if (Test-Path $nodeExe) {
            $nodeVer = & $nodeExe -v 2>$null
            if ($nodeVer) { Write-Host ("  node -v  : {0}" -f $nodeVer) }
        }
        $npmCmd = Join-Path $target "npm.cmd"
        if (Test-Path $npmCmd) {
            $npmVer = & $npmCmd -v 2>$null
            if ($npmVer) { Write-Host ("  npm -v   : {0}" -f $npmVer) }
        }
    }
    catch { }
}


function Show-Version() {
    Write-Host ("${VERSION}")
}


function Show-Help() {
    @"
Uso:
  snvm install v12       # Baixa/instala ultima v12.x compativel (Windows .zip)
  snvm use v12           # Ativa versao instalada (atualiza .snvm\current)
  snvm default v12       # Define padrao (persiste PATH do usuario)
  snvm remove v12        # Remove versao instalada da serie
  snvm list              # Lista suportadas/instaladas
  snvm current           # Mostra qual versao do Node esta sendo utilizada no momento
  snvm help              # Exibe esta ajuda
  snvm version           # Exibe a versao do snvm

Observacoes:
  - Repositorio: $RepoRoot
  - Versoes:     $VersionsDir\<versao>\<plataforma>
  - Ativa:       $CurrentLink -> link simbolico (junction) para a pasta da versao
"@ | Write-Host
}
#endregion


#region Execucao
switch ($Command) {
    'install' {
        if (-not $VersionTag) { throw "Informe a versao: ex.: snvm install v12" }
        Install-Version -tag $VersionTag
    }
    'use' {
        if (-not $VersionTag) { throw "Informe a versao: ex.: snvm use v12" }
        Use-Version -tag $VersionTag
    }
    'default' {
        if (-not $VersionTag) { throw "Informe a versao: ex.: snvm default v12" }
        Set-DefaultVersion -tag $VersionTag
    }
    'remove' {
        if (-not $VersionTag) { throw "Informe a versao: ex.: snvm remove v12" }
        Remove-Version -tag $VersionTag
    }
    'list' { List-Versions }
    'current' { Show-Current }
    'help' { Show-Help }
    'version' { Show-Version }
}
#endregion
