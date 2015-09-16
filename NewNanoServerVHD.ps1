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
    [string]$NanoServerDir = "C:\NanoServer"
)

$ErrorActionPreference = "Stop"

$isoMountDrive = (Mount-DiskImage $IsoPath -PassThru | Get-Volume).DriveLetter

try
{
    pushd "${isoMountDrive}:\NanoServer"
    try
    {
        . ".\new-nanoserverimage.ps1"
        $out = New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $NanoServerDir `
        -AdministratorPassword $AdministratorPassword -TargetPath $TargetPath `
        -GuestDrivers -ReverseForwarders
        Write-Host $out
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

# .\new-nanoserverimage.ps1 dos not have a VHD size attribute
$vhdPath =  Join-Path $TargetPath "$(Split-Path -Leaf $TargetPath).vhd"
$vhdxPath = "${vhdPath}x"
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
return $vhdxPath
