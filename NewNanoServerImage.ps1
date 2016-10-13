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
    [ValidatePattern('\.(vhdx?|raw|raw.gz|raw.tgz|vmdk|qcow2)$')]
    [string]$TargetPath,
    [ValidateSet("BIOS", "UEFI")]
    [string]$DiskLayout = "BIOS",
    [Parameter(Mandatory=$True)]
    [Security.SecureString]$AdministratorPassword,
    [ValidateSet("Hyper-V", "VMware", "KVM", "BareMetal")]
    [string]$Platform = "Hyper-V",
    [switch]$Compute,
    [switch]$Storage,
    [switch]$Clustering,
    [switch]$Containers,
    [String[]]$Packages,
    [UInt64]
    [ValidateNotNullOrEmpty()]
    [ValidateRange(512MB, 64TB)]
    $MaxSize = 1.5GB,
    [string[]]$ExtraDriversPaths = @(),
    [string]$VMWareDriversBasePath = "$Env:CommonProgramFiles\VMware\Drivers",
    [string]$VirtIODriversISOPath,
    [string]$NanoServerDir = "${env:SystemDrive}\NanoServer",
    [switch]$AddCloudbaseInit = $true,
    [switch]$AddMaaSHooks,
    [string]$CloudbaseInitZipPath,
    [string]$CloudbaseInitCOMPort = "COM1",
    [Parameter(Mandatory=$False)]
    [string]$ServerEdition = "Standard" # ["Standard" | "Datacenter"]
)

$ErrorActionPreference = "Stop"

Import-Module "${PSScriptRoot}\Common.psm1"
$arch = "amd64"

if(Test-Path $TargetPath)
{
    throw "The target path ""`$TargetPath"" already exists, please remove it before running this script"
}

if($CloudbaseInitZipPath -and !(Test-Path -PathType Leaf $CloudbaseInitZipPath))
{
    throw "The path ""$CloudbaseInitZipPath"" was not found"
}

# Note: currently VHDX creates a GPT EFI image for Gen2, while VHD targets a MBR BIOS Gen1.
if($DiskLayout -eq "BIOS")
{
    $vhdPathFormat = "vhd"
}
else
{
    $vhdPathFormat = "vhdx"
}

$diskFormat = [System.IO.Path]::GetExtension($TargetPath).substring(1).ToLower()

if ($diskFormat -eq $vhdPathFormat)
{
    $vhdPath = $TargetPath
}
else
{
    $vhdPath = "${TargetPath}.${vhdPathFormat}"
}

# Note: KVM supports some Hyper-V enlightenments.
# Note: VMWare can work w/o Guest or OEM drivers, except for the keyboard
$addGuestDrivers = (@("Hyper-V", "KVM", "VMware") -contains $Platform)
$addOEMDrivers = (@("Hyper-V", "KVM", "VMware") -notcontains $Platform)

$deploymentType = "Host"
if ($addGuestDrivers) {
   $deploymentType = "Guest"
}

$isoMountDrive = (Mount-DiskImage $IsoPath -PassThru | Get-Volume).DriveLetter
$isoNanoServerPath = "${isoMountDrive}:\NanoServer"

try
{
    Import-Module "${isoNanoServerPath}\NanoServerImageGenerator\NanoServerImageGenerator.psm1"
    New-NanoServerImage -MediaPath "${isoMountDrive}:\" -BasePath $NanoServerDir `
    -MaxSize $MaxSize -AdministratorPassword $AdministratorPassword -TargetPath $vhdPath `
    -DeploymentType $DeploymentType -OEMDrivers:$addOEMDrivers `
    -Compute:$Compute -Storage:$Storage -Clustering:$Clustering `
    -Containers:$Containers -Edition $ServerEdition
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

if($Platform -eq "KVM")
{
    if(!$VirtIODriversISOPath)
    {
        $VirtIODriversISOPath = DownloadVirtIODriversISO $NanoServerDir
    }

    $driversBasePath = MountISO $VirtIODriversISOPath
    $ExtraDriversPaths += GetVirtIODriverPaths $driversBasePath $arch
}

$featuresToEnable = @()

if($Storage)
{
    # File-Services, needed for S2D, is not enabled by default
    $featuresToEnable += "File-Services"
}

if($ExtraDriversPaths -or $featuresToEnable -or $AddMaaSHooks -or $AddCloudbaseInit)
{
    $dismPath = $(Get-Command dism | select Source -ExpandProperty Source)
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
            if($lastexitcode) { throw "dism /Enable-Feature failed for feature: $featureName"}
        }

        foreach($driverPath in $ExtraDriversPaths)
        {
            & $dismPath /Add-Driver /image:$mountDir /driver:$driverPath /Recurse /ForceUnsigned
            if($lastexitcode) { throw "dism /Add-Driver failed for path: $driverPath"}
        }

        if($AddMaaSHooks)
        {
            copy -Recurse "${PSScriptRoot}\windows-curtin-hooks\curtin" "${mountDir}\curtin"
        }

        if($AddCloudbaseInit)
        {
            if($CloudbaseInitZipPath)
            {
                $zipPath = $CloudbaseInitZipPath
            }
            else
            {
                $zipPath = DownloadCloudbaseInit $NanoServerDir $arch
            }

            $cloudbaseInitDir = "Cloudbase-Init"
            $cloudbaseInitBaseDir = Join-Path $mountDir $cloudbaseInitDir
            $cloudbaseInitRuntimeBaseDir = "C:\${cloudbaseInitDir}"

            $setupScriptsDir = Join-Path $mountDir "Windows\Setup\Scripts"
            if(!(Test-Path $setupScriptsDir)) {
                $d = mkdir $setupScriptsDir
            }

            . "${PSScriptRoot}\CloudbaseInitOfflineSetup.ps1" -CloudbaseInitBaseDir $cloudbaseInitBaseDir `
            -CloudbaseInitRuntimeBaseDir $cloudbaseInitRuntimeBaseDir `
            -CloudbaseInitZipPath $zipPath `
            -LoggingCOMPort $CloudbaseInitCOMPort

            copy -Force (Join-Path $PSScriptRoot "SetupComplete.cmd") $setupScriptsDir
            copy -Force (Join-Path $PSScriptRoot "PostInstall.ps1") $setupScriptsDir

            if(!$CloudbaseInitZipPath)
            {
                del $zipPath
            }
        }
    }
    finally
    {
        & $dismPath /Unmount-Image /MountDir:$mountDir /Commit
        if($lastexitcode) { throw "dism /Unmount-Image failed"}
    }
}

