BeforeAll {
    . "$PSScriptRoot/../config.global.ps1"
    . "$ProjectRoot/config.test.ps1"


    . "$LibDir/Class.Logger.ps1"
    . "$LibDir/Class.MECMDeviceDeploymentMonitor.ps1"

    Remove-Item $LogDir -Filter '*.*' -Recurse -Force -ErrorAction SilentlyContinue
	New-Item $LogDir -ItemType Directory | Out-Null

    $TEST_VM_NAME = "Master-test-g"
    $TEST_VM_NAME = "VM-PDT-26"

    $TS_DETECTION_ACTION_FAILURE = "Affichage du debugger"
    $TS_DETECTION_ACTION_SUCCESS = "TS Finished Successfully"

    # $TestDataDeploymentFail = Get-Content "$TestDataPath/FAIL_LMM00731_16781473_201_49.json" | Out-String  | ConvertFrom-Json
    $TestDataDeploymentSuccess = Import-Clixml "$TestDataPath/SUCCESS_LMM00731_16781473_201_327.xml"
    Mock Get-WmiObject { }
    $logger = [Logger]::new($TestLogFile, $false)
}

# Describe "Basic test" {
#     It "simple test" {
#         $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
#         Write-Host "wait"
#     }

# }

Describe "getDeploymentSteps" {
    BeforeEach{
        $script:result = @{CallCount = 0}

        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        Mock Get-WmiObject { $script:result.CallCount = $script:result.CallCount +1 }
    }
    It "Retrieve fresh data if no data are cached"{
        $script:result.CallCount | Should -Be 0
        $mon.GetDeploymentSteps()
        $script:result.CallCount | Should -Be 1
    }
    It "Retrieve fresh data if data is cached for more than 10 seconds"{
        $script:result.CallCount | Should -Be 0
        $mon.GetDeploymentSteps()
        $script:result.CallCount | Should -Be 1
        $mon.CacheLastRenewed = (Get-Date).AddSeconds(-10)
        $mon.GetDeploymentSteps()
        $script:result.CallCount | Should -Be 2
    }
    It "Retrieve data from cache if cached has been updated less than 10 seconds"{
        $script:result.CallCount | Should -Be 0
        $mon.GetDeploymentSteps()
        $script:result.CallCount | Should -Be 1
        $mon.GetDeploymentSteps()
        $script:result.CallCount | Should -Be 1

        $mon.CacheLastRenewed = (Get-Date).AddSeconds(-9)
        $mon.GetDeploymentSteps()
        $script:result.CallCount | Should -Be 1
    }
}

