$reservedNetworkShares = @("P", "L", "B")
function Add-LMMLoginScriptNetworkShare {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Letter,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$UNCPath
    )
    $filePath = "$netlogonUserScriptPath\$SamAccountName.scr"
    $line = "use $($Letter): `"$UNCPath`""
    $m = "        - Tentative d'ajout de '$line' dans '$filePath'"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    #if (Test-LMMLoginScriptDriveLetterInUse -SamAccountName $SamAccountName -Letter $Letter) { return $false }
    $existingDrives = Get-LMMMappedNetworkDrives -SamAccountName $SamAccountName
    $existingDrive = $existingDrives | ?{ $_.Letter -eq "$Letter" }
    $letterExists = ($existingDrive  -ne $null)
    if ($letterExists) {
        $sameUNCPath = ($existingDrive | ? { $_.UNCPath -eq "$UNCPath" }) -ne $null
        if ($sameUNCPath) {
            $m = "            ==> Pas d'ajout (lettre et UNC d�ja pr�sent"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            return $false
        } else {
            $m = "            ==> ERREUR : Lettre d�j� utilis�e pour un autre chemin : $($existingDrive.UNCPath)"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            throw "ERREUR : Lettre d�j� utilis�e pour un autre chemin : $($existingDrive.UNCPath)"
            return $false
        }

    }


    # V�rifie ajoute un saut de ligne si le fichier n'en poss�de pas
    [int]$lastChar = (Get-Content $filePath -Raw)[-1]
    #Write-Host "LastChar $lastChar"
    if (@(10,13) -notcontains $lastChar) {
        "" | Add-Content $filePath -Encoding UTF8
    }
    $line | Add-Content $filePath -Encoding UTF8
    return $true
}

function Test-LMMLoginScriptDriveLetterInUse {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Letter
    )
    $filePath = "$netlogonUserScriptPath\$SamAccountName.scr"
    $line = "use $($Letter):"
    $content = Get-Content $filePath -Raw
    return $content -match "use $Letter`:\s+"

}
function Add-LMMNetworkSharesWithPermissionsV2 {
    param(
        [ValidateNotNullOrEmpty()]
        [array]$ShareRequest,

        [ValidateNotNullOrEmpty()]
        [array]$ADUser
    )

    $TemplateUser = $ShareRequest.TemplateSamAccountName
    if ($TemplateUser) {
        $templateADUser = Get-ADUser -Filter "SamAccountName -like '$TemplateUser'" -Server $DCServer

        if (!$TemplateADUser) {
            $m = "            X Erreur : pas d'utilisateur modèle '$TemplateUser' trouv�"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            throw "Erreur : pas d'utilisateur '$TemplateUser' trouv�"
        }

        $templateGroups = $templateADUser |Get-ADPrincipalGroupMembership -Server $DCServer | Select -ExpandProperty name

        $m = "                - L'utilisateur '$TemplateUser' est membre direct de $($templateGroups.Count) groupes"
        Write-Log -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

        $m = "                    $($templateGroups -join ' | ')"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
    } else {
        $templateGroups = @()
    }

    $m = "[+] Ajout des lecteurs r�seaux"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    if ($ShareRequest.shares) { # n�cessaire car convertfrom-json transforme [] en $null et foreach it�re 1 fois avec $null
        foreach ($networkDrive in $ShareRequest.shares){
            $UNCPath = $networkDrive.UNCPath
            $ForceRW = $networkDrive.ForceRW
            $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath
            if ($networkDrive.ForceRW -eq $true){
                $forceRW = $true
            }else {
                $forceRW = $false
            }

            $m = "    * Ajout du partage $($networkDrive.UNCPath) ($($networkDrive.Letter):)   (Type : $($shareInfo.Type)) (RW : $forceRW)"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

            if ($shareInfo.Type -eq 5){

                    $m = "        X Non application du partage (interdit)"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

                    $m = "          ==> $($shareInfo.Message)"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                    continue;
            }

            $shareHaveBeenAddedResult = (Add-LMMLoginScriptNetworkShare -SamAccountName $ADUser.SamAccountName -Letter $networkDrive.Letter -UNCPath $networkDrive.UNCPath)
            # Ajout des groupes li�s aux partages r�seaux
            if ($templateGroups.Count -gt 0){
                $m = "        - Attribution des droits sur la base des autorisations de '$($ShareRequest.TemplateSamAccountName)'"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            } else {
                $m = "        - Attribution des droits"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            }

            if ($shareHaveBeenAddedResult -or $forceRW -eq $true) {  ## en cas de MAJ d'un lecteur forceRW, shareHaveBeenAdded n'est pas à true
                Add-LMMNetworkSharePermissionV2 -ADUser $ADUser -UNCPath $networkDrive.UNCPath -TemplateUserGroups $templateGroups -ForceRW:$forceRW
            }
        }
    }

    $m = "    Fin d'Ajout des lecteurs r�seaux"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
}

