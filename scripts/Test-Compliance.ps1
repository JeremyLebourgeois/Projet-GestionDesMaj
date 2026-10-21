<#
.SYNOPSIS
    Vérifie la conformité des machines du parc vis-à-vis d'une liste de correctifs requis (Partie 4).

.DESCRIPTION
    Ce script lit la liste des KB requises et le fichier d'inventaire des machines.
    Pour chaque machine :
      - En local (localhost / 127.0.0.1 / nom de la machine hôte) : exécution directe de Get-HotFix.
      - À distance (VM ou poste distant en Workgroup) :
          1. Validation préalable de la connectivité réseau (Ping).
          2. Gestion robuste des identifiants locaux (auto-qualification du compte ex: WINDOWS-VM\admin ou .\admin).
          3. Authentification explicite Negotiate (NTLM) via Invoke-Command pour éviter l'erreur 0x8009030e.
          4. Récupération résiliente des KB avec fallback CIM si Get-HotFix rencontre une anomalie.
      - En cas d'inaccessibilité (Ping KO ou erreur WinRM) : statut = INACCESSIBLE, KBManquantes = N/A.
      - Comparaison des KB installées aux KB requises : statut = CONFORME ou NON CONFORME.
    Exporte le rapport dans un fichier CSV et affiche un tableau récapitulatif ainsi que le taux global de conformité.

.PARAMETER InventoryFile
    Chemin vers le fichier d'inventaire (ex: computers.txt).

.PARAMETER RequiredFile
    Chemin vers le fichier contenant les KB requises (ex: required-patches.txt).

.PARAMETER OutputFile
    Chemin du fichier CSV de sortie (ex: ComplianceReport.csv).

.PARAMETER Credential
    Identifiants d'administration pour l'accès WinRM distant (comptes locaux en Workgroup).
#>

param (
    [string]$InventoryFile = "computers.txt",
    [string]$RequiredFile  = "required-patches.txt",
    [string]$OutputFile    = "ComplianceReport.csv",
    [pscredential]$Credential
)

# 1. Vérification des fichiers prérequis
if (-not (Test-Path -Path $InventoryFile)) {
    Write-Error "Fichier d'inventaire introuvable : $InventoryFile"
    exit 1
}

if (-not (Test-Path -Path $RequiredFile)) {
    Write-Error "Fichier des correctifs requis introuvable : $RequiredFile"
    exit 1
}

# 2. Lecture des KB requises (en ignorant les lignes vides et normalisation en majuscules)
$requiredKBs = @(
    Get-Content -Path $RequiredFile |
    Where-Object { $_ -match '\S' } |
    ForEach-Object { $_.Trim().ToUpper() } |
    Select-Object -Unique
)

Write-Host "Nombre de correctifs obligatoires chargés : $($requiredKBs.Count) ($($requiredKBs -join ', '))" -ForegroundColor Cyan

# 3. Lecture du fichier d'inventaire des machines
$computers = Import-Csv -Path $InventoryFile -Delimiter ';' -Header "Nom", "IP" |
    Where-Object { $_.Nom -and $_.IP -and $_.Nom -ne "Nom" }

# Détection de machines distantes dans l'inventaire
$remoteComputers = @($computers | Where-Object {
    $_.IP -notin @("localhost", "127.0.0.1", "::1") -and $_.Nom -ne $env:COMPUTERNAME
})

# Demande interactive des identifiants si des machines distantes existent et qu'aucun credential n'a été passé
if ($remoteComputers.Count -gt 0 -and -not $Credential) {
    if ([Environment]::UserInteractive) {
        Write-Host "`nDes machines distantes nécessitent une authentification administrative WinRM." -ForegroundColor Yellow
        $Credential = Get-Credential -Message "Entrez les identifiants pour l'accès aux machines distantes (ex: WINDOWS-VM\admin ou admin) :"
    }
    else {
        Write-Warning "Aucun identifiant -Credential fourni pour les machines distantes en mode non interactif."
    }
}

$complianceResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$now = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")

# Bloc d'exécution standard et résilient pour la récupération des HotFix
$collectHotFixes = {
    try {
        $hf = Get-HotFix -ErrorAction Stop
        if ($hf) {
            $hf | Select-Object -ExpandProperty HotFixID
        }
    }
    catch {
        # Fallback via la classe CIM standard si Get-HotFix échoue
        Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty HotFixID
    }
}

