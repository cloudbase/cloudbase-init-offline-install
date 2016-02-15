$ErrorActionPreference = "Stop"

$targetPath = "C:\VHDs\Nano.vhdx"
$isoPath = "C:\ISO\Windows_Server_2016_Technical_Preview_4.ISO"
$password = ConvertTo-SecureString -AsPlaintext -Force "P@ssw0rd"

if(Test-Path $targetPath)
{
    del $targetPath
}

.\NewNanoServerImage.ps1 -IsoPath $isoPath -TargetPath $targetPath `
-AdministratorPassword $password -Platform "Hyper-V" `
-Compute -Storage -Clustering `
-ExtraDriversPaths C:\Dev\VMware_Drivers `
-AddCloudbaseInit `
-MaxSize 1000MB `
-DiskLayout "BIOS"

Write-Host
Write-Host "Your OpenStack Nano Server image is ready: $targetPath"
