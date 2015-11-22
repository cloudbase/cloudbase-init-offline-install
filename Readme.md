# Readme

Building a Nano Server image for OpenStack consists in 2 main steps:

* Preparing a NanoServer image
* Downloading and installing Cloudbase-Init in the offline VHD image

All you need to do is to run NewNanoServerImage.ps1 to generate a
complete image.

#### NanoServer OpenStack build automation

A full example is available in _Build.ps1_.

    $targetPath = "C:\VHDs\Nano.vhdx"
    $isoPath = "C:\ISO\Windows_Server_2016_Technical_Preview_4.ISO"
    $password = ConvertTo-SecureString -AsPlaintext -Force "P@ssw0rd"

    .\NewNanoServerImage.ps1 -IsoPath $isoPath -TargetPath $targetPath -AdministratorPassword $password

The resulting _nano.vhdx_ file is now ready to be uploaded in Glance:

    glance image-create --property hypervisor_type=hyperv --name "Nano Server" `
    --container-format bare --disk-format vhd --file $targetPath