# 4. Traitement de chaque machine de l'inventaire
foreach ($pc in $computers) {
    Write-Host "Contrôle de conformité sur $($pc.Nom) ($($pc.IP))..." -ForegroundColor Cyan

    $isLocal = ($pc.IP -in @("localhost", "127.0.0.1", "::1") -or $pc.Nom -eq $env:COMPUTERNAME)

    if ($isLocal) {
        # --- MACHINE LOCALE ---
        # Exécution directe locale (évite l'erreur 0x8009030e liée aux boucles d'authentification locales en Workgroup)
        try {
            $rawInstalled = & $collectHotFixes
            $installed = @($rawInstalled) | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim().ToUpper() }

            $missing = @($requiredKBs | Where-Object { $_ -notin $installed })
            $statut = if ($missing.Count -eq 0) { "CONFORME" } else { "NON CONFORME" }
            $kbManquantes = if ($missing.Count -gt 0) { $missing -join ", " } else { "Aucune" }

            $complianceResults.Add([PSCustomObject]@{
                Poste        = $pc.Nom
                AdresseIP    = $pc.IP
                NbRequises   = $requiredKBs.Count
                NbManquantes = $missing.Count
                KBManquantes = $kbManquantes
                Statut       = $statut
                DateControle = $now
            })
        }
        catch {
            Write-Warning "Erreur locale lors du contrôle sur $($pc.Nom) : $_"
            $complianceResults.Add([PSCustomObject]@{
                Poste        = $pc.Nom
                AdresseIP    = $pc.IP
                NbRequises   = $requiredKBs.Count
                NbManquantes = "N/A"
                KBManquantes = "N/A"
                Statut       = "INACCESSIBLE"
                DateControle = $now
            })
        }
    }
    else {
        # --- MACHINE DISTANTE ---
        # 1. Test ping réseau préalable pour éliminer rapidement les hôtes hors ligne sans timeout WinRM
        $pingOk = Test-Connection -ComputerName $pc.IP -Count 1 -Quiet
        if (-not $pingOk) {
            Write-Warning "Machine injoignable au ping : $($pc.Nom) ($($pc.IP))"
            $complianceResults.Add([PSCustomObject]@{
                Poste        = $pc.Nom
                AdresseIP    = $pc.IP
                NbRequises   = $requiredKBs.Count
                NbManquantes = "N/A"
                KBManquantes = "N/A"
                Statut       = "INACCESSIBLE"
                DateControle = $now
            })
            continue
        }

        # 2. Adaptation des identifiants pour le mode Workgroup :
        # Si le nom d'utilisateur est fourni sans domaine/machine (ex: "admin"),
        # on qualifie avec le nom du poste distant (ex: "WINDOWS-VM\admin")
        # afin d'éviter que le SSP local cherche un ticket Kerberos ou une session locale (erreur 0x8009030e).
        $targetCred = $Credential
        if ($Credential -and ($Credential.UserName -notmatch '\\')) {
            $userOnly = $Credential.UserName
            $targetCred = New-Object System.Management.Automation.PSCredential("$($pc.Nom)\$userOnly", $Credential.Password)
        }

        # 3. Exécution distante avec Invoke-Command et authentification Negotiate (NTLM)
        $rawInstalled = $null
        $remoteSuccess = $false

        try {
            $invokeParams = @{
                ComputerName   = $pc.IP
                Authentication = "Negotiate"
                ErrorAction    = "Stop"
                ScriptBlock    = $collectHotFixes
            }
            if ($targetCred) {
                $invokeParams["Credential"] = $targetCred
            }

            $rawInstalled = Invoke-Command @invokeParams
            $remoteSuccess = $true
        }
        catch {
            # Si échec avec nom qualifié, tentative de repli avec les identifiants d'origine
            if ($targetCred -ne $Credential -and $Credential) {
                try {
                    $fallbackParams = @{
                        ComputerName   = $pc.IP
                        Authentication = "Negotiate"
                        Credential     = $Credential
                        ErrorAction    = "Stop"
                        ScriptBlock    = $collectHotFixes
                    }
                    $rawInstalled = Invoke-Command @fallbackParams
                    $remoteSuccess = $true
                }
                catch {
                    Write-Warning "Erreur WinRM sur $($pc.Nom) ($($pc.IP)) : $_"
                }
            }
            else {
                Write-Warning "Erreur WinRM sur $($pc.Nom) ($($pc.IP)) : $_"
            }
        }

        if ($remoteSuccess) {
            $installed = @($rawInstalled) | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim().ToUpper() }
            $missing = @($requiredKBs | Where-Object { $_ -notin $installed })
            $statut = if ($missing.Count -eq 0) { "CONFORME" } else { "NON CONFORME" }
            $kbManquantes = if ($missing.Count -gt 0) { $missing -join ", " } else { "Aucune" }

            $complianceResults.Add([PSCustomObject]@{
                Poste        = $pc.Nom
                AdresseIP    = $pc.IP
                NbRequises   = $requiredKBs.Count
                NbManquantes = $missing.Count
                KBManquantes = $kbManquantes
                Statut       = $statut
                DateControle = $now
            })
        }
        else {
            $complianceResults.Add([PSCustomObject]@{
                Poste        = $pc.Nom
                AdresseIP    = $pc.IP
                NbRequises   = $requiredKBs.Count
                NbManquantes = "N/A"
                KBManquantes = "N/A"
                Statut       = "INACCESSIBLE"
                DateControle = $now
            })
        }
    }
}

# 5. Export des résultats dans le fichier CSV
$complianceResults | Export-Csv -Path $OutputFile -Delimiter ';' -Encoding UTF8 -NoTypeInformation
Write-Host "`nRapport de conformité exporté avec succès dans : $OutputFile" -ForegroundColor Green

# 6. Affichage du tableau récapitulatif dans la console
Write-Host "`n--- Tableau récapitulatif de conformité ---" -ForegroundColor Yellow
$complianceResults | Format-Table -Property Poste, AdresseIP, NbRequises, NbManquantes, KBManquantes, Statut -AutoSize

# 7. Calcul et affichage du taux global de conformité (sur les machines accessibles)
$evaluable = @($complianceResults | Where-Object { $_.Statut -ne "INACCESSIBLE" })
if ($evaluable.Count -gt 0) {
    $conformes = @($evaluable | Where-Object { $_.Statut -eq "CONFORME" }).Count
    $taux = [math]::Round(($conformes / $evaluable.Count) * 100, 2)
    Write-Host "Taux global de conformité (sur les machines accessibles) : $taux % ($conformes / $($evaluable.Count) conforme(s))`n" -ForegroundColor Green
}
else {
    Write-Host "Aucune machine accessible pour évaluer le taux de conformité.`n" -ForegroundColor Yellow
}