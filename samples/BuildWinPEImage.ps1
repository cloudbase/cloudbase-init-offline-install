..\NewWinPEImage.ps1 -WinPEDir C:\winpe_amd64 `
-WinPEISOPath C:\ISO\WinPE_amd64.iso `
-ExtraDriversPaths @("C:\Dev\VMware_Drivers") `
-AddCloudbaseInit `
-AddVirtIODrivers `
-AdditionalContent (,('c:\Dev\R710_BIOS_4HKX2_WN64_6.4.0.EXE', "BIOS_Updates"))
