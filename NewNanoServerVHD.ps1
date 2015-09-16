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
    [string]$isoPath,
    [Parameter(Mandatory=$True)]
    [string]$targetPath,
    [Parameter(Mandatory=$True)]
    [Security.SecureString]$administratorPassword,
    [string]$nanoServerDir = "C:\NanoServer"
)

$ErrorActionPreference = "Stop"

$isoMountDrive = (Mount-DiskImage $isoPath -PassThru | Get-Volume).DriveLetter

try
{
    pushd "${isoMountDrive}:\NanoServer"
    try
    {
        . ".\new-nanoserverimage.ps1"
        New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $nanoServerDir `
        -AdministratorPassword $administratorPassword -TargetPath $targetPath `
        -GuestDrivers -ReverseForwarders
    }
    finally
    {
        popd
    }
}
finally
{
    Dismount-DiskImage $isoPath
}
