# [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.ConfigurationManagement.ManagementProvider') | Out-Null
# [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine')| Out-Null
# if((Get-Module ConfigurationManager) -eq $null) {
#     Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
# }
. "$PSScriptRoot/Class.Logger.ps1"
class MECMDeviceDeploymentMonitor {
    [Logger] $Logger
    [string]$SMS_Server
    [string]$SMS_SiteCode
    [DateTime] $CacheLastRenewed
    [string] $TaskSequenceName
    [string] $DeviceName
    [array] $_CachedDeployments = @()
    [int] $CurrentStep
    [System.Int32] static $WaitSecondsBetweenStepChange = 10
    [int32] static $MaxSteps = 400
    [int] $DeviceResourceId
    [string] $TSPackageId
    [string] $StartMarker

    MECMDeviceDeploymentMonitor([Logger]$Logger, [string]$SMS_Server, [string]$SMS_SiteCode, [string]$TaskSequenceName, [string]$DeviceName) {
        $this.Logger = $Logger
        $this.Logger.Debug("MECMDeviceDeploymentMonitor instance created")
        $this.Logger.Debug("$SMS_Server, $SMS_SiteCode, $TaskSequenceName, $DeviceName")
        $this.SMS_Server = $SMS_Server
        $this.SMS_SiteCode = $SMS_SiteCode
        $this.DeviceName = $DeviceName
        $this.TaskSequenceName = $TaskSequenceName
        $this.CurrentStep = 0
        $query = "SELECT PackageID FROM SMS_TaskSequencePackage WHERE Name='$TaskSequenceName'"
        $this.Logger.Debug("TSPackageId query = $query")
        $this.TSPackageId = Get-WmiObject -ComputerName $SMS_Server -Namespace "Root\SMS\site_$($SMS_SiteCode)" -Query $query | Select -ExpandProperty PackageID
        $this.Logger.Debug("TSPackageId = $($this.TSPackageId)")

        $query = "SELECT ResourceId FROM SMS_R_System WHERE Name='$DeviceName'"
        $this.Logger.Debug("DeviceResourceId query = $query")
        $this.DeviceResourceId = Get-WmiObject -ComputerName $SMS_Server -Namespace "Root\SMS\site_$($SMS_SiteCode)" -Query $query | Select -ExpandProperty ResourceId
        $this.Logger.Debug("DeviceResourceId = $($this.DeviceResourceId)")
        $this.CacheLastRenewed = (get-date).AddMinutes(-10)
    }

    [string]_GetTimestamp() {
        return Get-Date -Format "yyyMMddhhmmss"
    }

