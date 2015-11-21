# Readme

Building a Nano Server image for OpenStack consists in 2 main steps:

* Preparing a NanoServer VHD image
* Downloading and installing Cloudbase-Init in the offline VHD image

#### NanoServer OpenStack build automation

A full example is available in _Build.ps1_.

    $targetPath = "C:\VHDs\Nano.vhdx"
    $isoPath = "C:\ISO\Windows_Server_2016_Technical_Preview_4.ISO"
    $password = ConvertTo-SecureString -AsPlaintext -Force "P@ssw0rd"

    .\NewNanoServerVHD.ps1 -IsoPath $isoPath -TargetPath $targetPath -AdministratorPassword $password

    $cloudbaseInitZipPath = Join-Path $pwd CloudbaseInitSetup_x64.zip
    Start-BitsTransfer -Source "https://www.cloudbase.it/downloads/CloudbaseInitSetup_x64.zip" -Destination $cloudbaseInitZipPath

    .\CloudbaseInitOfflineSetup.ps1 -VhdPath $targetPath -CloudbaseInitZipPath $cloudbaseInitZipPath

The resulting _nano.vhdx_ file is now ready to be uploaded in Glance:

    glance image-create --property hypervisor_type=hyperv --name "Nano Server" ` 
    --container-format bare --disk-format vhd --file $targetPath
