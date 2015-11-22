<#
Copyright 2015 Cloudbase Solutions Srl

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

Param(
    [Parameter(Mandatory=$True)]
    [string]$IsoPath,
    [Parameter(Mandatory=$True)]
    [ValidatePattern('\.(vhdx?|raw|qcow2)$')]
    [string]$TargetPath,
    [Parameter(Mandatory=$True)]
    [Security.SecureString]$AdministratorPassword,
    [ValidateSet("Hyper-V", "VMware", "BareMetal")]
    [string]$Platform = "Hyper-V",
    [switch]$Compute,
    [switch]$Storage,
    [switch]$Clustering,
    [switch]$Containers,
    [String[]]$Packages,
    [UInt64]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(512MB, 64TB)]
    $MaxSize = 1GB,
    [string[]]$ExtraDriversPaths = @(),
    [string]$VMWareDriversBasePath = "$Env:CommonProgramFiles\VMware\Drivers",
    [string]$NanoServerDir = "${env:SystemDrive}\NanoServer"
)

$ErrorActionPreference = "Stop"

if(Test-Path $TargetPath)
{
    throw "The target path ""$TargetPath"" already exists, please remove it before running this script"
}

if ($TargetPath -match ".vhdx?$")
{
    $vhdPath = $TargetPath
}
else
{
    $vhdPath = $TargetPath + ".vhdx"
}

$addGuestDrivers = ($Platform -eq "Hyper-V")
# Note: VMWare can work w/o OEMDrivers, except for the keyboard
$addOEMDrivers = ($Platform -ne "Hyper-V")

$isoMountDrive = (Mount-DiskImage $IsoPath -PassThru | Get-Volume).DriveLetter
$isoNanoServerPath = "${isoMountDrive}:\NanoServer"

try
{
    Import-Module "${isoNanoServerPath}\NanoServerImageGenerator.psm1"
    New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $NanoServerDir `
    -MaxSize $MaxSize -AdministratorPassword $AdministratorPassword -TargetPath $vhdPath `
    -GuestDrivers:$addGuestDrivers -OEMDrivers:$addOEMDrivers `
    -ReverseForwarders -Compute:$Compute -Storage:$Storage -Clustering:$Clustering `
    -Containers:$Containers -Packages $Packages
}
finally
{
    Dismount-DiskImage $IsoPath
}

if($Platform -eq "VMware")
{
    if(!(Test-Path -PathType Container $VMWareDriversBasePath))
    {
        throw "VMware drivers path not found: $VMWareDriversBasePath"
    }

    $ExtraDriversPaths += Join-Path $VMWareDriversBasePath "pvscsi"
    $ExtraDriversPaths += Join-Path $VMWareDriversBasePath "vmxnet3"
    $ExtraDriversPaths += Join-Path $VMWareDriversBasePath "vmci\device"
}

$featuresToEnable = @()

if($Storage)
{
    # File-Services, needed for S2D, is not enabled by default
    $featuresToEnable += "File-Services"
}

if($ExtraDriversPaths -or $featuresToEnable)
{
    $dismPath = Join-Path $NanoServerDir "Tools\dism.exe"
    $mountDir = Join-Path $NanoServerDir "MountDir"

    if(!(Test-Path $mountDir))
    {
        mkdir $mountDir
    }

    & $dismPath /Mount-Image /ImageFile:$vhdPath /Index:1 /MountDir:$mountDir
    if($lastexitcode) { throw "dism /Mount-Image failed"}

    try
    {
        foreach($featureName in $featuresToEnable)
        {
            & $dismPath /Enable-Feature /image:$mountDir /FeatureName:$featureName
        }

        foreach($driverPath in $ExtraDriversPaths)
        {
            & $dismPath /Add-Driver /image:$mountDir /driver:$driverPath /Recurse
            if($lastexitcode) { throw "dism /Add-Driver failed for path: $driverPath"}
        }
    }
    finally
    {

        & $dismPath /Unmount-Image /MountDir:$mountDir /Commit
        if($lastexitcode) { throw "dism /Unmount-Image failed"}
    }
}

if ($vhdPath -ne $TargetPath)
{
    if(Test-Path -PathType Leaf $TargetPath)
    {
        del $TargetPath
    }

    $diskFormat = [System.IO.Path]::GetExtension($TargetPath).substring(1).ToLower()

    echo "Converting disk image to target format: $diskFormat"
    & $PSScriptRoot\Bin\qemu-img.exe convert -O $diskFormat $vhdPath $TargetPath
    if($lastexitcode) { throw "qemu-img.exe convert failed" }
    del $vhdPath
}
