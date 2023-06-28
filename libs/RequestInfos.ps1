function Show-RequestInfos {
	param(
		[ValidateNotNullOrEmpty()]
		$Request
	)
	switch ($Request.type){
		"NEW_USER" { $requestType = "Création de compte" }
		"EXISTING_USER_JOIN_SECOND_DEPARTMENT" { $requestType = "Ajout de droits (nouveau service en complément)" }
        "EXISTING_USER_CHANGE_DEPARTMENT" { $requestType = "Remplacement de droits (lié à un changement de service)" }
        "EXISTING_USER_CUSTOM_ADD" { $requestType = "Ajout de droits à la carte" }
		default { Write-Host "Type de requête inconnue $($Request.type)" }
	}
	$i = $Request.userInfos
	if ($i.ExpirationDate) {
		$expiration = $i.ExpirationDate
	} else {
		$expiration = "Aucune"
	}
	Write-Host ""
	Write-Host ""
	Write-Host ""
	Write-Host "".PadRight(100, '#')
    Write-Host "".PadRight(100, '#')
	Write-Host "                                  Information Requête"
    Write-Host "".PadRight(100, '#')
	Write-Host "  Type de Requête      : $requestType"
	Write-Host "  Date d'exécution     : $($Request.executionDate)"
	Write-Host "  Personne à notifier  : $($Request.notificationMail)" 
    Write-Host "  Saisie par $($Request.techInfos.Username) depuis $($Request.techInfos.Computername) " 
	
	Write-Host "".PadRight(100, '#')
	Write-Host "                                  Information Utilisateur"
    Write-Host "".PadRight(100, '#')
	Write-Host "  $('Nom'.PadRight(20, ' ')) : $($i.Surname.PadRight(20,' '))  $('Prénom'.PadRight(20, ' ')) : $($i.GivenName.PadRight(20,' '))" 
	Write-Host "  $('SamAccountName'.PadRight(20, ' ')) : $($i.SamAccountName.PadRight(20,' '))"
	Write-Host "  $('Email'.PadRight(20, ' ')) : $($i.Emailaddress.PadRight(30,' '))" 
	Write-Host "  $('Date d''expiration'.PadRight(20, ' ')) : $expiration" 
	Write-Host "  $('OU'.PadRight(20, ' ')) : $($i.OU)" 
	Write-Host "".PadRight(100, '#')
	Write-Host "                                  Internet : $($Request.internet)" 
	Write-Host "".PadRight(100, '#')
	Write-Host "".PadRight(100, '#')
	Write-Host "                                  Imprimantes"
    Write-Host "".PadRight(100, '#')
	if (!$Request.printers) {
		Write-Host "      Aucunes"
	} else {
		Write-Host "    " -NoNewLine
		$Request.printers | % { Write-Host "$_ " -NoNewLine }
	}
    Write-Host " "
	Write-Host "".PadRight(100, '#')
	Write-Host "                                  Lecteurs réseaux"
    Write-Host "".PadRight(100, '#')
	if ($($Request.shareRequest.templateSamAccountName)){
		$templateUser = $($Request.shareRequest.templateSamAccountName)
	} else {
		$templateUser = "Aucun"
    }
	Write-Host "  Même profil que    : $templateUser" 
	foreach ($share in $Request.shareRequest.shares) {
		Write-Host -NoNewline "      - $($share.Letter):  $($share.UNCPath) " 
        $shareInfos = Get-LMMShareInfo -UNCPath $share.UNCPath
        if (!$shareInfos) {
            Write-Host "(Partage inconnu, soyez vigilent !)"
            continue;
        }
        if (@(2,3) -contains $shareInfos.Type){
            if ($_.forceRW -eq $true) {
                Write-Host " (RW)"
            } else {
                Write-Host " (RO)"
            }
        } elseif ($shareInfos.Type -eq 5){
            Write-Host " Interdit : $($shareInfos.Message)"
        } else {
            Write-Host ""
        }
	}
	Write-Host "".PadRight(100, '#')
	Write-Host "                                  Information Tilt"
	Write-Host "".PadRight(100, '#')
    Write-Host " $($Request.tiltInfos)" 
	Write-Host "".PadRight(100, '#')
    Write-Host "".PadRight(100, '#')
	
	
}