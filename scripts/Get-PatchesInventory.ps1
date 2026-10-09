param (
    [string]$InventoryFile = "computers.txt",
    [string]$OutputFile    = "Patches Inventory.csv",
    [pscredential]$Credential
)

if (-not $Credential) {
    $Credential = Get-Credential
}

if (-not (Test-Path $InventoryFile)) {
    Write-Error "Fichier $InventoryFile introuvable."
    exit 1
}

$computers = Import-Csv -Path $InventoryFile -Delimiter ';' -Header "Nom", "IP"
$allPatches = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($pc in $computers) {
    Write-Host "Collecte des correctifs sur $($pc.Nom) ($($pc.IP))..." -ForegroundColor Cyan
    
    $pingOk = Test-Connection -ComputerName $pc.IP -Count 1 -Quiet
    if (-not $pingOk) {
        Write-Warning "$($pc.Nom) est inaccessible (ping)."
        continue
    }

    try {
        $patches = Invoke-Command -ComputerName $pc.IP -Credential $Credential -ErrorAction Stop -ScriptBlock {
            Get-HotFix | Select-Object HotFixID, Description, InstalledOn, InstalledBy
        }

        foreach ($patch in $patches) {
            $allPatches.Add([PSCustomObject]@{
                Poste            = $pc.Nom
                AdresseIP        = $pc.IP
                KB               = $patch.HotFixID
                Description      = $patch.Description
                DateInstallation = if ($patch.InstalledOn) { $patch.InstalledOn.ToString("yyyy-MM-dd") } else { "Inconnue" }
                InstallePar      = $patch.InstalledBy
            })
        }
    }
    catch {
        Write-Warning "Impossible de collecter les KB sur $($pc.Nom) : $_"
    }
}

# Tri par poste puis par date d'installation décroissante
$sortedPatches = $allPatches | Sort-Object Poste, DateInstallation -Descending

# Export CSV
$sortedPatches | Export-Csv -Path $OutputFile -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host "Inventaire des correctifs exporté dans : $OutputFile" -ForegroundColor Green

# Statistiques par machine
$allPatches | Group-Object Poste | ForEach-Object {
    $last = $_.Group | Sort-Object DateInstallation -Descending | Select-Object -First 1
    [PSCustomObject]@{
        Poste         = $_.Name
        TotalPatches  = $_.Count
        DernierKB     = $last.KB
        DateDernierKB = $last.DateInstallation
    }
} | Format-Table -AutoSize