    [array]getDeploymentSteps() {
        $this.Logger.Debug("getDeploymentSteps()")

        $ts = Get-Date
        $lastRenew = (New-TimeSpan -Start $this.CacheLastRenewed -End $ts).TotalSeconds
        # $this.Logger.Debug("lastRenew = $lastRenew")
        if ($lastRenew -ge 10 ) {
            $this._updateCachedDeployments()
        }
        return $this._CachedDeployments  `
        | Select @{N = "Date"; E = { Get-Date -Date ([DateTime]::ParseExact(($_.ExecutionTime -split '\+')[0], "yyyyMMddHHmmss.ffffff", $null)) -Format "yyyy/MM/dd HH:mm:ss" } }, * `
        | Select Step, LastStatusMsgName, ActionName, ActionOutput, Date -First ([MECMDeviceDeploymentMonitor]::MaxSteps) `
        | Sort-Object Date, Step
    }

    <#
        Wait until either Success or Failure action is reached
        Thoses actions names are defined within global.config.ps1
        return $true if the deployment has reached success step
        return $false if the deployment has reached falure step or timeout is reached
    #>
    [boolean] WatchDeploymentProgress() {
        $this.Logger.Info("Waiting 10 minutes for initial communication")
        $this.Logger.Verbose("Waiting for Step 1 of Task sequence")
        $stepReachedBeforeTimeout = $this.getStepWhenAvailable(1, 10 * 60)
        if (!$stepReachedBeforeTimeout) {
            $this.Logger.Warning("The step 1 hasn't been reached after 10 minutes")
            return $false
        }
        else {
            $this.Logger.Info("Step 1 reached : the TS started successfully")
        }

        $this.Logger.Info("Waiting until one of the success or failure action occurs")
        $this.Logger.Verbose("- Success Action Name : $Global:SMS_TS_SUCCESS_ActionName")
        $this.Logger.Verbose("- Failure Action Name : $Global:SMS_TS_FAILURE_ActionName")

        $timeoutDelay = 60 * $Global:SMS_TS_EXECUTION_MAX_EXECUTION_MINUTES
        $stepReachedBeforeTimeout = $this.getStepWhenAvailableFromActionNames(@($Global:SMS_TS_SUCCESS_ActionName, $Global:SMS_TS_FAILURE_ActionName), $timeoutDelay)

        if (!$stepReachedBeforeTimeout) {
            $this.Logger.Error("$timeoutDelay maximum delay has been reached")
            $this.Logger.Error("Something went wrong.")
            return $false
        }
        if ($stepReachedBeforeTimeout.ActionName -eq $Global:SMS_TS_FAILURE_ActionName) {
            $this.Logger.Error("Failure action name has been reached")
            $this.Logger.Debug("Retrieved step value :")
            $this.Logger.Debug("$($stepReachedBeforeTimeout|ConvertTo-Json)")
            return $false
        }

        $this.Logger.Info("TS Deployment was successful on machine '$($this.DeviceName)'")
        $this.Logger.Debug("Retrieved step value :")

        $this.Logger.Debug("$($stepReachedBeforeTimeout|ConvertTo-Json)")
        return $true
    }

    <# Save last SMS_TaskSequenceExecutionStatus result date, to detect only newer events #>
    [void]_SetStartMarker() {
        $query = "SELECT * FROM SMS_TaskSequenceExecutionStatus ORDER BY ExecutionTime Desc"
        $this.Logger.Debug("executing WMI query : $query")
        $this.StartMarker = Get-WmiObject -ComputerName $this.SMS_Server -Namespace "Root\SMS\site_$($this.SMS_SiteCode)"  -Query $query  | Select -First 1 -ExpandProperty ExecutionTime

        $this.Logger.Verbose("Start Marker set to : $($this.StartMarker)")

    }

    <# Retrieve deployment information related to TSPackageId and DeviceResourceId. Only list events more recent than StartMarker#>
    [void]_updateCachedDeployments() {
        $query = "SELECT * FROM SMS_TaskSequenceExecutionStatus WHERE ExecutionTime>'$($this.StartMarker)' AND PackageID='$($this.TSPackageId)' AND ResourceID='$($this.DeviceResourceId)' AND Step >= $($this.CurrentStep) ORDER BY ExecutionTime Desc"
        $this.Logger.Debug("executing WMI query : $query")
        $this._CachedDeployments = Get-WmiObject -ComputerName $this.SMS_Server -Namespace "Root\SMS\site_$($this.SMS_SiteCode)"  `
            -Query $query
        $this.CacheLastRenewed = Get-Date
    }

    [object]getCurrentStep() {
        return $this.getDeploymentSteps() | ? { $_.Step -eq $this.CurrentStep } | Select -Last 1 # sometimes there are multiple time the same step in the db (at different dates)
    }



    # [object]getStepWhenAvailable($stepNumber){
    #     return $this.waitUntilStep($stepNumber,60*60*24*15)
    # }

    [object]getStepWhenAvailable($stepNumber, $maxWaitSeconds) {
        $this._SetStartMarker()
        $this.Logger.Debug("getStepWhenAvailable($stepNumber,$maxWaitSeconds)")
        $noTimeout = $this.waitUntilStep($stepNumber, $maxWaitSeconds)
        if ($noTimeout) {
            $this.Logger.Debug("timeout was not reached")
            return $this.getCurrentStep()
        }
        else {
            $this.Logger.Warning("timeout was reached")
            return $null
        }
    }


    [object]getStepNumberWhenAvailable($stepNumber, $maxWaitSeconds) {
        $this.Logger.Debug("getStepNumberWhenAvailable($stepNumber,$maxWaitSeconds)")
        $noTimeout = $this.waitUntilStep($stepNumber, $maxWaitSeconds)
        if ($noTimeout) {
            return $this.getCurrentStep()
        }
        else {
            return $null
        }
    }


