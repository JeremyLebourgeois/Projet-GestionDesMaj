param (
    [string]$InventoryFile = "computers.txt",
    [string]$OutputFile    = "ParkInventory.csv",
    [pscredential]$Credential
)

if (-not (Test-Path $InventoryFile)) {
    Write-Error "Fichier d'inventaire introuvable : $InventoryFile"
    exit 1
}

$computers = Import-Csv -Path $InventoryFile -Delimiter ';' -Header "Nom", "IP"
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$collectBlock = {
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    $wu   = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $hotfixes = Get-HotFix -ErrorAction SilentlyContinue
    $lastPatch = ($hotfixes | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn

    [PSCustomObject]@{
        Modele           = $cs.Model
        VersionBios      = $bios.SMBIOSBIOSVersion
        Windows          = $os.Caption
        Architecture     = $os.OSArchitecture
        DernierDemarrage = $os.LastBootUpTime.ToString("dd/MM/yyyy HH:mm")
        RAM_Go           = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        DisqueLibre_Go   = [math]::Round($disk.FreeSpace / 1GB, 2)
        DerniereMaj      = if ($lastPatch) { $lastPatch.ToString("dd/MM/yyyy") } else { "Aucune" }
        NbMajInstallees  = if ($hotfixes) { ($hotfixes | Measure-Object).Count } else { 0 }
        WindowsUpdate    = if ($wu) { $wu.Status.ToString() } else { "Introuvable" }
    }
}

foreach ($pc in $computers) {
    Write-Host "Traitement de $($pc.Nom) ($($pc.IP))..." -ForegroundColor Cyan

    $isLocal = ($pc.IP -in @("localhost", "127.0.0.1") -or $pc.Nom -eq $env:COMPUTERNAME)

    # 1. Traitement machine locale
    if ($isLocal) {
        try {
            $data = & $collectBlock
            $results.Add([PSCustomObject]@{
                Poste           = $pc.Nom
                AdresseIP       = $pc.IP
                Modele          = $data.Modele
                VersionBios     = $data.VersionBios
                Windows         = $data.Windows
                Architecture    = $data.Architecture
                DernierDemarrage = $data.DernierDemarrage
                RAM_Go          = $data.RAM_Go
                DisqueLibre_Go  = $data.DisqueLibre_Go
                DerniereMaj     = $data.DerniereMaj
                NbMajInstallees = $data.NbMajInstallees
                WindowsUpdate   = $data.WindowsUpdate
                Etat            = "Accessible"
                Erreur          = "Aucune"
            })
        }
        catch {
            Write-Warning "Erreur locale sur $($pc.Nom) : $_"
            $results.Add([PSCustomObject]@{
                Poste           = $pc.Nom
                AdresseIP       = $pc.IP
                Modele          = "N/A"
                VersionBios     = "N/A"
                Windows         = "N/A"
                Architecture    = "N/A"
                DernierDemarrage = "N/A"
                RAM_Go          = "N/A"
                DisqueLibre_Go  = "N/A"
                DerniereMaj     = "N/A"
                NbMajInstallees = "N/A"
                WindowsUpdate   = "N/A"
                Etat            = "Inaccessible"
                Erreur          = $_.Exception.Message
            })
        }
        continue
    }

    # 2. Test ping prealable pour les machines distantes
    $pingOk = Test-Connection -ComputerName $pc.IP -Count 1 -Quiet
    if (-not $pingOk) {
        Write-Warning "$($pc.Nom) est injoignable (ping)."
        $results.Add([PSCustomObject]@{
            Poste           = $pc.Nom
            AdresseIP       = $pc.IP
            Modele          = "N/A"
            VersionBios     = "N/A"
            Windows         = "N/A"
            Architecture    = "N/A"
            DernierDemarrage = "N/A"
            RAM_Go          = "N/A"
            DisqueLibre_Go  = "N/A"
            DerniereMaj     = "N/A"
            NbMajInstallees = "N/A"
            WindowsUpdate   = "N/A"
            Etat            = "Inaccessible"
            Erreur          = "Hote non joignable (ping)"
        })
        continue
    }

    # 3. Collecte distante via WinRM
    try {
        $invokeParams = @{
            ComputerName = $pc.IP
            ErrorAction  = "Stop"
            ScriptBlock  = $collectBlock
        }
        if ($Credential) {
            $invokeParams["Credential"] = $Credential
        }

        $data = Invoke-Command @invokeParams

        $results.Add([PSCustomObject]@{
            Poste           = $pc.Nom
            AdresseIP       = $pc.IP
            Modele          = $data.Modele
            VersionBios     = $data.VersionBios
            Windows         = $data.Windows
            Architecture    = $data.Architecture
            DernierDemarrage = $data.DernierDemarrage
            RAM_Go          = $data.RAM_Go
            DisqueLibre_Go  = $data.DisqueLibre_Go
            DerniereMaj     = $data.DerniereMaj
            NbMajInstallees = $data.NbMajInstallees
            WindowsUpdate   = $data.WindowsUpdate
            Etat            = "Accessible"
            Erreur          = "Aucune"
        })
    }
    catch {
        Write-Warning "Erreur WinRM sur $($pc.Nom) : $_"
        $results.Add([PSCustomObject]@{
            Poste           = $pc.Nom
            AdresseIP       = $pc.IP
            Modele          = "N/A"
            VersionBios     = "N/A"
            Windows         = "N/A"
            Architecture    = "N/A"
            DernierDemarrage = "N/A"
            RAM_Go          = "N/A"
            DisqueLibre_Go  = "N/A"
            DerniereMaj     = "N/A"
            NbMajInstallees = "N/A"
            WindowsUpdate   = "N/A"
            Etat            = "Inaccessible"
            Erreur          = $_.Exception.Message
        })
    }
}

$results | Format-Table Poste, AdresseIP, Windows, RAM_Go, DisqueLibre_Go, WindowsUpdate, Etat -AutoSize
$results | Export-Csv -Path $OutputFile -NoTypeInformation -Delimiter ';' -Encoding UTF8
Write-Host "`nInventaire exporte dans : $OutputFile" -ForegroundColor Green
