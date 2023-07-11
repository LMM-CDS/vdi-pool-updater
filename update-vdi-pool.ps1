. "$PSScriptRoot\config.global.ps1"
. "$PSScriptRoot\config.ps1"
. "$LibDir\Loader.ps1"

function Update-VDIPool($Logger, $VMName, $PoolName) {
    # try {
    $Retries = 1
    $CredentialVCenter = Get-StoredCredentials -Target $CREDENTIALS_TARGET_VCENTER
    $componentLogger = $Logger.GetChildLogger("VCenter-$PoolName")
    $VMDriver = [VMDriverVCenter]::new($VCENTER_SERVER, $VCENTER_PORT, $CredentialVCenter, $componentLogger)
    $VMBuildSuccess = $false

    $CredentialMECM = Get-StoredCredentials -Target $CREDENTIALS_TARGET_MECM # TODO : need to be used !

    While ($Retries -le $MAX_VM_DEPLOYMENT_RETRIES) {
        try {
            $MECMMonitor = [MECMDeviceDeploymentMonitor]::new($Logger.GetChildLogger("MECMMonitor-$PoolName"), $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $VMName)
        }
        catch {
            $Logger.Error($_)
            return
        }
        $Logger.Info("Attempt #$Retries / $MAX_VM_DEPLOYMENT_RETRIES of running OSD TS on '$VMName' :")

        $Retries = $Retries + 1
        Pushd "$($SMS_SiteCode):"
        $Logger.Info("Removing existing PXE deployments for device '$VMName'")
        Clear-CMPxeDeployment -Device (Get-CMDevice -Name $VMName)
        Popd

        $VMDriver.StartPXE($VMName, $true)

        $success = $MECMMonitor.WatchDeploymentProgress()
        if (!$success) {
            $Logger.Warning("Something went wrong. Retry (")
            # $VMDriver.StopVM($VMName)
            continue
        }

        $Logger.Info("Deployment succeedded !")
        $Logger.Info("Removing MECM Agent before taking snapshot")
        ipconfig /flushdns
        psexec -s \\$VMName c:\windows\ccmsetup\ccmsetup.exe /uninstall


        $Logger.Info("Powering off VM.")
        $VMDriver.ShutdownVM($VMName)

        $timestamp = Get-Date -Format "yyyMMddhhmmss"
        $snapshotName = "VDI-$VMName-$timestamp"
        $Logger.Info("Taking snapshot $snapshotName")
        $VMDriver.SnapshotVM($VMName, $SnapshotName)
        $VMBuildSuccess = $true
        break
    }
    if ($VMBuildSuccess -ne $true) { return $false }


    $Logger.Info("Starting VDI Pool regeneration.")
    $Logger.Info("TO BE IMPLEMENTED !")

}

function Main {
    $MainLogger = [Logger]::new("$LogDir/Main.log")
    $MainLogger.SetLogLevel($LOGLEVEL)
    $MainLogger.Info("******************************************************* Program Starts ********************************************************")

    foreach ($pool in $VDI_POOLS_AVAILABLES) {
        $timestamp = Get-Date -Format "yyyMMddhhmmss"
        $LogFile = "$LogDir/$timestamp-Pool-$($pool.Name).log"
        $Logger = [Logger]::new($LogFile)
        $Logger.SetLogLevel($LOGLEVEL)
        $MainLogger.Info("Starting Pool '$($pool.Name)' generation with VM '$($pool.VM)'")
        Update-VDIPool -Logger $Logger -PoolName $pool.Name -VMName $pool.VM
    }
    $MainLogger.Info("******************************************************* Program End ***********************************************************")
}

Main
Write-Host "Done"