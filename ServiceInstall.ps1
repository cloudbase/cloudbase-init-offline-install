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
    [string]$PostInstallPath = ".\UnattendResources\Postinstall.ps1"
)

$ErrorActionPreference = "Stop"

function Create-RegService {
    param(
        $serviceName,
        $regKeyRoot)

    $properties = @(
        @{"Name" = "DependOnService"; "Type"="REG_MULTI_SZ"; "Data" = "Winmgmt"},
        @{"Name" = "Description"; "Type"="REG_SZ"; "Data" = "Service wrapper for $serviceName"},
        @{"Name" = "DisplayName"; "Type"="REG_SZ"; "Data" = "Cloud Initialization Service"},
        @{"Name" = "ObjectName"; "Type"="REG_SZ"; "Data" = "cloudbase-init"},
        @{"Name" = "ImagePath"; "Type"="REG_EXPAND_SZ"; "Data" = "`\`"C:\Program Files (x86)\Cloudbase Solutions\Cloudbase-Init\bin\OpenStackService.exe`\`" cloudbase-init `\`"C:\Program Files (x86)\Cloudbase Solutions\Cloudbase-Init\Python27\Scripts\cloudbase-init.exe`\`" --config-file `\`"c:\Program Files (x86)\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf`\`""},
        @{"Name" = "Start"; "Type"="REG_DWORD"; "Data" = 3},
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
    $registryName = "hivename"
    $regKeyRoot1 = "HKLM\$registryName\ControlSet001\Services"
    $regKeyRoot2 = "HKLM\$registryName\ControlSet002\Services"
    $serviceName = "cloudbase-init"

    #Copy cloudbase-init files to the mounted image
    Copy-Item -Recurse  $cloudbaseInitFilesDir "$mountFolder\Program Files (x86)\Cloudbase Solutions"

    # create the cloudbase-init service using registry key hive from the mounted image
    reg load "HKLM\$registryName" "$mountFolder\windows\system32\config\system"
    Create-RegService $serviceName $regKeyRoot1
    Create-RegService $serviceName $regKeyRoot2
    reg unload "HKLM\$registryName"
}


###################BEGIN###################################################

# copy the post install script to the mounted image
$postInstallImagePath = "$mountFolder\UnattendResources\Postinstall.ps1"
$postInstallImageParentPath = Split-Path -Parent $postInstallImagePath
if (!(Test-Path $postInstallImageParentPath)) {
    mkdir $postInstallImageParentPath
}
# copy postinstall script
cp -force $postInstallPath $postInstallImagePath

# create cloudbase-init service
Create-CloudbaseInitService $mountFolder $cloudbaseInitFilesDir

# copy the unattend file
# this step is not mandatory, as long as you have an apropriate Unattend.xml
#cp -force OfflineUnattend.xml "$mountFolder\Unattend.xml"

# Add in Unattend.xml:
#  <settings pass="specialize">
#    <component name="Microsoft-Windows-Deployment" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" processorArchitecture="amd64" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
#      <RunSynchronous>
#        <RunSynchronousCommand wcm:action="add">
#          <Order>1</Order>
#          <Path>cmd /c "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy RemoteSigned -File C:\UnattendResources\Postinstall.ps1"</Path>
#          <Description>pywin postinstall script1</Description>
#        </RunSynchronousCommand>
#      </RunSynchronous>
#    </component>
#  </settings>

