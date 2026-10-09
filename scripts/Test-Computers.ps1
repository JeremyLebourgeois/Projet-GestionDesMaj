# scripts/Test-Computers.ps1
param (
    [string]$FilePath = "computers.txt"
)

if (-not (Test-Path $FilePath)) {
    Write-Error "Fichier d'inventaire introuvable : $FilePath"
    exit 1
}

# Importation du fichier avec séparateur ';'
$computers = Import-Csv -Path $FilePath -Delimiter ';' -Header "Nom", "IP"

$results = foreach ($pc in $computers) {
    # Test de connectivité ICMP (ping rapide)
    $pingOk = Test-Connection -ComputerName $pc.IP -Count 1 -Quiet

    $status = if ($pingOk) { "Accessible" } else { "Inaccessible" }

    [PSCustomObject]@{
        Nom   = $pc.Nom
        IP    = $pc.IP
        Etat  = $status
    }
}

# Affichage du résultat dans la console
$results | Format-Table -AutoSize