    # [bool]waitForNextStep(){
    #     return $this.waitForNextStep(60*60*24*15)

    # }

    [bool]waitForNextStep($maxWaitSeconds) {
        $this.Logger.Debug("waitForNextStep($maxWaitSeconds)")
        $startTime = Get-Date
        $waitDuration = 0
        While ($waitDuration -lt $maxWaitSeconds) {
            # Write-Host "Waiting for step $($this.CurrentStep + 1)  - Remaining waiting time : $($maxWaitSeconds - $waitDuration)"
            $this.Logger.Debug("trying to get next step (CurrentStep=$($this.CurrentStep)")
            $nextStep = $this.getDeploymentSteps() | Select -ExpandProperty Step | ? { $_ -gt $this.CurrentStep } | Sort-Object | Select -First 1
            if ($nextStep) {
                $this.Logger.Debug("nextStep = $nextStep")
                $this.CurrentStep = $nextStep
                return $true
            }
            else {
                $this.Logger.Debug("waiting 10 seconds")
                Start-Sleep -Seconds 10
            }
            $ts = Get-Date
            $waitDuration = (New-TimeSpan -Start $startTime -End $ts).TotalSeconds
            $this.Logger.Debug("waitDuration = $waitDuration    maxWaitSeconds = $maxWaitSeconds")
        }
        $this.Logger.Warning("Timeout reached waitDuration ($waitDuration) > maxWaitSeconds ($maxWaitSeconds)")
        return $false
    }

    # [bool]waitUntilStep($stepNumber){
    #     return $this.waitUntilStep($stepNumber,60*60*24*15)
    # }
    [object]getStepWhenAvailableFromActionName([string]$actionName, [int]$maxWaitSeconds) {
        return $this.getStepWhenAvailableFromActionNames(@($actionName), $maxWaitSeconds)
    }
    [object]getStepWhenAvailableFromActionNames([array]$actionNames, [int]$maxWaitSeconds) {
        # wait (until timeout) for a step object that has one the expected actionNames
        # return $null if timeout
        # return the step object if reached
        $this.Logger.Debug("getStepWhenAvailableFromActionName($actionNames, $maxWaitSeconds)")
        $startTime = Get-Date
        $elapsedTime = 0
        while ($elapsedTime -le $maxWaitSeconds) {
            $elapsedTime = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
            $remainingTime = $maxWaitSeconds - $elapsedTime
            $this.Logger.Debug("elapsetTime = $elapsedTime    remainingTime = $remainingTime")
            $res = $this.getNextStepWhenAvailable($remainingTime)
            if ($res -eq $null) {
                $this.Logger.Debug("Next step was not available (timeout)")
                break
            } # timeout
            if ($actionNames -contains $res.ActionName) {
                $this.Logger.Debug("action $($res.ActionName) found")
                return $res
            }
            $hide = $false
            $type = ""
            switch ($res.LastStatusMsgName) {
                { $_ -like "*a group*" } { $hide = $true }
                { $_ -like "*disabled*" } { $type = "SKIP (Disabled)" }
                { $_ -like "*skipped*" } { $type = "SKIP" }
                { $_ -like "*successfully completed an action*" } { $type = "ACTION - SUCCESS" }
                { $_ -like "*failed executing an action*" } { $type = "ACTION - FAILURE" }
                # Default {  }
            }
            if (!$hide) {$this.Logger.Verbose(" Step $("$($res.Step)".PadLeft(3)) : $("$($type)".PadRight(20)) - $($res.ActionName)")}
        }
        return $null
    }

    [object]getNextStepWhenAvailable($maxWaitSeconds) {
        $noTimeout = $this.waitForNextStep($maxWaitSeconds)
        if ($noTimeout) {
            return $this.getCurrentStep()
        }
        else {
            return $null
        }
    }

    [bool]waitUntilStep($stepNumber, $maxWaitSeconds) {
        $startTime = Get-Date
        $elapsedTime = 0
        while ($this.CurrentStep -lt $stepNumber) {
            $elapsedTime = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
            if ($elapsedTime -gt $maxWaitSeconds) { break }
            $this.waitForNextStep($maxWaitSeconds - $elapsedTime)
        }
        return ($elapsedTime -lt $maxWaitSeconds)
    }
}