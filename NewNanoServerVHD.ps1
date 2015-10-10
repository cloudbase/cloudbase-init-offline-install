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
    pushd "${isoMountDrive}:\NanoServer"
    try
    {
        . ".\new-nanoserverimage.ps1"
        New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $NanoServerDir `
        -AdministratorPassword $AdministratorPassword -TargetPath $TargetPath `
        -GuestDrivers:$addGuestDrivers -OEMDrivers:$addOEMDrivers `
        -ReverseForwarders -Compute:$Compute -Storage:$Storage -Clustering:$Clustering
    }
    finally
    {
        popd
    }
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

if($ExtraDriversPaths)
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

# .\new-nanoserverimage.ps1 dos not have a VHD size attribute
$vhdxPath = "${vhdPath}x"
# Convert to VHDX as VHD does not allow resizing down
Convert-VHD $vhdPath $vhdxPath
del $vhdPath

$disk = Mount-Vhd $vhdxPath -Passthru
try
{
    $part = $disk | Get-Partition
    $sizeMin = ($part |  Get-PartitionSupportedSize).SizeMin
    $part | Resize-Partition -Size $sizeMin
}
finally
{
    Dismount-VHD -DiskNumber $disk.DiskNumber
}

Resize-VHD $vhdxPath -ToMinimumSize

if($DiskFormat -eq "vhd")
{
    Convert-VHD $vhdxPath $vhdPath
    del $vhdxPath
}
elseif ($DiskFormat -ne "vhdx")
{
    $path = Get-Item $vhdxPath
    $diskPath = Join-Path $path.Directory ($path.BaseName + "." + $DiskFormat)

    if(Test-Path -PathType Leaf $diskPath)
    {
        del $diskPath
    }

    echo "Converting disk image to target format: $DiskFormat"
    & $PSScriptRoot\Bin\qemu-img.exe convert -O $DiskFormat $vhdxPath $diskPath
    if($lastexitcode) { throw "qemu-img.exe convert failed" }
    del $vhdxPath
}
