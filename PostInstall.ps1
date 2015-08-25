#
# Copyright 2014-2015 Cloudbase Solutions Srl
#
$ErrorActionPreference = "Stop"

$SourcePolicy = @"
/*
Original sources available at: https://bitbucket.org/splatteredbits/carbon
*/

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

namespace PSCarbon
{
    public sealed class Lsa
    {
        // ReSharper disable InconsistentNaming
        [StructLayout(LayoutKind.Sequential)]
        internal struct LSA_UNICODE_STRING
        {
            internal LSA_UNICODE_STRING(string inputString)
            {
                if (inputString == null)
                {
                    Buffer = IntPtr.Zero;
                    Length = 0;
                    MaximumLength = 0;
                }
                else
                {
                    Buffer = Marshal.StringToHGlobalAuto(inputString);
                    Length = (ushort)(inputString.Length * UnicodeEncoding.CharSize);
                    MaximumLength = (ushort)((inputString.Length + 1) * UnicodeEncoding.CharSize);
                }
            }

            internal ushort Length;
            internal ushort MaximumLength;
            internal IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct LSA_OBJECT_ATTRIBUTES
        {
            internal uint Length;
            internal IntPtr RootDirectory;
            internal LSA_UNICODE_STRING ObjectName;
            internal uint Attributes;
            internal IntPtr SecurityDescriptor;
            internal IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        // ReSharper disable UnusedMember.Local
        private const uint POLICY_VIEW_LOCAL_INFORMATION = 0x00000001;
        private const uint POLICY_VIEW_AUDIT_INFORMATION = 0x00000002;
        private const uint POLICY_GET_PRIVATE_INFORMATION = 0x00000004;
        private const uint POLICY_TRUST_ADMIN = 0x00000008;
        private const uint POLICY_CREATE_ACCOUNT = 0x00000010;
        private const uint POLICY_CREATE_SECRET = 0x00000014;
        private const uint POLICY_CREATE_PRIVILEGE = 0x00000040;
        private const uint POLICY_SET_DEFAULT_QUOTA_LIMITS = 0x00000080;
        private const uint POLICY_SET_AUDIT_REQUIREMENTS = 0x00000100;
        private const uint POLICY_AUDIT_LOG_ADMIN = 0x00000200;
        private const uint POLICY_SERVER_ADMIN = 0x00000400;
        private const uint POLICY_LOOKUP_NAMES = 0x00000800;
        private const uint POLICY_NOTIFICATION = 0x00001000;
        // ReSharper restore UnusedMember.Local

        [DllImport("advapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern bool LookupPrivilegeValue(
            [MarshalAs(UnmanagedType.LPTStr)] string lpSystemName,
            [MarshalAs(UnmanagedType.LPTStr)] string lpName,
            out LUID lpLuid);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        private static extern uint LsaAddAccountRights(
            IntPtr PolicyHandle,
            IntPtr AccountSid,
            LSA_UNICODE_STRING[] UserRights,
            uint CountOfRights);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
        private static extern uint LsaClose(IntPtr ObjectHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaEnumerateAccountRights(IntPtr PolicyHandle,
            IntPtr AccountSid,
            out IntPtr UserRights,
            out uint CountOfRights
            );

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaFreeMemory(IntPtr pBuffer);

        [DllImport("advapi32.dll")]
        private static extern int LsaNtStatusToWinError(long status);

        [DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
        private static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, uint DesiredAccess, out IntPtr PolicyHandle );

        [DllImport("advapi32.dll", SetLastError = true, PreserveSig = true)]
        static extern uint LsaRemoveAccountRights(
            IntPtr PolicyHandle,
            IntPtr AccountSid,
            [MarshalAs(UnmanagedType.U1)]
            bool AllRights,
            LSA_UNICODE_STRING[] UserRights,
            uint CountOfRights);
        // ReSharper restore InconsistentNaming

        private static IntPtr GetIdentitySid(string identity)
        {
            var sid =
                new NTAccount(identity).Translate(typeof (SecurityIdentifier)) as SecurityIdentifier;
            if (sid == null)
            {
                throw new ArgumentException(string.Format("Account {0} not found.", identity));
            }
            var sidBytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(sidBytes, 0);
            var sidPtr = Marshal.AllocHGlobal(sidBytes.Length);
            Marshal.Copy(sidBytes, 0, sidPtr, sidBytes.Length);
            return sidPtr;
        }

        private static IntPtr GetLsaPolicyHandle()
        {
            var computerName = Environment.MachineName;
            IntPtr hPolicy;
            var objectAttributes = new LSA_OBJECT_ATTRIBUTES
            {
                Length = 0,
                RootDirectory = IntPtr.Zero,
                Attributes = 0,
                SecurityDescriptor = IntPtr.Zero,
                SecurityQualityOfService = IntPtr.Zero
            };

            const uint ACCESS_MASK = POLICY_CREATE_SECRET | POLICY_LOOKUP_NAMES | POLICY_VIEW_LOCAL_INFORMATION;
            var machineNameLsa = new LSA_UNICODE_STRING(computerName);
            var result = LsaOpenPolicy(ref machineNameLsa, ref objectAttributes, ACCESS_MASK, out hPolicy);
            HandleLsaResult(result);
            return hPolicy;
        }

        public static string[] GetPrivileges(string identity)
        {
            var sidPtr = GetIdentitySid(identity);
            var hPolicy = GetLsaPolicyHandle();
            var rightsPtr = IntPtr.Zero;

            try
            {

                var privileges = new List<string>();

                uint rightsCount;
                var result = LsaEnumerateAccountRights(hPolicy, sidPtr, out rightsPtr, out rightsCount);
                var win32ErrorCode = LsaNtStatusToWinError(result);
                // the user has no privileges
                if( win32ErrorCode == STATUS_OBJECT_NAME_NOT_FOUND )
                {
                    return new string[0];
                }
                HandleLsaResult(result);

                var myLsaus = new LSA_UNICODE_STRING();
                for (ulong i = 0; i < rightsCount; i++)
                {
                    var itemAddr = new IntPtr(rightsPtr.ToInt64() + (long) (i*(ulong) Marshal.SizeOf(myLsaus)));
                    myLsaus = (LSA_UNICODE_STRING) Marshal.PtrToStructure(itemAddr, myLsaus.GetType());
                    var cvt = new char[myLsaus.Length/UnicodeEncoding.CharSize];
                    Marshal.Copy(myLsaus.Buffer, cvt, 0, myLsaus.Length/UnicodeEncoding.CharSize);
                    var thisRight = new string(cvt);
                    privileges.Add(thisRight);
                }
                return privileges.ToArray();
            }
            finally
            {
                Marshal.FreeHGlobal(sidPtr);
                var result = LsaClose(hPolicy);
                HandleLsaResult(result);
                result = LsaFreeMemory(rightsPtr);
                HandleLsaResult(result);
            }
        }

        public static void GrantPrivileges(string identity, string[] privileges)
        {
            var sidPtr = GetIdentitySid(identity);
            var hPolicy = GetLsaPolicyHandle();

            try
            {
                var lsaPrivileges = StringsToLsaStrings(privileges);
                var result = LsaAddAccountRights(hPolicy, sidPtr, lsaPrivileges, (uint)lsaPrivileges.Length);
                HandleLsaResult(result);
            }
            finally
            {
                Marshal.FreeHGlobal(sidPtr);
                var result = LsaClose(hPolicy);
                HandleLsaResult(result);
            }
        }

        const int STATUS_SUCCESS = 0x0;
        const int STATUS_OBJECT_NAME_NOT_FOUND = 0x00000002;
        const int STATUS_ACCESS_DENIED = 0x00000005;
        const int STATUS_INVALID_HANDLE = 0x00000006;
        const int STATUS_UNSUCCESSFUL = 0x0000001F;
        const int STATUS_INVALID_PARAMETER = 0x00000057;
        const int STATUS_NO_SUCH_PRIVILEGE = 0x00000521;
        const int STATUS_INVALID_SERVER_STATE = 0x00000548;
        const int STATUS_INTERNAL_DB_ERROR = 0x00000567;
        const int STATUS_INSUFFICIENT_RESOURCES = 0x000005AA;

        private static readonly Dictionary<int, string> ErrorMessages = new Dictionary<int, string>
                                    {
                                        {STATUS_OBJECT_NAME_NOT_FOUND, "Object name not found. An object in the LSA policy database was not found. The object may have been specified either by SID or by name, depending on its type."},
                                        {STATUS_ACCESS_DENIED, "Access denied. Caller does not have the appropriate access to complete the operation."},
                                        {STATUS_INVALID_HANDLE, "Invalid handle. Indicates an object or RPC handle is not valid in the context used."},
                                        {STATUS_UNSUCCESSFUL, "Unsuccessful. Generic failure, such as RPC connection failure."},
                                        {STATUS_INVALID_PARAMETER, "Invalid parameter. One of the parameters is not valid."},
                                        {STATUS_NO_SUCH_PRIVILEGE, "No such privilege. Indicates a specified privilege does not exist."},
                                        {STATUS_INVALID_SERVER_STATE, "Invalid server state. Indicates the LSA server is currently disabled."},
                                        {STATUS_INTERNAL_DB_ERROR, "Internal database error. The LSA database contains an internal inconsistency."},
                                        {STATUS_INSUFFICIENT_RESOURCES, "Insufficient resources. There are not enough system resources (such as memory to allocate buffers) to complete the call."}
                                    };

        private static void HandleLsaResult(uint returnCode)
        {
            var win32ErrorCode = LsaNtStatusToWinError(returnCode);

            if( win32ErrorCode == STATUS_SUCCESS)
                return;

            if( ErrorMessages.ContainsKey(win32ErrorCode) )
            {
                throw new Win32Exception(win32ErrorCode, ErrorMessages[win32ErrorCode]);
            }

            throw new Win32Exception(win32ErrorCode);
        }

        public static void RevokePrivileges(string identity, string[] privileges)
        {
            var sidPtr = GetIdentitySid(identity);
            var hPolicy = GetLsaPolicyHandle();

            try
            {
                var currentPrivileges = GetPrivileges(identity);
                if (currentPrivileges.Length == 0)
                {
                    return;
                }
                var lsaPrivileges = StringsToLsaStrings(privileges);
                var result = LsaRemoveAccountRights(hPolicy, sidPtr, false, lsaPrivileges, (uint)lsaPrivileges.Length);
                HandleLsaResult(result);
            }
            finally
            {
                Marshal.FreeHGlobal(sidPtr);
                var result = LsaClose(hPolicy);
                HandleLsaResult(result);
            }

        }

        private static LSA_UNICODE_STRING[] StringsToLsaStrings(string[] privileges)
        {
            var lsaPrivileges = new LSA_UNICODE_STRING[privileges.Length];
            for (var idx = 0; idx < privileges.Length; ++idx)
            {
                lsaPrivileges[idx] = new LSA_UNICODE_STRING(privileges[idx]);
            }
            return lsaPrivileges;
        }
    }
}
"@
Add-Type -TypeDefinition $SourcePolicy -Language CSharp

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

function Check-Membership {
    Param (
        [Parameter(Mandatory=$true)]
        [string]$User,
        [Parameter(Mandatory=$true)]
        [string]$GroupSID
    )

    $group = Get-CimInstance -ClassName Win32_Group  `
                -Filter "SID = '$GroupSID'"
    $ret = Get-CimAssociatedInstance -InputObject $group `
          -ResultClassName Win32_UserAccount | Where-Object `
                                               { $_.Name -eq $User }
    return $ret
}

function Create-LocalAdmin {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalAdminUsername,
        [Parameter(Mandatory=$true)]
        [string]$LocalAdminPassword
    )

    Add-WindowsUser $LocalAdminUsername $LocalAdminPassword

    $administratorsGroupSID = "S-1-5-32-544"
    $isLocalAdmin = Check-Membership $LocalAdminUsername $administratorsGroupSID
    $groupName = Convert-SIDToFriendlyName -SID $administratorsGroupSID
    if (!$isLocalAdmin) {
        net.exe localgroup $groupName $LocalAdminUsername /add
    }

}

function Get-WindowsUser {
    Param(
        [parameter(Mandatory=$true)]
        [string]$Username
    )

    $existentUser = Get-WmiObject -Class "Win32_Account" `
                                  -Filter "Name = '$Username'"
    return $existentUser
}

function Add-WindowsUser {
    param(
        [parameter(Mandatory=$true)]
        [string]$Username,
        [parameter(Mandatory=$true)]
        [string]$Password
    )

    $existentUser = Get-WindowsUser $Username
    if ($existentUser -eq $null) {
        $computer = [ADSI]"WinNT://$env:computername"
        $user = $computer.Create("User", $Username)
        $user.SetPassword($Password)
        $user.SetInfo()
        $user.FullName = $Username
        $user.SetInfo()
        # UserFlags = Logon script | Normal user | No pass expiration
        $user.UserFlags = 1 + 512 + 65536
        $user.SetInfo()
    } else {
        $computername = hostname.exe
        $user = [ADSI] "WinNT://$computerName/$Username,User"
        $user.SetPassword($Password)
    }
}

###################BEGIN###################################################
$cloudbasePythonFolder = "C:\Program Files (x86)\Cloudbase Solutions\Cloudbase-Init\Python27"
$username = "cloudbase-init"
$serviceName = "cloudbase-init"
$privilege = "SeServiceLogonRight"
$password = Generate-StrongPassword

# Add user for service
Create-LocalAdmin $username $password

#Add user logon as a service right
if (![PSCarbon.Lsa]::GetPrivileges($Username).Contains($privilege)) {
    [PSCarbon.Lsa]::GrantPrivileges($UserName, $privilege)
}

# Recreate pywin32
& "$cloudbasePythonFolder\python.exe" "$cloudbasePythonFolder\Scripts\pywin32_postinstall.py" -install -silent -quiet
if ($LASTEXITCODE -ne 0) {
    throw $error[0]
}

# Update executables
& "$cloudbasePythonFolder\python.exe" -c "import os; import sys; from pip._vendor.distlib import scripts; specs = 'cloudbase-init = cloudbaseinit.shell:main'; scripts_path = os.path.join(os.path.dirname(sys.executable), 'Scripts'); m = scripts.ScriptMaker(None, scripts_path); m.executable = sys.executable; m.make(specs)"
if ($LASTEXITCODE -ne 0) {
    throw $error[0]
}

# set service username and password
sc.exe config $serviceName obj=".\$username" password="$password"
if ($LASTEXITCODE -ne 0) {
    throw $error[0]
}

# set service startup type
sc.exe config $serviceName start="auto"
if ($LASTEXITCODE -ne 0) {
    throw $error[0]
}