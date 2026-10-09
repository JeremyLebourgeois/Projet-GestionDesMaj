param (
    [string]$InventoryFile = "computers.txt",
    [string]$OutputFile    = "Patches Inventory.csv",
    [pscredential]$Credential
)

if (-not (Test-Path $InventoryFile)) {
    Write-Error "Fichier d'inventaire introuvable : $InventoryFile"
    exit 1
}

$computers = Import-Csv -Path $InventoryFile -Delimiter ';' -Header "Nom", "IP"
$allPatches = [System.Collections.Generic.List[PSCustomObject]]::new()

$patchBlock = {
    Get-HotFix | Select-Object HotFixID, Description, InstalledOn, InstalledBy
}

foreach ($pc in $computers) {
    Write-Host "Collecte des correctifs sur $($pc.Nom) ($($pc.IP))..." -ForegroundColor Cyan

    $isLocal = ($pc.IP -in @("localhost", "127.0.0.1") -or $pc.Nom -eq $env:COMPUTERNAME)

    if ($isLocal) {
        try {
            $patches = & $patchBlock
            foreach ($p in $patches) {
                $dateStr = if ($p.InstalledOn) { (Get-Date $p.InstalledOn).ToString("yyyy-MM-dd") } else { "Inconnue" }
                $allPatches.Add([PSCustomObject]@{
                    Poste            = $pc.Nom
                    AdresseIP        = $pc.IP
                    KB               = $p.HotFixID
                    Description      = $p.Description
                    DateInstallation = $dateStr
                    InstallePar      = $p.InstalledBy
                })
            }
        }
        catch {
            Write-Warning "Erreur locale lors de la collecte sur $($pc.Nom) : $_"
        }
        continue
    }

    $pingOk = Test-Connection -ComputerName $pc.IP -Count 1 -Quiet
    if (-not $pingOk) {
        Write-Warning "$($pc.Nom) est injoignable (ping)."
        continue
    }

    try {
        $invokeParams = @{
            ComputerName = $pc.IP
            ErrorAction  = "Stop"
            ScriptBlock  = $patchBlock
        }
        if ($Credential) {
            $invokeParams["Credential"] = $Credential
        }

        $patches = Invoke-Command @invokeParams

        foreach ($p in $patches) {
            $dateStr = if ($p.InstalledOn) { (Get-Date $p.InstalledOn).ToString("yyyy-MM-dd") } else { "Inconnue" }
            $allPatches.Add([PSCustomObject]@{
                Poste            = $pc.Nom
                AdresseIP        = $pc.IP
                KB               = $p.HotFixID
                Description      = $p.Description
                DateInstallation = $dateStr
                InstallePar      = $p.InstalledBy
            })
        }
    }
    catch {
        Write-Warning "Erreur WinRM sur $($pc.Nom) : $_"
    }
}

# Tri par Poste puis par DateInstallation décroissante
$sortedPatches = $allPatches | Sort-Object Poste, DateInstallation -Descending

# Exportation en CSV
$sortedPatches | Export-Csv -Path $OutputFile -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host "`nInventaire des correctifs exporté avec succès dans : $OutputFile" -ForegroundColor Green

# Synthèse dans la console
Write-Host "`n--- Synthèse des correctifs par machine ---" -ForegroundColor Yellow
$allPatches | Group-Object Poste | ForEach-Object {
    $last = $_.Group | Sort-Object DateInstallation -Descending | Select-Object -First 1
    [PSCustomObject]@{
        Poste         = $_.Name
        TotalPatches  = $_.Count
        DernierKB     = $last.KB
        DateDernierKB = $last.DateInstallation
    }
} | Format-Table -AutoSize