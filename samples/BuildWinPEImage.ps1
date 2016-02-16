..\NewWinPEImage.ps1 -WinPEDir C:\winpe_amd64 `
-WinPEISOPath C:\ISO\WinPE_amd64.iso `
-ExtraDriversPaths @("C:\Dev\VMware_Drivers") `
-AddCloudbaseInit `
-AddVirtIODrivers
