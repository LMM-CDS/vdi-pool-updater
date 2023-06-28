
BeforeAll {
	#Import-Module "C:\Path\To\file.psm1" -DisableNameChecking
    $ProjectRoot = "$PSScriptRoot\.."
	$LibsDir = "$ProjectRoot\libs"
	. "$LibsDir\script.ps1"
    $LibPath = "$PSScriptRoot\data\requests"

	# backup original cmdlet for calling during mock
	# $getDateCmdlet = Get-Command Get-Date -CommandType Cmdlet

}

Describe "SomeTEst" {
		It "Should return true " {
			$true | Should -Be $true
		}
		It "Should return false" {
			$false | Should -Be $false
		}
}