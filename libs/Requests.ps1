
function Get-LMMUserAccessRequests {
    return Get-ChildItem -Path $requestsPath -File
}

function Get-LMMUserAccessRequestsToProcess {
    return Get-LMMUserAccessRequests | ? {
        $req = Get-Content -Encoding UTF8 $_.FullName | ConvertFrom-Json
        return (Get-Date $req.executionDate) -le (Get-Date)
    }
}
