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

param(
    [Parameter(Mandatory=$True)]
    [string]$CloudbaseInitBaseDir,
    [Parameter(Mandatory=$True)]
    [string]$CloudbaseInitRuntimeBaseDir,
    [string]$CloudbaseInitZipPath = "CloudbaseInitSetup_x64.zip",
    [string]$LoggingCOMPort,
    [switch]$IsWinPE
)

$ErrorActionPreference = "Stop"

$CloudbaseInitZipPath = Resolve-Path $CloudbaseInitZipPath
if(!(Test-Path -PathType Leaf $CloudbaseInitZipPath))
{
    throw "Zip file ""$CloudbaseInitZipPath"" does not exist"
}

if(Test-Path $CloudbaseInitBaseDir) {
    rmdir -Recurse -Force $CloudbaseInitBaseDir
}
$d = mkdir $CloudbaseInitBaseDir

pushd $CloudbaseInitBaseDir
try
{
    echo "Unzipping Cloudbase-Init..."
    & "$PSScriptRoot\Bin\7za.exe" x $CloudbaseInitZipPath -y | Out-Null
    if($LastExitCode) { throw "7za.exe failed to unzip: $CloudbaseInitZipPath"}
}
finally
{
    popd
}

$cloudbaseInitConfigDir = Join-Path $CloudbaseInitBaseDir "conf"
$d = mkdir $cloudbaseInitConfigDir
$cloudbaseInitLogDir = Join-Path $CloudbaseInitBaseDir "Log"
$d = mkdir $cloudbaseInitLogDir

. (Join-Path $PSScriptRoot "ini.ps1")

$cloudbaseInitConfigFile = Join-Path $cloudbaseInitConfigDir "cloudbase-init.conf"
$cloudbaseInitUnattendConfigFile = Join-Path $cloudbaseInitConfigDir "cloudbase-init-unattend.conf"

$cloudbaseInitRuntimeLogDir = "${CloudbaseInitRuntimeBaseDir}\Log"
$cloudbaseInitRuntimeBinDir = "${CloudbaseInitRuntimeBaseDir}\Bin"

Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "username" -Value "Admin"
# Todo: builtin group names must be retrieved from SID
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "groups" -Value "Administrators"
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "inject_user_password" -Value $true
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "config_drive_raw_hhd" -Value $true
# Nano does not have DVD drivers
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "config_drive_cdrom" -Value $false
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "config_drive_vfat" -Value $true
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "bsdtar_path" -Value "${CloudbaseInitRuntimeBinDir}\bsdtar.exe"
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "mtools_path" -Value $cloudbaseInitRuntimeBinDir
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logdir" -Value $cloudbaseInitRuntimeLogDir
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logfile" -Value "cloudbase-init.log"
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "default_log_levels" -Value "comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN"
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "mtu_use_dhcp_config" -Value $true
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "ntp_use_dhcp_config" -Value $true
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "allow_reboot" -Value $true
Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "debug" -Value $true

if($LoggingCOMPort) {
    $loggingSerialPortSettings = "${LoggingCOMPort},115200,N,8"
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logging_serial_port_settings" -Value $loggingSerialPortSettings
}

if($IsWinPE) {
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "plugins" -Value  `
    ("cloudbaseinit.plugins.common.mtu.MTUPlugin," + `
    "cloudbaseinit.plugins.windows.ntpclient.NTPClientPlugin," + `
    "cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin," + `
    "cloudbaseinit.plugins.common.userdata.UserDataPlugin," + `
    "cloudbaseinit.plugins.common.localscripts.LocalScriptsPlugin")
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "stop_service_on_exit" -Value $false
} else {
    copy $cloudbaseInitConfigFile $cloudbaseInitUnattendConfigFile

    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "metadata_services" -Value "cloudbaseinit.metadata.services.configdrive.ConfigDriveService,cloudbaseinit.metadata.services.httpservice.HttpService,cloudbaseinit.metadata.services.ec2service.EC2Service,cloudbaseinit.metadata.services.maasservice.MaaSHttpService"
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "plugins" -Value  "cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin"
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "stop_service_on_exit" -Value $false
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "check_latest_version" -Value $false
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "logfile" -Value "cloudbase-init-unattend.log"
}

Write-Host
Write-Host "Cloudbase-Init offline setup done!"