Describe "getCurrentStep" {
    BeforeEach{
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
    }
    It "Return the step object from the currentStep property" {
        Mock Get-WmiObject { return Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json }
        $mon.CurrentStep = 10
        $step = $mon.getCurrentStep()
        $step.Step | Should -Be 10

    }
    It "Returns 0 if no steps are available" {

    }
}
Describe "getNextStepWhenAvailable(`$maxWaitSeconds)" {
    BeforeEach{
        $script:result = @{CallCount = 0}
        $script:result.SleepCallCount = 0
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        Mock Start-Sleep { $script:result.SleepCallCount = $script:result.SleepCallCount + 1 }
    }
    It "If next step is available, return next step (even if step number is not consecutive)" {
        Mock Get-WmiObject { return Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json }
        @(1, 2, 3, 10, 20, 21, 30, 100) | % {
            # $mon.CacheLastRenewed = (Get-Date).AddSeconds(-10);
            $step = $mon.getNextStepWhenAvailable(1000)
            # Write-Host "Step $($step.Step) found expected $_"
            $step.Step | Should -Be $_
        }
    }
    It "Return next step when it becomes available" {
        $script:result.DateValue = Get-Date
        $script:result.DateCallCount = 0

        Mock Get-WmiObject {
            $script:result.CallCount = $script:result.CallCount + 1
            $steps = Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json
            if ($script:result.SleepCallCount -eq 0) { return $steps | ? { $_.Step -le 3}}
            if ($script:result.CallCount -eq 1) { return $steps | ? { $_.Step -le 20}}
            if ($script:result.CallCount -le 3) { return $steps | ? { $_.Step -le 20}}
            if ($script:result.CallCount -eq 4) { return $steps | ? { $_.Step -le 30}}
            if ($script:result.CallCount -lt 20) { return $steps }
        }
        Mock Get-Date {
            $script:result.DateValue = $script:result.DateValue.AddSeconds(10)
            $script:result.DateCallCount = $script:result.DateCallCount + 1
            return $script:result.DateValue
        }
        # # used for generating correct tests from working code (hope it works !)
        # $stepCount = @(1, 2, 3, 10, 20, 21, 30, 100).Count
        # 1..$stepCount | %{
        #     $step = $mon.getNextStepWhenAvailable(1000)
        #     Write-Host ""
        #     Write-Host "`$step = `$mon.getNextStepWhenAvailable(1000)"
        #     Write-Host "`$step.Step | Should -Be $($step.Step)"
        #     Write-Host "`$script:result.CallCount | Should -Be $($script:result.CallCount)"
        #     Write-Host "`$script:result.SleepCallCount | Should -Be $($script:result.SleepCallCount)"
        #     Write-Host "`$script:result.DateCallCount | Should -Be $($script:result.DateCallCount)"
        #     Write-Host ""
        # }
        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 1
        $script:result.CallCount | Should -Be 2
        $script:result.SleepCallCount | Should -Be 0
        $script:result.DateCallCount | Should -Be 5

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 2
        $script:result.CallCount | Should -Be 4
        $script:result.SleepCallCount | Should -Be 0
        $script:result.DateCallCount | Should -Be 10

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 3
        $script:result.CallCount | Should -Be 6
        $script:result.SleepCallCount | Should -Be 0
        $script:result.DateCallCount | Should -Be 15

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 10
        $script:result.CallCount | Should -Be 9
        $script:result.SleepCallCount | Should -Be 1
        $script:result.DateCallCount | Should -Be 23

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 20
        $script:result.CallCount | Should -Be 11
        $script:result.SleepCallCount | Should -Be 1
        $script:result.DateCallCount | Should -Be 28

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 21
        $script:result.CallCount | Should -Be 13
        $script:result.SleepCallCount | Should -Be 1
        $script:result.DateCallCount | Should -Be 33

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 30
        $script:result.CallCount | Should -Be 15
        $script:result.SleepCallCount | Should -Be 1
        $script:result.DateCallCount | Should -Be 38

        $step = $mon.getNextStepWhenAvailable(1000)
        $step.Step | Should -Be 100
        $script:result.CallCount | Should -Be 17
        $script:result.SleepCallCount | Should -Be 1
        $script:result.DateCallCount | Should -Be 43


    }
    It "Returns `$null if timeout is reached" {
        $script:result.DateValue = Get-Date
        Mock Get-WmiObject {
            $script:result.CallCount = $script:result.CallCount + 1
            $steps = Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json
            return $steps | ? { $_.Step -le 3 }
        }
        Mock Get-Date {
            $script:result.DateValue = $script:result.DateValue.AddSeconds(100)
            return $script:result.DateValue
        }
        $step = $mon.getNextStepWhenAvailable(1000)
        $step = $mon.getNextStepWhenAvailable(1000)
        $step = $mon.getNextStepWhenAvailable(1000)
        $step = $mon.getNextStepWhenAvailable(1000)
        $step | Should -Be $null
    }
}
Describe "getStepNumberWhenAvailable(`$stepNumber, `$maxWaitSeconds)" {
    BeforeEach{
        $script:result = @{DateValue=Get-Date}
        $script:result.DateCallCount = 0
        Mock Get-WmiObject -Verifiable { return (Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json) | ? { $_.Step -le 20} }
        Mock Get-WmiObject -ParameterFilter {$query -like "SELECT PackageID FROM SMS_TaskSequencePackage*"} { return [PSCustomObject]@{PackageID = "REB0123"}}
        Mock Get-WmiObject -ParameterFilter {$query -like "SELECT ResourceId FROM SMS_R_System*"} { return [PSCustomObject]@{ResourceId="123456"}}
        Mock Start-Sleep {}
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
    }
    It "If step number or greater step is not available until timeout, return `$null" {
        Mock Get-Date  -Verifiable {
            $script:result.DateValue = $script:result.DateValue.AddSeconds(10)
            return $script:result.DateValue
        }
        $mon.getStepNumberWhenAvailable(21,1000) | Should -Be $null
        Should -invoke Get-WmiObject -Time 5
        Should -invoke Start-Sleep -Time 5
    }
    It "If step is already available, return imediately the desired step (or next greater if this step doesn't exists)" {
        $mon.getStepNumberWhenAvailable(20,1000) | Select -ExpandProperty Step | Should -Be 20
        Should -invoke Start-Sleep -Time 0
        Should -invoke Get-WmiObject -Time 3 -Exactly # 2 initial calls during constructor + 1 to retrieve steps
    }
    It "If step is not yet available, wait until it becomes available (or next greater...)" {
        Mock -Verifiable Start-Sleep -ParameterFilter {$Seconds -eq 10} {
            $script:result.DateCallCount = $script:result.DateCallCount + 1
        }

        Mock Get-WmiObject -Verifiable {
            $steps = Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json
            if ($script:result.DateCallCount -lt 50) { return $steps | ? { $_.Step -le 20}}
            return $steps
        }
        Mock Get-Date  -Verifiable {
            $script:result.DateValue = $script:result.DateValue.AddSeconds(1)
            return $script:result.DateValue
        }
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)

        $mon.getStepNumberWhenAvailable(100,1000) | Select -ExpandProperty Step | Should -Be 100
        Should -invoke Get-WmiObject -Time 5
        Should -invoke Get-Date -Time 100

    }
}

