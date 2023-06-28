$exludedFiles = @("Loader.ps1")
$files = gci -File $LibPath -filter '*.ps1'

$files | ? { $exludedFiles -notcontains $_.Name  } | % {
	Write-Host "Chargement de $($_.BaseName)"
	. "$($_.FullName)"
}