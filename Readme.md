# Readme

Step 1:

    Unarchive Cloudbase-Init.tar.gz

Step 2:

    Run ServiceInstall.ps1 with the required parameters. The Windows Image must be mounted before trying to run the script.
    
    The script will:
        
        install the cloudbase-init service using the registry hive
        
        Copy the cloudbase-init folders to the mounted image
        
        Copy the PostInstall.ps1 script to the mounted image
        
        Make sure you add in your Unattend.xml, section specialize, the RunSynchronousCommand with the apropriate path for PostInstall.ps1 script.

During sysprep, specialize stage, the PostInstall.ps1 will be run, creating the cloudbase-init user, setting to that user a passsword and setting the cloudbase-init service to start automatically.

The same script will also perform some house-keeping for the cloudbase-init files and executables.