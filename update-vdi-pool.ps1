. "$PSScriptRoot\config.global.ps1"
. "$PSScriptRoot\config.ps1"
. "$LibDir\Loader.ps1"

function Update-VDIPool($Logger, $VMName, $PoolName) {
    # try {
    $Retries =
    $CredentialVCenter = Get-StoredCredentials -Target $CREDENTIALS_TARGET_VCENTER
    $componentLogger = $Logger.GetChildLogger("VCenter-$PoolName")
    $VMDriver = [VMDriverVCenter]::new($VCENTER_SERVER, $VCENTER_PORT, $CredentialVCenter, $componentLogger)


    $CredentialMECM = Get-StoredCredentials -Target $CREDENTIALS_TARGET_MECM # TODO : need to be used !
    try {
        $MECMMonitor = [MECMDeviceDeploymentMonitor]::new($Logger.GetChildLogger("MECMMonitor-$PoolName"), $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $VMName)
    }
    catch {
        $Logger.Error($_)
        return
    }

    While ($Retries -le $MAX_VM_DEPLOYMENT_RETRIES) {
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

        $Logger.Info("Deployment succeedded ! Preparing snapshot.")

        $VMDriver.ShutdownVM($VMName)

        $timestamp = Get-Date -Format "yyyMMddhhmmss"
        $snapshotName = "VDI-$VMName-$timestamp"
        $VMDriver.SnapshotVM($VMName, $SnapshotName)
        break
    }
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