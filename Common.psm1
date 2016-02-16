$ErrorActionPreference = "Stop"

Import-Module "${PSScriptRoot}\FastWebRequest.psm1"

function DownloadVirtIODriversISO($baseDir)
{
    $virtIOIsoPath = Join-Path $baseDir "virtio-win.iso"
    if(Test-Path $virtIOIsoPath)
    {
        del $virtIOIsoPath
    }
    $virtioIsoUrl = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"
    Invoke-FastWebRequest -Uri $virtIOIsoUrl -OutFile $virtIOIsoPath
    return $virtIOIsoPath
}

function MountISO($isoPath)
{
    $driveLetter = (Mount-DiskImage $isoPath -StorageType ISO -PassThru | Get-Volume).DriveLetter
    # Refresh drives
    Get-PSDrive | Out-Null
    return "{0}:" -f $driveLetter
}

function GetVirtIODriverPaths($driversBasePath, $arch)
{
    $drivers = @("Balloon", "NetKVM", "qxldod", "pvpanic", "viorng", "vioscsi", "vioserial", "viostor")
    $driverPaths = @()
    foreach ($driver in $drivers)
    {
        $virtioDir = "${driversBasePath}\${driver}\w10\${arch}"
        if (Test-Path $virtioDir)
        {
            $driverPaths += $virtioDir
        }
        else
        {
            Write-Warning ("Path not found: {0}" -f $virtioDir)
        }
    }

    return $driverPaths
}

function DownloadCloudbaseInit($baseDir, $arch)
{
    $archMap = @{"amd64"="x64"; "x86"="x86"}

    $cloudbaseInitUri = "https://www.cloudbase.it/downloads/CloudbaseInitSetup_{0}.zip" -f $archMap[$arch]
    $zipPath = Join-Path $baseDir "CloudbaseInit.zip"

    if(Test-Path $zipPath)
    {
        del $zipPath
    }

    Invoke-FastWebRequest -Uri $cloudbaseInitUri -OutFile $zipPath
    return $zipPath
}

function SetADKVars($ADKRoot)
{
    if(!(Test-Path $ADKRoot))
    {
        throw "Cannot find ADK root path: ${ADKRoot}"
    }

    pushd "${ADKRoot}\Deployment Tools"
    try
    {
        cmd /c "DandISetEnv.bat&set" |
        foreach {
          if ($_ -match "=") {
            $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
          }
        }
    }
    finally
    {
        popd
    }
}

Export-ModuleMember -function *
