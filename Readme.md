# Readme

Step 1:

    Unarchive CloudbaseInit.zip

Step 2:

    Run ServiceInstall.ps1 with the required parameters. The Windows Image must be mounted before trying to run the script.
    
    Example: & .\ServiceInstall.ps1 -MountFolder "E:" -CloudbaseInitFilesDir ".\Cloudbase Solutions" -PostInstallPath  ".\PostInstall.ps1" -SetupCompletePath ".\SetupComplete.cmd" -UnattendXmlPath ".\Unattend.xml"

    The script will:
        
        install the cloudbase-init service using the registry hive
        
        Copy the cloudbase-init folders to the mounted image
        
        Copy the PostInstall.ps1 script to the mounted image
        
        Copy the Unattend.xml to the mounted image.

        Copy the SetupComplete.cmd script to the mounted image, to \Windows\Setup\Scripts\SetupComplete.cmd

At the last sysprep stage, the SetupComplete.cmd will run, executing the PostInstall.ps1 script.

https://technet.microsoft.com/en-us/library/cc766314(v=ws.10).aspx