if($Platform -eq "KVM")
{
    Dismount-DiskImage $VirtIODriversISOPath
}

$diskImage = Mount-DiskImage $vhdPath -PassThru | Get-DiskImage
try
{
    $driveLetter = (Get-Disk -Number $diskImage.Number | Get-Partition).DriveLetter | where {$_}
    $logicalDisk = Get-CimInstance Win32_LogicalDisk -filter ("DeviceId = '{0}:'" -f $driveLetter)

    Write-Output ("Total space on Nano image partition: {0:N2} MB" -f ($logicalDisk.Size / 1MB))

    $msg = "Free space on Nano image partition: {0:N2} MB" -f ($logicalDisk.FreeSpace / 1MB)
    if($logicalDisk.FreeSpace -lt 100MB)
    {
        Write-Warning $msg
    }
    else
    {
        Write-Output $msg
    }
}
finally
{
    Dismount-DiskImage $vhdPath
}

if ($vhdPath -ne $TargetPath)
{
    if(Test-Path -PathType Leaf $TargetPath)
    {
        del $TargetPath
    }

    $tar = $false
    $gzip = $false
    if($diskFormat -eq "gz" -or $diskFormat -eq "tgz")
    {
        if($diskFormat -eq "tgz")
        {
            $tar = $true
        }
        $gzip = $true
        $imagePath = $TargetPath.Substring(0, $TargetPath.LastIndexOf("."))
        $diskFormat = [System.IO.Path]::GetExtension($imagePath).substring(1).ToLower()
    }
    else
    {
        $imagePath = $TargetPath
    }

    echo "Converting disk image to target image format: $diskFormat"
    if(@("vhd", "vhdx") -contains $diskFormat)
    {
        Convert-VHD -Path $vhdPath -DestinationPath $imagePath
    }
    else
    {
        & $PSScriptRoot\Bin\qemu-img.exe convert -O $diskFormat $vhdPath $imagePath
        if($lastexitcode) { throw "qemu-img.exe convert failed" }
    }
    del $vhdPath

    if($tar)
    {
        $imagePathTmp = "${imagePath}.tar"
        if(Test-Path $imagePathTmp)
        {
            del $imagePathTmp
        }

        pushd ([System.IO.Path]::GetDirectoryName((Resolve-path $imagePath).Path))
        try
        {
            # Avoid storing the full path in the archive
            $imageFileName = (Get-Item $imagePath).Name
            echo "Creating tar archive..."
            & $PSScriptRoot\Bin\7za.exe a -ttar $imagePathTmp $imageFileName
            if($lastexitcode) { throw "7za.exe failed while creating tar file for image: $imagePath" }
        }
        finally
        {
            popd
        }

        del $imagePath
        $imagePath = $imagePathTmp
    }

    if($gzip)
    {
        $imagePathGzip = "${imagePath}.gz"
        if(Test-Path $imagePathGzip)
        {
            del $imagePathGzip
        }

        echo "Compressing with gzip..."
        & $PSScriptRoot\Bin\pigz.exe $imagePath
        if($lastexitcode) { throw "pigz.exe failed while compressing: $imagePath" }

        if($imagePathGzip -ine $TargetPath)
        {
            Rename-Item $imagePathGzip $TargetPath
        }
    }
}
