param (
    [string]$InventoryFile = "computers.txt",
    [string]$RequiredFile  = "required-patches.txt",
    [string]$OutputFile    = "ComplianceReport.csv",
    [pscredential]$Credential
)

if (-not $Credential) {
    $Credential = Get-Credential
}

if (-not (Test-Path $RequiredFile)) {
    Write-Error "Fichier des KB requises introuvable : $RequiredFile"
    exit 1
}

$requiredKBs = Get-Content $RequiredFile | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim().ToUpper() }
$computers = Import-Csv -Path $InventoryFile -Delimiter ';' -Header "Nom", "IP"

$complianceResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$now = (Get-Date).ToString("dd/MM/yyyy HH:mm:ss")

foreach ($pc in $computers) {
    $pingOk = Test-Connection -ComputerName $pc.IP -Count 1 -Quiet
    if (-not $pingOk) {
        $complianceResults.Add([PSCustomObject]@{
            Poste           = $pc.Nom
            AdresseIP       = $pc.IP
            KBRequises      = $requiredKBs.Count
            KBManquantes    = "N/A"
            ListeManquantes = "N/A"
            Etat            = "INACCESSIBLE"
            DateControle    = $now
        })
        continue
    }

    try {
        $installed = Invoke-Command -ComputerName $pc.IP -Credential $Credential -ErrorAction Stop -ScriptBlock {
            (Get-HotFix).HotFixID
        } | ForEach-Object { $_.ToUpper() }

        $missing = $requiredKBs | Where-Object { $_ -notin $installed }

        $status = if ($missing.Count -eq 0) { "CONFORME" } else { "NON CONFORME" }

        $complianceResults.Add([PSCustomObject]@{
            Poste           = $pc.Nom
            AdresseIP       = $pc.IP
            KBRequises      = $requiredKBs.Count
            KBManquantes    = $missing.Count
            ListeManquantes = ($missing -join ", ")
            Etat            = $status
            DateControle    = $now
        })
    }
    catch {
        $complianceResults.Add([PSCustomObject]@{
            Poste           = $pc.Nom
            AdresseIP       = $pc.IP
            KBRequises      = $requiredKBs.Count
            KBManquantes    = "N/A"
            ListeManquantes = "Erreur WinRM"
            Etat            = "INACCESSIBLE"
            DateControle    = $now
        })
    }
}

# Export CSV
$complianceResults | Export-Csv -Path $OutputFile -NoTypeInformation -Delimiter ';' -Encoding UTF8
$complianceResults | Format-Table Poste, KBRequises, KBManquantes, ListeManquantes, Etat -AutoSize

# Calcul du taux global (hors inaccessibles)
$evaluable = $complianceResults | Where-Object { $_.Etat -ne "INACCESSIBLE" }
if ($evaluable.Count -gt 0) {
    $conformes = ($evaluable | Where-Object { $_.Etat -eq "CONFORME" }).Count
    $taux = [math]::Round(($conformes / $evaluable.Count) * 100, 2)
    Write-Host "Taux global de conformité (postes accessibles) : $taux %" -ForegroundColor Green
}