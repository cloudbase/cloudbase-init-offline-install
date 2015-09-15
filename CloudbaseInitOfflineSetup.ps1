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
    [string]$VHDPath,
    [string]$cloudbaseInitZipPath = "CloudbaseInitSetup_x64.zip"
)

$ErrorActionPreference = "Stop"

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

if(!(Test-Path -PathType Leaf $cloudbaseInitZipPath))
{
    throw "Zip file ""$cloudbaseInitZipPath"" does not exist"
}

$disk = Mount-Vhd $VHDPath -Passthru
try
{
    $driveLetter = (Get-Disk -Number $d.DiskNumber | Get-Partition).DriveLetter

    $cloudbaseInitBaseDir = "${driveLetter}:\Cloudbase-Init"
    if(Test-Path $cloudbaseInitBaseDir) {
        rmdir -Recurse -Force $cloudbaseInitBaseDir
    }
    mkdir $cloudbaseInitBaseDir

    pushd $cloudbaseInitBaseDir
    try
    {
        $7z = Join-Path $scriptPath "7z.exe"
        & $7z x $cloudbaseInitZipPath -y
        if($LastExitCode) { throw "7z.exe failed to unzip: $cloudbaseInitZipPath"}
    }
    finally
    {
        popd
    }

    $cloudbaseInitConfigDir = Join-Path $cloudbaseInitBaseDir "Config"
    mkdir $cloudbaseInitConfigDir
    $cloudbaseInitLogDir = Join-Path $cloudbaseInitBaseDir "Log"
    mkdir $cloudbaseInitLogDir

    . (Join-Path $scriptPath "ini.ps1")

    $setupScriptsDir = "${driveLetter}:\Windows\Setup\Scripts"
    if(!(Test-Path $setupScriptsDir)) {
        mkdir $setupScriptsDir
    }

    $cloudbaseInitConfigFile = Join-Path $cloudbaseInitConfigDir "cloudbase-init.conf"
    $cloudbaseInitUnattendConfigFile = Join-Path $cloudbaseInitConfigDir "cloudbase-init-unattend.conf"
    $cloudbaseInitBinDir = Join-Path $cloudbaseInitBaseDir "Bin"

    $loggingSerialPortSettings = "COM1,115200,N,8"

    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "username" -Value "Admin"
    # Todo: builtin group names must be retrieved from SID
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "groups" -Value "Administrators"
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "config_drive_raw_hhd" -Value $true
    # Nano does not have DVD drivers
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "config_drive_cdrom" -Value $false
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "config_drive_vfat" -Value $true
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "bsdtar_path" -Value (join-Path $cloudbaseInitBinDir "bsdtar.exe")
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "mtools_path" -Value $cloudbaseInitBinDir
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logdir" -Value $cloudbaseInitLogDir
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logfile" -Value "cloudbase-init.log"
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "default_log_levels" -Value "comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN"
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logging_serial_port_settings" -Value $loggingSerialPortSettings
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "mtu_use_dhcp_config" -Value $true
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "ntp_use_dhcp_config" -Value $true
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "allow_reboot" -Value $true
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "debug" -Value $true

    copy $cloudbaseInitConfigFile $cloudbaseInitUnattendConfigFile

    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "metadata_services" -Value "cloudbaseinit.metadata.services.configdrive.ConfigDriveService,cloudbaseinit.metadata.services.httpservice.HttpService,cloudbaseinit.metadata.services.ec2service.EC2Service,cloudbaseinit.metadata.services.maasservice.MaaSHttpService"
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "plugins" -Value  "cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin"
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "stop_service_on_exit" -Value $false
    Set-IniFileValue -Path $cloudbaseInitUnattendConfigFile -Key "check_latest_version" -Value $false
    Set-IniFileValue -Path $cloudbaseInitConfigFile -Key "logfile" -Value "cloudbase-init-unattend.log"

    copy -Force (Join-Path $scriptPath "SetupComplete.cmd") $setupScriptsDir
    copy -Force (Join-Path $scriptPath "PostInstall.ps1") $setupScriptsDir
}
finally
{
    Dismount-VHD -DiskNumber $disk.DiskNumber
}
