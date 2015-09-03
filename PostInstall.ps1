#
# Copyright 2014-2015 Cloudbase Solutions Srl
#
$ErrorActionPreference = "Stop"

$Source = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace PSCloudbase
{
    public sealed class Win32CryptApi
    {
        public static long CRYPT_SILENT                     = 0x00000040;
        public static long CRYPT_VERIFYCONTEXT              = 0xF0000000;
        public static int PROV_RSA_FULL                     = 1;

        [DllImport("advapi32.dll", CharSet=CharSet.Auto, SetLastError=true)]
        [return : MarshalAs(UnmanagedType.Bool)]
        public static extern bool CryptAcquireContext(ref IntPtr hProv,
                                                      StringBuilder pszContainer, // Don't use string, as Powershell replaces $null with an empty string
                                                      StringBuilder pszProvider, // Don't use string, as Powershell replaces $null with an empty string
                                                      uint dwProvType,
                                                      uint dwFlags);

        [DllImport("Advapi32.dll", EntryPoint = "CryptReleaseContext", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CryptReleaseContext(IntPtr hProv, Int32 dwFlags);

        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern bool CryptGenRandom(IntPtr hProv, uint dwLen, byte[] pbBuffer);

        [DllImport("Kernel32.dll")]
        public static extern uint GetLastError();
    }
}
"@
Add-Type -TypeDefinition $Source -Language CSharp

function Grant-Privilege {
    param($username, $privilege)

    $tempPath = [System.IO.Path]::GetTempPath()
    $import = Join-Path -Path $tempPath -ChildPath "import.inf"
    $export = Join-Path -Path $tempPath -ChildPath "export.inf"
    $secedt = Join-Path -Path $tempPath -ChildPath "secedit.sdb"

    secedit /export /cfg $export
    $privilegeAssignedAccounts = (Select-String $export -Pattern $privilege).Line
    $templateLines = @("[Unicode]", "Unicode=yes", "[System Access]", "[Event Audit]",
                  "[Registry Values]", "[Version]", "signature=`"`$CHICAGO$`"",
                  "Revision=1", "[Profile Description]", "Description=Privilege $privilege security template",
                  "[Privilege Rights]","$privilegeAssignedAccounts,$username")
    foreach ($line in  $templateLines) {
      Add-Content $import $line
    }
    secedit /import /db $secedt /cfg $import
    secedit /configure /db $secedt
    gpupdate /force
    Remove-Item -Force $import
    Remove-Item -Force $export
    Remove-Item -Force $secedt
}

function Get-RandomPassword
{
    [CmdletBinding()]
    Param
    (
        [parameter(Mandatory=$true)]
        [int]
        $Length
    )

    process
    {
        $hProvider = 0
        try {
            if (![PSCloudbase.Win32CryptApi]::CryptAcquireContext(
                [ref]$hProvider, $null, $null,
                [PSCloudbase.Win32CryptApi]::PROV_RSA_FULL,
                ([PSCloudbase.Win32CryptApi]::CRYPT_VERIFYCONTEXT -bor
                [PSCloudbase.Win32CryptApi]::CRYPT_SILENT))) {
                throw "CryptAcquireContext failed with error: 0x" + "{0:X0}" `
                    -f [PSCloudbase.Win32CryptApi]::GetLastError()
            }

            $buffer = New-Object byte[] $Length
            if(![PSCloudbase.Win32CryptApi]::CryptGenRandom($hProvider,
                                                           $Length, $buffer)) {
                throw "CryptGenRandom failed with error: 0x" + "{0:X0}" `
                    -f [PSCloudbase.Win32CryptApi]::GetLastError()
            }

            $buffer | ForEach-Object { $password += "{0:X0}" -f $_ }
            return $password
        } finally {
            if($hProvider)
            {
                $retVal = [PSCloudbase.Win32CryptApi]::CryptReleaseContext(
                             $hProvider, 0)
            }
        }
    }
}

<#

.SYNOPSIS

Generates a strong password, appropriate for a Windows user account. The
password must pass the password policy requirements:
https://technet.microsoft.com/en-us/library/hh994572%28WS.10%29.aspx

.DESCRIPTION

In order to respect the password policy requirements, the generated pasword has
16 characters and is constructed using advapi.dll's CryptGenRandom.

.EXAMPLE

$password = Generate-StrongPassword

.Notes

The user under which this command is run must have the appropriate privilleges
and to be a local administrator in order to be able to execute the command
successfully.

#>

function Generate-StrongPassword {
    $maxRetries = 10
    $retries = 0
    while ($retries -lt $maxRetries) {
        $password = (Get-RandomPassword 15) + "^"
        if (($password -cmatch '[\p{Ll}]' -or $password -cmatch '[\p{Lu}]') `
                -and $password -cmatch '[\p{Nd}]' `
                -and $password -cmatch '[^\p{Ll}\p{Lu}\p{Nd}]' `
                -and $password -cnotmatch '\s') {
            return $password
        }
        $retries = $retries + 1
    }
    throw "Failed to generate strong password"
}

function Convert-SIDToFriendlyName {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$SID
    )

    $objSID = New-Object System.Security.Principal.SecurityIdentifier($SID)
    $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
    $name = $objUser.Value
    $n = $name.Split("\")
    if ($n.length -gt 1){
        return $n[1]
    }
    return $n[0]
}

function Create-LocalAdmin {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalAdminUsername,
        [Parameter(Mandatory=$true)]
        [string]$LocalAdminPassword
    )
    
    net user /add $LocalAdminUsername $LocalAdminPassword /y
    if ($LASTEXITCODE -ne 0) {
        net user $LocalAdminUsername $LocalAdminPassword
    }

    $administratorsGroupSID = "S-1-5-32-544"
    $groupName = Convert-SIDToFriendlyName -SID $administratorsGroupSID
    net.exe localgroup $groupName $LocalAdminUsername /add
}


function ExecuteWith-Retry {
    param(
        [ScriptBlock]$Command,
        [int]$MaxRetryCount=10,
        [int]$RetryInterval=3,
        [array]$ArgumentList=@()
    )

    $currentErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true) {
        try {
            $res = Invoke-Command -ScriptBlock $Command `
                     -ArgumentList $ArgumentList
            $ErrorActionPreference = $currentErrorActionPreference
            return $res
        } catch [System.Exception] {
            $retryCount++
            if ($retryCount -gt $MaxRetryCount) {
                $ErrorActionPreference = $currentErrorActionPreference
                throw $_.Exception
            } else {
                Write-Error $_.Exception
                Start-Sleep $RetryInterval
            }
        }
    }
}

function Write-Log {
    param($message)
    Write-Host $message
    #$date = Get-Date
    #echo "$date : $message" >> "C:\logs"
}


ExecuteWith-Retry {
    ###################BEGIN###################################################
    $cloudbasePythonFolder = "C:\Program Files (x86)\Cloudbase Solutions\Cloudbase-Init\Python27"
    $username = "cloudbase-init"
    $serviceName = "cloudbase-init"
    $privilege = "SeServiceLogonRight"
    $password = Generate-StrongPassword
    # Add user for service
    Create-LocalAdmin $username $password
    Write-Log "Created local admin"
    #Add user logon as a service right
    Grant-Privilege $username $privilege
    Write-Log "Added local admin logon as a service right"

    # Hide cloudbase-init user at the logon screen
    REG ADD "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList" /f
    REG ADD "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList\\" /f /t REG_DWORD /d 0 /v $username
    Write-Log "Hide user at the logon screen"

    # Recreate pywin32
    & "$cloudbasePythonFolder\python.exe" "$cloudbasePythonFolder\Scripts\pywin32_postinstall.py" -install -silent -quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Log $error[0]
        throw $error[0]
    }
    Write-Log "Recreated pywin32"

    # Update executables
    & "$cloudbasePythonFolder\python.exe" -c "import os; import sys; from pip._vendor.distlib import scripts; specs = 'cloudbase-init = cloudbaseinit.shell:main'; scripts_path = os.path.join(os.path.dirname(sys.executable), 'Scripts'); m = scripts.ScriptMaker(None, scripts_path); m.executable = sys.executable; m.make(specs)"
    if ($LASTEXITCODE -ne 0) {
        Write-Log $error[0]
        throw $error[0]
    }
    Write-Log "Recreated pywin32"

    # set service username and password
    sc.exe config $serviceName obj= ".\$username" password= "$password"
    if ($LASTEXITCODE -ne 0) {
        Write-Log $error[0]
        throw $error[0]
    }
    Write-Log "Set service user and password"

    # wait in case of 2008r2 for all processes to finish execution
    Start-Sleep 5
    
    Restart-Service $serviceName

} -MaxRetryCount 3 -RetryInterval 10