Import-Module Pester
$configuration = [PesterConfiguration]::Default
$configuration.Output.Verbosity = "Detailed"
$configuration.Output.Verbosity = "Diagnostic"
Invoke-Pester
Read-Host "?"