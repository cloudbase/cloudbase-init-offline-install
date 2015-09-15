#
# Copyright 2014-2015 Cloudbase Solutions Srl
#
param(
    # to be changed: the folder where the wim image is mounted
    [Parameter(Mandatory=$True)]
    [string]$MountFolder = "E:",
    # to be changed: the local folder where the cloudbase init files are
    [Parameter(Mandatory=$True)]
    [string]$CloudbaseInitFilesDir = "C:\Program Files (x86)\Cloudbase Solutions",
    # to be changed: the local file path for the PostInstall.ps1 file
    # this script will be run as a RunSynchronousCommand from the specialize part in the Unattend.xml
    [Parameter(Mandatory=$True)]
    [string]$PostInstallPath = ".\PostInstall.ps1",
    [Parameter(Mandatory=$True)]
    [string]$SetupCompletePath = ".\SetupComplete.cmd",
    [Parameter(Mandatory=$True)]
    [string]$UnattendXmlPath = ".\Unattend.xml"
)

$ErrorActionPreference = "Stop"

function Create-RegService {
    param(
        $serviceName,
        $regKeyRoot,
        $cloudbaseInitProgramFiles)

    $cloudbaseInitInstallFolder = "`\`"C:" + $cloudbaseInitProgramFiles + "\Cloudbase-Init\"
    $cloudbaseInitOpenstackService = $cloudbaseInitInstallFolder + "bin\OpenStackService.exe`\`""
    $cloudbaseInitBinary = $cloudbaseInitInstallFolder + "Python27\Scripts\cloudbase-init.exe`\`""
    $cloudbaseInitConf = $cloudbaseInitInstallFolder + "conf\cloudbase-init.conf`\`""

    $properties = @(
        @{"Name" = "DependOnService"; "Type"="REG_MULTI_SZ"; "Data" = "Winmgmt"},
        @{"Name" = "Description"; "Type"="REG_SZ"; "Data" = "Service wrapper for $serviceName"},
        @{"Name" = "DisplayName"; "Type"="REG_SZ"; "Data" = "Cloud Initialization Service"},
        @{"Name" = "ObjectName"; "Type"="REG_SZ"; "Data" = "cloudbase-init"},
        @{"Name" = "ImagePath"; "Type"="REG_EXPAND_SZ"; "Data" =  ($cloudbaseInitOpenstackService + " cloudbase-init " + $cloudbaseInitBinary + " --config-file " + $cloudbaseInitConf) },
        @{"Name" = "Start"; "Type"="REG_DWORD"; "Data" = 2},
        @{"Name" = "Type"; "Type"="REG_DWORD"; "Data" = 16},
        @{"Name" = "ErrorControl"; "Type"="REG_DWORD"; "Data" = 0}
        )

    $regKeyService = Join-Path $regKeyRoot $serviceName
    if (!(Test-Path $regKeyService -ErrorAction SilentlyContinue)) {
        REG ADD "$regKeyRoot\$serviceName" /f
    } else {
        Write-Host "Service key already exists"
    }

    foreach ($property in $properties) {
    $data=$property["Data"]
        REG ADD "$regKeyRoot\$serviceName" /f /v $property["Name"] /t $property["Type"] /d "${data}"
    }
}

function Create-CloudbaseInitService {
    param($mountFolder,
        $cloudbaseInitFilesDir)

    $cloudbaseInitProgramFiles = "\Program Files\Cloudbase Solutions"
    $registryName = "hivename"
    $regKeyRoot1 = "HKLM\$registryName\ControlSet001\Services"
    $regKeyRoot2 = "HKLM\$registryName\ControlSet002\Services"
    $serviceName = "cloudbase-init"

    #Copy cloudbase-init files to the mounted image
    Copy-Item -Recurse  $cloudbaseInitFilesDir ("$mountFolder" + $cloudbaseInitProgramFiles)

    # create the cloudbase-init service using registry key hive from the mounted image
    reg load "HKLM\$registryName" "$mountFolder\windows\system32\config\system"
    Create-RegService $serviceName $regKeyRoot1 $cloudbaseInitProgramFiles
    Create-RegService $serviceName $regKeyRoot2 $cloudbaseInitProgramFiles
    reg unload "HKLM\$registryName"
}

###################BEGIN###################################################

# copy the post install script to the mounted image
$postInstallImagePath = "$mountFolder\UnattendResources\PostInstall.ps1"
$postInstallImageParentPath = Split-Path -Parent $postInstallImagePath
if (!(Test-Path $postInstallImageParentPath)) {
    New-Item -Type Directory -Path $postInstallImageParentPath
}
# copy postinstall script
cp -force $postInstallPath $postInstallImagePath

# copy SetupComplete script
$imageSetupCompletePath = "$MountFolder\Windows\Setup\Scripts\SetupComplete.cmd"
$setupCompleteParentPath = Split-Path -Parent $imageSetupCompletePath
if (!(Test-Path $setupCompleteParentPath)) {
    New-Item -Type Directory -Path $setupCompleteParentPath
}
cp -force $SetupCompletePath $imageSetupCompletePath

# create cloudbase-init service
Create-CloudbaseInitService $mountFolder $cloudbaseInitFilesDir

# copy the unattend file
# this step is not mandatory, as long as you have an apropriate Unattend.xml
cp -force $UnattendXmlPath "$mountFolder\Unattend.xml"

