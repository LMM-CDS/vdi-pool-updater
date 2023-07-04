BeforeAll {
    . "$PSScriptRoot/../config.global.ps1"
    . "$ProjectRoot/config.test.ps1"

    . "$LibDir/Class.Logger.ps1"

    Remove-Item $TestLogDir -Filter '*.*' -Recurse -Force -ErrorAction SilentlyContinue
	New-Item $TestLogDir -ItemType Directory | Out-Null
}

Describe "Constructor" {
    AfterEach {
        if (Test-Path $TestLogFile) {
            Remove-Item $TestLogFile -Force
        }
    }
	It "Can take 2 parameters (Path, TeeToSTDOUT)" {
        { [Logger]::new($TestLogFile, $true) } |  Should -Not -Throw
	}
	It "Can take 1 parameter (Path)" {
        { [Logger]::new($TestLogFile) } |  Should -Not -Throw
	}
	It "Cannot take 0 parameter ()" {
        { [Logger]::new() } |  Should -Throw
	}
    It "Throw an exception if the log file cannot be created" {
        { [Logger]::new("$TestLogDir/Some/Path/notcreated.log") } |  Should -Throw
	}
	It "'Component' parameter is set to 'Main' by default" {
        ([Logger]::new($TestLogFile)).Component |  Should -Be "Main"
	}
	It "TeeToSTDOUT parameter is set to '$true' by default" {
        ([Logger]::new($TestLogFile)).TeeToSTDOUT |  Should -Be "$true"
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
        $logger = [Logger]::new($TestLogFile, $false)
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

        $logger = [Logger]::new($TestLogFile, $false)
        $logger.Log("Info", "blah")
        $myParam | Should -Be $false

        $logger = [Logger]::new($TestLogFile, $true)
        $logger.Log("Info", "blah")
        $myParam | Should -Be $true
    }
}