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
    [string]$TargetPath,
    [Parameter(Mandatory=$True)]
    [Security.SecureString]$AdministratorPassword,
    [ValidateSet("Hyper-V", "VMware", "BareMetal")]
    [string]$Platform = "Hyper-V",
    [ValidateSet("vmdk", "vhd", "vhdx", "qcow2", "raw")]
    [string]$DiskFormat, # Format selected based on the platform by default
    [switch]$Compute,
    [switch]$Storage,
    [switch]$Clustering,
    [UInt64]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(512MB, 64TB)]
    $SizeBytes = 750MB,
    [string[]]$ExtraDriversPaths = @(),
    [string]$VMWareDriversBasePath = "$Env:CommonProgramFiles\VMware\Drivers",
    [string]$NanoServerDir = "${env:SystemDrive}\NanoServer"
)

$ErrorActionPreference = "Stop"

if(Test-Path $TargetPath)
{
    throw "The target directory ""$TargetPath"" already exists, please remove it before running this script"
}

$addGuestDrivers = ($Platform -eq "Hyper-V")
# Note: VMWare can work w/o OEMDrivers, except for the keyboard
$addOEMDrivers = ($Platform -ne "Hyper-V")

if(!$DiskFormat)
{
    switch($Platform)
    {
        "Hyper-V"
        {
            $DiskFormat = "vhdx"
        }
        "VMware"
        {
            $DiskFormat = "vmdk"
        }
        default # BareMetal
        {
            $DiskFormat = "raw"
        }
    }
}

$isoMountDrive = (Mount-DiskImage $IsoPath -PassThru | Get-Volume).DriveLetter

try
{
    # The following hack is necessary because New-NanoServerImage (TP3) does
    # not provide a way to pass the target image size to Convert-WindowsImage.
    # For now we just update dynamically the script waiting for a fix
    # in an updated version of New-NanoServerImage.
    $isoNanoServerPath = "${isoMountDrive}:\NanoServer"
    copy (Join-Path $isoNanoServerPath "convert-windowsimage.ps1") $PSScriptRoot -Force
    Get-Content (Join-Path $isoNanoServerPath "new-nanoserverimage.ps1") | `
    Foreach-Object {$_ -replace "Convert-WindowsImage -SourcePath", "Convert-WindowsImage -SizeBytes $SizeBytes -SourcePath"} | `
    Set-Content "$PSScriptRoot\new-nanoserverimage.ps1" -Force

    $baseVhdPath = Join-Path $NanoServerDir "NanoServer.vhd"
    if(Test-Path -PathType Leaf $baseVhdPath)
    {
        # Check if the base VHD needs to be rebuilt
        if ((get-VHD C:\NanoServer\NanoServer.vhd).Size -ne $SizeBytes)
        {
            del -Force $baseVhdPath
        }
    }

    . "$PSScriptRoot\new-nanoserverimage.ps1"
    New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $NanoServerDir `
    -AdministratorPassword $AdministratorPassword -TargetPath $TargetPath `
    -GuestDrivers:$addGuestDrivers -OEMDrivers:$addOEMDrivers `
    -ReverseForwarders -Compute:$Compute -Storage:$Storage -Clustering:$Clustering
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

$vhdPath =  Join-Path $TargetPath "$(Split-Path -Leaf $TargetPath).vhd"

$featuresToEnable = @()

if($Storage)
{
    # File-Services, needed for S2D, is not enabled by default
    $featuresToEnable += "File-Services"
}

if($ExtraDriversPaths -or $featuresToEnable)
{
    $dismPath = Join-Path $NanoServerDir "Tools\dism.exe"
    $mountDir = Join-Path $TargetPath "MountDir"

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

if($DiskFormat -eq "vhdx")
{
    $vhdxPath = "${vhdPath}x"
    Convert-VHD $vhdPath $vhdxPath
    del $vhdPath
}
elseif ($DiskFormat -ne "vhd")
{
    $path = Get-Item $vhdPath
    $diskPath = Join-Path $path.Directory ($path.BaseName + "." + $DiskFormat)

    if(Test-Path -PathType Leaf $diskPath)
    {
        del $diskPath
    }

    echo "Converting disk image to target format: $DiskFormat"
    & $PSScriptRoot\Bin\qemu-img.exe convert -O $DiskFormat $vhdPath $diskPath
    if($lastexitcode) { throw "qemu-img.exe convert failed" }
    del $vhdPath
}