Describe "getStepWhenAvailableFromActionName(`$actionName, `$maxWaitSeconds)" {
    BeforeEach{
        $script:result = @{DateValue=Get-Date}
        $script:result.DateCallCount = 0
        Mock Get-WmiObject -Verifiable { return (Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json) | ? { $_.Step -le 20} }
        Mock Get-WmiObject -ParameterFilter {$query -like "SELECT PackageID FROM SMS_TaskSequencePackage*"} { return [PSCustomObject]@{PackageID = "REB0123"}}
        Mock Get-WmiObject -ParameterFilter {$query -like "SELECT ResourceId FROM SMS_R_System*"} { return [PSCustomObject]@{ResourceId="123456"}}
        Mock Start-Sleep {}

        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
    }
    It "If a step with actionName is not available until timeout, return `$null" {
        Mock Get-Date  -Verifiable {
            $script:result.DateValue = $script:result.DateValue.AddSeconds(10)
            return $script:result.DateValue
        }
        $mon.getStepWhenAvailableFromActionName("TS Non Existing Action Indicator", 1000) | Should -Be $null
        Should -invoke Get-WmiObject -Time 5
        Should -invoke Start-Sleep -Time 5
    }
    It "If a step with actionName is already available until timeout, return that step" {
        # "TS Failure Action Indicator"
        # "TS Success Action Indicator"
        Mock Start-Sleep {}
        Mock Get-WmiObject -Verifiable {
            $steps = Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeSuccessStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json
            return $steps
        }

        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        Mock Get-Date  -Verifiable {
            $script:result.DateValue = $script:result.DateValue.AddSeconds(10)
            return $script:result.DateValue
        }
        $res =$mon.getStepWhenAvailableFromActionName("TS Success Action Indicator", 1000)
        $res.Step | Should -Be 100
        Should  -Invoke Get-Date -Times 30
        {Should  -Invoke Get-Date -Times 60} | Should -Throw
    }
    It "If a step with actionName is not yet available wait for it and the return it" {
        $script:result.DateCallCount = 0
        Mock Get-WmiObject -Verifiable {
            $steps = Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeSuccessStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json
            if ($script:result.DateCallCount -lt 80) { return $steps | ? { $_.Step -le 20}}
            return $steps
        }
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        Mock Get-Date  -Verifiable {
            $script:result.DateCallCount = $script:result.DateCallCount + 1
            $script:result.DateValue = $script:result.DateValue.AddSeconds(10)
            return $script:result.DateValue
        }
        $res = $mon.getStepWhenAvailableFromActionName("TS Success Action Indicator", 1000)
        $res.Step | Should -Be 100
        Should -Invoke Get-Date -Times 80
    }
}

Describe "getStepWhenAvailableFromActionNames" {

    It "return expected step as soon as one element is found" {
        $script:result = @{}
        $script:result.date = Get-Date
        Mock Get-WmiObject -Verifiable { return (Get-Content "$TestDataPath/MECMDeviceDeploymentMonitor/fakeSuccessStepsSequence-0-1-2-3-10-20-21-30-100.json" | ConvertFrom-Json) }
        Mock Get-WmiObject -ParameterFilter {$query -like "SELECT PackageID FROM SMS_TaskSequencePackage*"} { return [PSCustomObject]@{PackageID = "REB0123"}}
        Mock Get-WmiObject -ParameterFilter {$query -like "SELECT ResourceId FROM SMS_R_System*"} { return [PSCustomObject]@{ResourceId="123456"}}
        Mock Get-Date  -Verifiable {$script:result.date = $script:result.date.AddSeconds(10); return $script:result.date}
        Mock Start-Sleep {}
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        $mon.getStepWhenAvailableFromActionNames(@("TS Success Action Indicator", "some action name"), 1000) | Select -ExpandProperty ActionName | Should -Be "some action name"
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        $mon.getStepWhenAvailableFromActionNames(@("TS Success Action Indicator", "non existing"), 1000) | Select -ExpandProperty ActionName | Should -Be "TS Success Action Indicator"
        $mon = [MECMDeviceDeploymentMonitor]::new($logger, $SMS_SERVER, $SMS_SITECODE, $SMS_MONITORED_TS_NAME, $TEST_VM_NAME)
        $mon.getStepWhenAvailableFromActionNames(@("TS Success Action Indicator", "non existing"), 1000) | Select -ExpandProperty Step | Should -Be 100
    }
}