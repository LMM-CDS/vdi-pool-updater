Import-Module CredentialManager


function Get-StoredCredentials {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Target
    )

    $stored = Get-StoredCredential -Target $Target
    if (-not $stored) {
        # Define Credentials
        $creds = (Get-Credential -Message "$Target")
        New-StoredCredential -Target $Target -UserName $creds.UserName -Password $creds.GetNetworkCredential().Password -Type Generic
    }

    return $stored
}
