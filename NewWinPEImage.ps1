<#
Copyright 2016 Cloudbase Solutions Srl

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>

param(
    [string]$ADKRoot = "${ENV:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
    [Parameter(Mandatory=$True)]
    [string]$WinPEDir,
    [Parameter(Mandatory=$True)]
    [string]$WinPEISOPath,
    [ValidateSet("x86", "amd64", "ia64")]
    [string]$Arch = "amd64",
    [string]$Language = "en-us",
    [string[]]$ExtraDriversPaths = @(),
    [switch]$AddVirtIODrivers,
    [string]$VirtIODriversISOPath,
    [switch]$AddCloudbaseInit = $true,
    [switch]$AddMaaSHooks,
    [string]$CloudbaseInitZipPath,
    [string]$LoggingCOMPort
)

$ErrorActionPreference = "Stop"

Import-Module "${PSScriptRoot}\Common.psm1"

$packages = @("WinPE-WMI", "WinPE-NetFx",  "WinPE-PowerShell", "WinPE-Scripting", "WinPE-DismCmdlets")

if(Test-Path $WinPEDir)
{
    throw "WinPE directory already exists: $WinPEDir"
}

SetADKVars $ADKRoot | Out-Null

if($AddVirtIODrivers)
{
    if(!$VirtIODriversISOPath)
    {
        $VirtIODriversISOPath = DownloadVirtIODriversISO $env:TEMP
    }

    $driversBasePath = MountISO $VirtIODriversISOPath
    $ExtraDriversPaths += GetVirtIODriverPaths $driversBasePath $Arch
}

& copype.cmd $Arch $WinPEDir | Out-Null
if($LASTEXITCODE) { throw "copype.cmd failed" }

$mountDir =  "${WinPEDir}\mount"
& dism.exe /Mount-Image /ImageFile:"${WinPEDir}\media\sources\boot.wim" /index:1 /MountDir:$mountDir
if($LASTEXITCODE) { throw "Dism /Mount-Image failed" }

try
{
    if ($AddCloudbaseInit)
    {
        if($CloudbaseInitZipPath)
        {
            $zipPath = $CloudbaseInitZipPath
        }
        else
        {
            $zipPath = DownloadCloudbaseInit $env:TEMP $Arch
        }

        . "${PSScriptRoot}\CloudbaseInitOfflineSetup.ps1" `
        -CloudbaseInitBaseDir "${mountDir}\Cloudbase-Init" `
        -CloudbaseInitRuntimeBaseDir "X:\Cloudbase-Init" `
        -CloudbaseInitZipPath $zipPath `
        -LoggingCOMPort $LoggingCOMPort `
        -IsWinPE:$True

        $startnetDir = "${mountDir}\Windows\System32"
        copy "${PSScriptRoot}\PostInstall.ps1" $startnetDir
        Add-Content -Path "${startnetDir}\Startnet.cmd" `
        -Value "powershell.exe -ExecutionPolicy RemoteSigned %SYSTEMROOT%\System32\PostInstall.ps1 -CreateService:`$False"

        if(!$CloudbaseInitZipPath)
        {
            del $zipPath
        }
    }

    if($AddMaaSHooks)
    {
        copy -Recurse "${PSScriptRoot}\windows-curtin-hooks\curtin" "${mountDir}\curtin"
    }

    $packageBasePath = "${ADKRoot}\Windows Preinstallation Environment\${Arch}\WinPE_OCs"
    foreach ($package in $packages)
    {
        $packagePath = "${packageBasePath}\${package}.cab"
        & dism.exe /Add-Package /Image:$mountDir /PackagePath:$packagePath
        if($LASTEXITCODE) { throw "Dism /Add-Package failed for $packagePath" }

        $packagePath = "${packageBasePath}\${Language}\${package}_${Language}.cab"
        & dism.exe /Add-Package /Image:$mountDir /PackagePath:$packagePath
        if($LASTEXITCODE) { throw "Dism /Add-Package failed for $packagePath" }
    }

    foreach($driverPath in $ExtraDriversPaths)
    {
        & dism.exe /Add-Driver /Image:$mountDir /Driver:$driverPath /Recurse
        if($LASTEXITCODE) { throw "Dism /Add-Driver failed for $driverPath" }
    }
}
finally
{
    & dism.exe /Unmount-Image /MountDir:$mountDir /Commit
    if($LASTEXITCODE) { throw "Dism /Unmount-Image failed" }
}

if($AddVirtIODrivers)
{
    # TODO: delete downloaded ISO
    Dismount-DiskImage $VirtIODriversISOPath
}

try
{
    & MakeWinPEMedia.cmd /ISO /f $WinPEDir $WinPEISOPath
    if($LASTEXITCODE) { throw "MakeWinPEMedia failed" }
}
finally
{
    del -Recurse -Force $WinPEDir
}

Write-Host "WinPE image ready: $WinPEISOPath"