function Add-LMMNetworkSharePermissionV2 {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $ADUser,

        [string[]]$TemplateUserGroups=@(),

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$UNCPath,

        [ValidateNotNullOrEmpty()]
        [switch]$ForceRW
    )
    $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath
    if (!$shareInfo) {
        $m = "            - Pas d'info trouv�e pour le partage $UNCPath !"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m

        $m = "              ===> Pas d'info trouv�e pour le partage $UNCPath ! (IL FAUT TRAITER LES DROITS A LA MAIN !!)"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
        return
        #throw "Pas d'info trouv�e pour le partage $UNCPath !"
    }
    $m = "            - Ajout des autorisations pour $($ADUser.SamAccountName) sur le partage $UNCPath (RW='$ForceRW')"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    # mise en conformit� : suppression du domaine
    $shareInfo.GroupsRO = $shareInfo.GroupsRO | %{ "$_".Replace("ADMIN\", "") }
    $shareInfo.GroupsRW = $shareInfo.GroupsRW | %{ "$_".Replace("ADMIN\", "") }


    $grp = $null
    switch ($shareInfo.Type){
        1 { # Ajout de l'utilisateur au groupe RW
            $grp = $shareInfo.GroupsRW | Select -First 1
        }
        2 { # Ajout de l'utilisateur au groupe RO SAUF SI l'attribut *rw* est � true dans la demande
            if (!$ForceRW) {
                $grp = $shareInfo.GroupsRO | Select -First 1
            } else {
                $grp = $shareInfo.GroupsRW | Select -First 1
            }
        }
        3 { # Ajout de l'utilisateur au groupe RO SAUF SI l'attribut *rw* est � true dans la demande
            if (!$ForceRW) {
                $grp = $shareInfo.GroupsRO | Select -First 1
            } else {
                $grp = Read-LMMADGroupSelection -TemplateGroups $TemplateUserGroups -ShareInfo $shareInfo -RWOnly
            }
        }
        4 { # R�cup�ration de la liste des groupes RW du partage : *groupes_rw*
            $grp = Read-LMMADGroupSelection -TemplateGroups $TemplateUserGroups -ShareInfo $shareInfo -RWOnly
        }

        5 {
            $m = "            X Partage 'interdit' : $($shareInfo.Message)"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            return

        }
        default {
            $m = "            ? Partage de type '$($shareInfo.Type)' : s�lectionner le groupe de votre choix"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

            $grp = Read-LMMADGroupSelection -TemplateGroups $TemplateUserGroups -ShareInfo $shareInfo
        }
    }

	if ($grp -eq "Tout le monde") {
		$m = "                ==> Ajout au groupe '$grp' inutile"
		Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
	} else {
		$m = "                ==> Ajout au groupe '$grp'"
		Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
		Add-ADGroupMember -Identity (Get-ADGroup $grp).DistinguishedName  -Server $DCServer -Members $ADUser.SamAccountName
	}
}

function Add-LMMNetworkSharesWithPermissions {
    param(
        [ValidateNotNullOrEmpty()]
        [array]$ShareRequest,

        [ValidateNotNullOrEmpty()]
        [array]$ADUser
    )
	############# PROVISOIRE #######################################
	$m = "## PROVISOIRE ## Suppression des informations de templateSamAccountName en attendant que le script prenne en charge la suggestion de groupe bas� sur celui-ci"
	Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
	if ($ShareRequest.TemplateSamAccountName) { $ShareRequest.TemplateSamAccountName = "" }
	############# PROVISOIRE #######################################

    # Si pas de template user, v�rification que tous les partages demand�s sont de type 1 ou 2 ou 3
    if (!$ShareRequest.TemplateSamAccountName) {
        if ($ShareRequest.shares) {# n�cessaire car convertfrom-json transforme [] en $null et foreach it�re 1 fois avec $null
            $ShareRequest.shares |%{
                $UNCPath = $_.UNCPath
                $ForceRW = $_.ForceRW
                $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath
                if (!$shareInfo) {
                    $m = "Pas d'info trouv�e pour le partage $UNCPath !"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                    throw "Partage de type $($shareInfo.type) impossible sans TemplateUser"
                }
                if (!$TemplateUser) {
                    Write-Host "- Pas de TemplateUser fourni : v�rification que le groupe peut �tre d�termin� sans cette information ($($_.UNCPath))"
                    if (@(1,2,3,5) -notcontains $shareInfo.type){
                        $m = "Partage de type $($shareInfo.type) impossible sans TemplateUser ($UNCPath)"
                        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                        ### On arrete de lever une exception car on va tenter un traitement manuel (ajout de groupe a la main via un menu)
                        #throw "Partage de type $($shareInfo.type) impossible sans TemplateUser"
                    }
                    if ($shareInfo.type -eq 3 -and $ForceRW -eq $true){
                        $m = "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
                        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                        throw "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
                    }
                }
            }
        }
    }

    # Ajout des lecteurs r�seaux :

    $m = "[+] Ajout des lecteurs r�seaux"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    if ($ShareRequest.shares) { # n�cessaire car convertfrom-json transforme [] en $null et foreach it�re 1 fois avec $null
        foreach ($networkDrive in $ShareRequest.shares){
            $UNCPath = $networkDrive.UNCPath
            $ForceRW = $networkDrive.ForceRW
            $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath

            $m = "    * Ajout du partage $($networkDrive.UNCPath) ($($networkDrive.Letter):)   (Type : $($shareInfo.Type))"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

            if ($shareInfo.Type -eq 5){

                    $m = "        X Non application du partage (interdit)"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

                    $m = "          ==> $($shareInfo.Message)"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                    continue;
            }

            $shareHaveBeenAddedResult = (Add-LMMLoginScriptNetworkShare -SamAccountName $ADUser.SamAccountName -Letter $networkDrive.Letter -UNCPath $networkDrive.UNCPath)
            # Ajout des groupes li�s aux partages r�seaux
            $m = "        - Attribution des droits sur la base des autorisations de $($ShareRequest.TemplateSamAccountName)"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

            if ($networkDrive.ForceRW -eq $true){
                $forceRW = $true
            }else {
                $forceRW = $false
            }
            if ($shareHaveBeenAddedResult) {
                Add-LMMNetworkSharePermission -ADUser $ADUser -UNCPath $networkDrive.UNCPath -TemplateUser $ShareRequest.TemplateSamAccountName -ForceRW:$forceRW
            }
        }
    }

    #Write-Host "- Lancement d'un nouveau powershell pour ajouter d'�ventuels groupes"
    #Write-Host "- TAPER 'exit' POUR CONTINUER"
    #Start-process -Wait powershell.exe
    $m = "    Fin d'Ajout des lecteurs r�seaux"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

}

function Choose-SharePermissions {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $ShareInfo
    )

    $m = "            - Veuillez s�lectionner le groupe � attribuer pour l'acc�s au partage $($ShareInfo.UNCPath)"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    $m = "                - Groupes autoris�s en lecture :"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    $ShareInfo.GroupsRO | % {
        $m = "                    - $_"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
    }

    $m = "                - Groupes autoris�s en �criture :"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    $ShareInfo.GroupsRW | % {
        $m = "                    - $_"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
    }

    $groupList = @()
    $groupList += $ShareInfo.GroupsRO
    $groupList += $ShareInfo.GroupsRW

    $group = Get-MenuSelection -MenuPrompt "Selectionnez le groupe � ajouter" -MenuItems $groupList
    $ShareInfo.Type = 1
    $ShareInfo.GroupsRO = @()
    $ShareInfo.GroupsRW = @($group)

}


function Read-LMMADGroupSelection {
    param(
        $ShareInfo,
        $TemplateGroups,
        [switch]$ROOnly,
        [switch]$RWOnly
    )
    if ($ROOnly -and $RWOnly) { throw "Cannot use both ROOnly and RWOnly switch" }

    $selectedSymbol = "(x)"
    $groupList = @()
    $labels = @()

    if (!$ROOnly -and !$RWOnly) {
        foreach ($group in $ShareInfo.GroupsRO){
            if ($TemplateGroups -contains $group) { $selected = $selectedSymbol } else { $selected = "   " }
            $labels += "$selected $group  (RO)"
        }
        foreach ($group in $ShareInfo.GroupsRW){
             if ($TemplateGroups -contains $group) { $selected = $selectedSymbol } else { $selected = "   " }
             $labels += "$selected $group  (RW)"
        }
        $groupList = $ShareInfo.GroupsRO + $ShareInfo.GroupsRW

    } elseif ($ROOnly) {
        $groupList = $ShareInfo.GroupsRO
        foreach ($group in $ShareInfo.GroupsRO){
            if ($TemplateGroups -contains $group) { $selected = $selectedSymbol } else { $selected = "   " }
            $labels += "$selected $group  (RO)"
        }
    } elseif ($RWOnly) {
        $groupList = $ShareInfo.GroupsRW
        foreach ($group in $ShareInfo.GroupsRW){
            if ($TemplateGroups -contains $group) { $selected = $selectedSymbol } else { $selected = "   " }
            $labels += "$selected $group  (RW)"
       }
   }
   #bugfix : pour une raison indéterminée shareInfo.groupsRO ou RW deviennent null lorsque le tableau est vide...
   #         on supprime donc les éléments null de grouplist avant de le passer à Get-MenuSelection
   $groupList = $groupList | ? { $_ -ne $null }

   $group = Get-MenuSelection -MenuPrompt "Selectionnez le groupe � ajouter" -MenuItems $groupList -MenuLabels $labels
   return $group

}

function Add-LMMNetworkSharePermission {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $ADUser,

        [string]$TemplateUser,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$UNCPath,

        [ValidateNotNullOrEmpty()]
        [switch]$ForceRW
    )
    $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath
    if (!$shareInfo) {
        $m = "            - Pas d'info trouv�e pour le partage $UNCPath !"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m

        $m = "              ===> Pas d'info trouv�e pour le partage $UNCPath ! (IL FAUT TRAITER LES DROITS A LA MAIN !!)"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
        return
        #throw "Pas d'info trouv�e pour le partage $UNCPath !"
    }
    if (!$TemplateUser) {
        $m = "            - Pas de TemplateUser fourni : v�rification que le partage peut �tre d�termin� sans cette information"
        Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

        if (@(1,2,3,5) -notcontains $shareInfo.type){
            $m = "            - Partage de type $($shareInfo.type) : proposition de traitement manuel"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            if ((Get-MenuSelection -MenuPrompt "Souhaitez-vous choisir manuellement le groupe � ajouter ?" -MenuItems "N", "O" ) -eq "O"){
                Choose-SharePermissions -ShareInfo $shareInfo
            } else {
                $m = "            - Partage de type $($shareInfo.type) impossible sans TemplateUser"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                throw "Partage de type $($shareInfo.type) impossible sans TemplateUser"
            }
        }
        if ($shareInfo.type -eq 3 -and $ForceRW -eq $true){
            $m = "            - Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            throw "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
        }
    }

    $m = "            - Ajout des autorisations pour $($ADUser.SamAccountName) sur le partage $UNCPath (TemplateUser='$TemplateUser') (RW='$ForceRW')"
    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

    if (@(1,2) -notcontains $shareInfo.type){
		if ($TemplateUser) {
			$templateADUser = Get-ADUser -Filter "SamAccountName -like '$TemplateUser'" -Server $DCServer

			if (!$TemplateADUser) {
				$m = "            X Erreur : pas d'utilisateur '$TemplateUser' trouv�"
				Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
				throw "Erreur : pas d'utilisateur '$TemplateUser' trouv�"
			}

			$templateGroups = $templateADUser |Get-ADPrincipalGroupMembership -Server $DCServer | Select -ExpandProperty name

			$m = "                - L'utilisateur $TemplateUser est membre direct de $($templateGroups.Count) groupes"
			Write-Log -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

			$m = "                    $($templateGroups -join ' | ')"
			Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
		}
	}

    # mise en conformit� : suppression du domaine
    $shareInfo.GroupsRO = $shareInfo.GroupsRO | %{ "$_".Replace("ADMIN\", "") }
    $shareInfo.GroupsRW = $shareInfo.GroupsRW | %{ "$_".Replace("ADMIN\", "") }

    switch ($shareInfo.Type){
        1 { # Ajout de l'utilisateur au groupe RW
            $grp = $shareInfo.GroupsRW | Select -First 1
        }
        2 { # Ajout de l'utilisateur au groupe RO SAUF SI l'attribut *rw* est � true dans la demande
            if (!$ForceRW) {
                $grp = $shareInfo.GroupsRO | Select -First 1
            } else {
                $grp = $shareInfo.GroupsRW | Select -First 1
            }
        }
        3 { # Ajout de l'utilisateur au groupe RO SAUF SI l'attribut *rw* est � true dans la demande
            if (!$ForceRW) {
                $grp = $shareInfo.GroupsRO | Select -First 1
            } else {
                $grp = Get-LMMFirstCommonGroup -LeftGroupList $shareInfo.GroupsRW -RightGroupList $templateGroups
            }
        }
        4 { # R�cup�ration de la liste des groupes RW du partage : *groupes_rw*
            $grp = Get-LMMFirstCommonGroup -LeftGroupList $shareInfo.GroupsRW -RightGroupList $templateGroups
        }

        5 {
            $m = "            X Partage 'interdit' : $($shareInfo.Message)"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m

            return

        }
        default {
            throw "            X Type non g�r� '$($shareInfo.Type)' pour le partage $($shareInfo.share). ShareInfo = $($shareInfo | ConvertTo-Json)"
        }
    }

	if ($grp -eq "Tout le monde") {
		$m = "                ==> Ajout au groupe $grp inutile"
		Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
	} else {
		$m = "                ==> Ajout au groupe $grp"
		Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Info -Component "$($MyInvocation.MyCommand.Name)" -Message $m
		Add-ADGroupMember -Identity (Get-ADGroup $grp).DistinguishedName  -Server $DCServer -Members $ADUser.SamAccountName
	}



    #Add-LMMNetworkSharePermission -ADUser $adUser -UNCPath $networkDrive.UNCPath -TemplateUser $shareRequest.TemplateSamAccountName
}


function Is-LMMValidNetworkRequest {
    Param(
        [ValidateNotNullOrEmpty()]
        [array]$ShareRequest
    )
    # v�rification que les qu'il n'y a pas de partages de type 0 dans la demande
    $ShareRequest.shares |%{
        $UNCPath = $_.UNCPath
        $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath
        if (!$shareInfo) {
            $m = "Pas d'info trouv�e pour le partage $UNCPath !"
            Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
            return $false
        }
        if (@(1,2,3,4,5) -notcontains $shareInfo.type){
            Write-Host "- Pas de TemplateUser fourni : v�rification que le partage peut �tre d�termin� sans cette information"
            if (@(1,2,3,5) -notcontains $shareInfo.type){
                $m = "Partage de type $($shareInfo.type) impossible sans TemplateUser"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                throw "Partage de type $($shareInfo.type) impossible sans TemplateUser"
            }

        }

        if (!$TemplateUser) {
            Write-Host "- Pas de TemplateUser fourni : v�rification que le partage peut �tre d�termin� sans cette information"
            if (@(1,2,3,5) -notcontains $shareInfo.type){
                $m = "Partage de type $($shareInfo.type) impossible sans TemplateUser"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                throw "Partage de type $($shareInfo.type) impossible sans TemplateUser"
            }
            if ($shareInfo.type -eq 3 -and $ForceRW -eq $true){
                $m = "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                throw "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
            }
        }
    }


    # Si pas de template user, v�rification que tous les partages demand�s sont de type 1 ou 2 ou 3
    if (!$ShareRequest.TemplateSamAccountName) {
        $ShareRequest.shares |%{
            $UNCPath = $_.UNCPath
            $ForceRW = $_.ForceRW
            $shareInfo = Get-LMMShareInfo -UNCPath $UNCPath
            if (!$shareInfo) {
                $m = "Pas d'info trouv�e pour le partage $UNCPath !"
                Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m

                throw "Pas d'info trouv�e pour le partage $UNCPath !"
            }
            if (!$TemplateUser) {
                Write-Host "- Pas de TemplateUser fourni : v�rification que le partage peut �tre d�termin� sans cette information"
                if (@(1,2,3,5) -notcontains $shareInfo.type){
                    $m = "Partage de type $($shareInfo.type) impossible sans TemplateUser"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                    throw "Partage de type $($shareInfo.type) impossible sans TemplateUser"
                }
                if ($shareInfo.type -eq 3 -and $ForceRW -eq $true){
                    $m = "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
                    Write-Log -TeeToSTDOUT -Path $GLOBAL:Logfile -Type Error -Component "$($MyInvocation.MyCommand.Name)" -Message $m
                    throw "Partage de type $($shareInfo.type) avec ForceRW='$ForceRW' impossible sans TemplateUser"
                }
            }
        }
    }


}