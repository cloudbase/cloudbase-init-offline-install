# Readme

Building a Nano Server image for OpenStack consists in 2 main steps:

* Preparing a NanoServer VHD image
* Downloading and installing Cloudbase-Init in the offline VHD image

# NanoServer OpenStack build automation:

    $targetPath = "C:\VHDs\Nano"
    $isoPath = "C:\ISO\Windows_Server_2016_Technical_Preview_3.ISO"
    $password = ConvertTo-SecureString -AsPlaintext -Force "P@ssw0rd"

    $vhdxPath = .\NewNanoServerVHD.ps1 -IsoPath $isoPath -TargetPath $targetPath -AdministratorPassword $password

    $cloudbaseInitZipPath = Join-Path $pwd CloudbaseInitSetup_x64.zip
    Start-BitsTransfer -Source "https://www.cloudbase.it/downloads/CloudbaseInitSetup_x64.zip" -Destination $cloudbaseInitZipPath

    .\CloudbaseInitOfflineSetup.ps1 -VhdPath $vhdxPath -CloudbaseInitZipPath $cloudbaseInitZipPath
