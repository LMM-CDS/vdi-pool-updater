BeforeAll {
    $ProjectRoot = "$PSScriptRoot\.."
	$LibsDir = "$ProjectRoot/libs"
    $LogsDir = "$PSScriptRoot/logs"
    $LogFile = "$LogsDir/TestLog.log"

    . "$LibsDir/Class.Logger.ps1"
    . "$PSScriptRoot/../libs/Class.Logger.ps1"

    Remove-Item $LogsDir -Filter '*.*' -Recurse -Force -ErrorAction SilentlyContinue
	New-Item $LogsDir -ItemType Directory | Out-Null
}

Describe "Constructor" {
    AfterEach {
        if (Test-Path $LogFile) {
            Remove-Item $LogFile -Force
        }
    }
	It "Can take 2 parameters (Path, TeeToSTDOUT)" {
        { [Logger]::new($LogFile, $true) } |  Should -Not -Throw
	}
	It "Can take 1 parameter (Path)" {
        { [Logger]::new($LogFile) } |  Should -Not -Throw
	}
	It "Cannot take 0 parameter ()" {
        { [Logger]::new() } |  Should -Throw
	}
    It "Throw an exception if the log file cannot be created" {
        { [Logger]::new("$LogsDir/Some/Path/notcreated.log") } |  Should -Throw
	}
	It "'Component' parameter is set to 'Main' by default" {
        ([Logger]::new($LogFile)).Component |  Should -Be "Main"
	}
	It "TeeToSTDOUT parameter is set to '$true' by default" {
        ([Logger]::new($LogFile)).TeeToSTDOUT |  Should -Be "$true"
	}
}
# Describe "Info method" {
#     It "call Log method with parameter Type = 'Info'"
# }
# Describe "Warning method" {
#     It "call Log method with parameter Type = 'Warning'"
# }
# Describe "Error method" {
#     It "call Log method with parameter Type = 'Error'"
# }

# Describe "Factory method"{
#     It "Return a Logger object instance with the same 'Path' as parent object" {

#     }
#     It "Return a Logger object instance with the 'Component' set to the provided 'component' parameter" {

#     }
# }

Describe "Log methods" {
    BeforeEach{
        Set-Variable -Name myParam -Value $false -Scope Script
        $logger = [Logger]::new($LogFile, $false)
        $logger.SetLogLevel("Debug")
    }

    It "Test Mock variable scope"{
        function blah{ Write-Host "was not hooked"}
        Mock blah{ Set-Variable -Name myVar -Value $true -Scope Script }
        blah
        $myVar | Should -be $true
    }
    # It "Calls 'Write-log' with 'Path' parameter"{
    #     Mock Write-Log { $receivedParams = $PesterBoundParameters}
    #     $logger.Info("Message")
    # }
    It "Calls 'Write-log' with 'Message' parameter"{
        Mock Write-Log{ Set-Variable -Name myParam -Value $Message -Scope Script }
        $logger.Log("Info", "blah")
        $myParam | Should -Be "blah"
    }
    It "Calls 'Write-log' with 'Component' parameter"{
        Mock Write-Log{ Set-Variable -Name myParam -Value $Component -Scope Script }
        $logger.Log("Info", "blah")
        $myParam | Should -Be "Main"
    }
    It "Calls 'Write-log' with correct 'Type' parameter"{
        Mock Write-Log{ Set-Variable -Name myParam -Value $Type -Scope Script }

        $logger.Error("blah")
        $myParam | Should -Be "Error"

        $logger.Warning("blah")
        $myParam | Should -Be "Warning"

        $logger.Info("Info")
        $myParam | Should -Be "Info"

        $logger.Verbose("blah")
        $myParam | Should -Be "Verbose"

        $logger.Debug("blah")
        $myParam | Should -Be "Debug"

    }
    It "Calls 'Write-log' with 'TeeToSTDOUT' parameter"{
        Set-Variable -Name myParam -Value $false -Scope Script
        Mock Write-Log{ Set-Variable -Name myParam -Value $TeeToSTDOUT -Scope Script }

        $logger = [Logger]::new($LogFile, $false)
        $logger.Log("Info", "blah")
        $myParam | Should -Be $false

        $logger = [Logger]::new($LogFile, $true)
        $logger.Log("Info", "blah")
        $myParam | Should -Be $true
    }
}