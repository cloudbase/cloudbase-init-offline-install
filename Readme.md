# Readme

Step 1:

    Unarchive CloudbaseInit.zip

Step 2:

    Add in your Unattend.xml, section specialize
      <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" processorArchitecture="amd64" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <RunSynchronous>
            <RunSynchronousCommand wcm:action="add">
              <Order>1</Order>
              <Path>cmd /c "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy RemoteSigned -File C:\UnattendResources\Postinstall.ps1"</Path>
              <Description>pywin postinstall script1</Description>
            </RunSynchronousCommand>
          </RunSynchronous>
        </component>
      </settings>

Step 3:

    Run ServiceInstall.ps1 with the required parameters. The Windows Image must be mounted before trying to run the script.
    
    Example: & .\ServiceInstall.ps1 -MountFolder "E:" -CloudbaseInitFilesDir ".\Cloudbase Solutions" -PostInstallPath  ".\PostInstall.ps1"

    The script will:
        
        install the cloudbase-init service using the registry hive
        
        Copy the cloudbase-init folders to the mounted image
        
        Copy the PostInstall.ps1 script to the mounted image
        
        Make sure you add in your Unattend.xml, section specialize, the RunSynchronousCommand with the apropriate path for PostInstall.ps1 script.

During sysprep, specialize stage, the PostInstall.ps1 will be run, creating the cloudbase-init user, setting to that user a passsword and setting the cloudbase-init service to start automatically.

The same script will also perform some house-keeping for the cloudbase-init files and executables.