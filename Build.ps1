$ErrorActionPreference = "Stop"

$targetPath = "C:\VHDs\Nano"
$isoPath = "C:\ISO\Windows_Server_2016_Technical_Preview_3.ISO"
$password = ConvertTo-SecureString -AsPlaintext -Force "P@ssw0rd"

if(Test-Path $targetPath)
{
    del -recurse $targetPath
}

$vhdxPath = .\NewNanoServerVHD.ps1 -IsoPath $isoPath -TargetPath $targetPath -AdministratorPassword $password

$cloudbaseInitZipPath = Join-Path $pwd CloudbaseInitSetup_x64.zip
Start-BitsTransfer -Source "https://www.cloudbase.it/downloads/CloudbaseInitSetup_x64.zip" -Destination $cloudbaseInitZipPath

.\CloudbaseInitOfflineSetup.ps1 -VhdPath $vhdxPath -CloudbaseInitZipPath $cloudbaseInitZipPath

Write-Host
Write-Host "Your OpenStack Nano Server image is ready: $vhdxPath"
