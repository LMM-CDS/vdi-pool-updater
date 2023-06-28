$sharesByType = gc -Encoding UTF8 $sharesByTypeFilePath | ConvertFrom-Json

function Get-LMMShareInfo {
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$UNCPath
    )
    [array]$res = $sharesByType | ?{$_.share -eq $UNCPath }
    if (!$res) {
        return Write-Host "Share not found '$UNCPath'"
    }
    if ($res.Count -ne 1) {
        throw "Not 1 exact share found for '$UNCPath' ($($res.Count))"
    }
    return $res
}