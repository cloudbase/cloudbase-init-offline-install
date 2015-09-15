#
# Copyright 2015 Cloudbase Solutions Srl
#

# Import required PowerShell modules
import-module Microsoft.PowerShell.Management
import-module Microsoft.PowerShell.Utility

# Define variables
$cloudbaseFolder = "$Env:SystemDrive\Program Files\Cloudbase Solutions\Cloudbase-Init\"
$cloudbasePythonFolder = Join-Path $cloudbaseFolder "Python27"
$cloudbaseUnattendConf = Join-Path $cloudbaseFolder "conf\cloudbase-init-unattend.conf"
$cloudbaseExe = Join-Path $cloudbasePythonFolder "Scripts\cloudbase-init.exe"
$serviceName = "cloudbase-init"
$logFile = "$Env:SystemDrive\cloudbase-init-setup.log"
$errorLogFile = "$Env:SystemDrive\cloudbase-init-setup.error"

# Recreate pywin32
& "$cloudbasePythonFolder\python.exe" "$cloudbasePythonFolder\Scripts\pywin32_postinstall.py" -install -silent -quiet >>$logFile 2>>$errorLogFile

# Update executables
& "$cloudbasePythonFolder\python.exe" -c "import os; import sys; from pip._vendor.distlib import scripts; specs = 'cloudbase-init = cloudbaseinit.shell:main'; scripts_path = os.path.join(os.path.dirname(sys.executable), 'Scripts'); m = scripts.ScriptMaker(None, scripts_path); m.executable = sys.executable; m.make(specs)" >>$logFile 2>>$errorLogFile

# set service startup type
sc.exe config $serviceName start= "auto"

#run cloudbase-init unattend
& $cloudbaseExe --config-file $cloudbaseUnattendConf
