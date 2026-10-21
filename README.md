# Système de Gestion et d'Audit des Mises à Jour (PowerShell)

Projet académique réalisé dans le cadre du module **Sécurité des Systèmes** à l'**EFREI Paris** (Semestre 7).

**Auteur :** Jérémy Lebourgeois  
**Dépôt GitHub :** [https://github.com/JeremyLebourgeois/Projet-GestionDesMaj](https://github.com/JeremyLebourgeois/Projet-GestionDesMaj)

---

## 📌 Présentation du Projet

Ce projet a pour objectif de concevoir une solution automatisée en PowerShell pour administrer, inventorier et auditer l'état des correctifs de sécurité (KB) sur un parc informatique Windows hétérogène (machine locale, machine virtuelle supervisée et machines hors ligne) à travers **PowerShell Remoting (WinRM)**.

Le système permet de :
1. Tester la connectivité réseau et valider les liaisons WinRM.
2. Réaliser un inventaire matériel et système complet du parc.
3. Recenser l'intégralité des correctifs de sécurité installés.
4. Auditer la conformité des machines par rapport à une liste de correctifs obligatoires (*baseline* de sécurité).
5. Exporter les résultats aux formats CSV normalisés et restituer des synthèses dans la console.

---

## 📂 Structure du Répertoire

```text
Projet-GestionDesMaj/
├── scripts/
│   ├── Test-Computers.ps1        # Test de connectivité ICMP (Ping)
│   ├── Get-ParkInventory.ps1     # Inventaire matériel et système (Partie 2)
│   ├── Get-PatchesInventory.ps1  # Inventaire des correctifs installés (Partie 3)
│   └── Test-Compliance.ps1       # Contrôle de conformité et calcul du taux (Partie 4)
│
├── computers.txt                 # Inventaire des cibles (Format: Nom;IP)
├── required-patches.txt          # Liste des correctifs obligatoires (KB)
│
├── ParkInventory.csv             # Export CSV de l'inventaire matériel
├── Patches Inventory.csv         # Export CSV des correctifs recensés
├── ComplianceReport.csv          # Export CSV du rapport de conformité
│
├── img/                          # Captures d'écran d'exécution et de validation
├── RAPPORT.md                    # Compte-rendu technique complet et réponses théoriques
└── README.md                     # Documentation synthétique du projet
```

---

## 🚀 Utilisation Rapide

### 1. Prérequis
- **PowerShell 5.1** ou supérieur avec droits d'administration.
- **WinRM activé** sur les machines cibles :
  ```powershell
  Enable-PSRemoting -Force
  ```
- Configuration de la liste de confiance sur le poste d'administration en Workgroup :
  ```powershell
  Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.56.101" -Force
  ```

### 2. Exécution des scripts

#### A. Test de connectivité rapide
```powershell
.\scripts\Test-Computers.ps1
```

#### B. Inventaire matériel et système
```powershell
.\scripts\Get-ParkInventory.ps1 -InventoryFile "computers.txt" -OutputFile "ParkInventory.csv"
```

#### C. Recensement des correctifs installés
```powershell
.\scripts\Get-PatchesInventory.ps1 -InventoryFile "computers.txt" -OutputFile "Patches Inventory.csv"
```

#### D. Contrôle de conformité (Partie 4)
```powershell
# Définition des identifiants administratifs de la machine distante
$cred = Get-Credential

# Lancement de l'audit de conformité
.\scripts\Test-Compliance.ps1 -InventoryFile "computers.txt" -RequiredFile "required-patches.txt" -OutputFile "ComplianceReport.csv" -Credential $cred
```

---

## 📊 Résultat du Contrôle de Conformité

Exemple de sortie console générée par `Test-Compliance.ps1` :

```text
--- Tableau récapitulatif de conformité ---

Poste           AdresseIP      NbRequises NbManquantes KBManquantes                    Statut      
-----           ---------      ---------- ------------ ------------                    ------      
MSI             localhost               3            3 KB5014032, KB5129195, KB9999999 NON CONFORME
WINDOWS-VM      192.168.56.101          3            2 KB5129195, KB9999999            NON CONFORME
PC-Inaccessible 192.168.1.250           3          N/A N/A                             INACCESSIBLE

Taux global de conformité (sur les machines accessibles) : 0 % (0 / 2 conforme(s))
```

---

## 📖 Documentation Complète

Pour une analyse détaillée des choix techniques, la résolution des incidents d'authentification en Workgroup (code `0x8009030e`, clé `LocalAccountTokenFilterPolicy`) et les réponses aux questions théoriques, consultez le fichier [RAPPORT.md](RAPPORT.md).