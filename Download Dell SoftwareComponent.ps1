<#
    Author:  Michael 
    Version: 1.0
    Created: 2022-10-21

    Use this script if you want to download single drivers for Dell computers, rather than the full Driver Package. 
    In cases for OSD over CMG, it is useful to ensure the network drivers are available once the full OS starts.
#>

# system variables
If (Test-Path -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlset\Control\MiniNT -ErrorAction:SilentlyContinue) {
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $rootFolder = "$($TSEnv.Value("OSDTargetSystemDrive"))\Temp\DellDrivers"
} Else {
    $rootFolder = "$($env:SystemRoot)\Temp\DellDrivers"
}

$systemSku = (Get-WmiObject -Namespace root\WMI -Class MS_SystemInformation).SystemSKU
$driverCategory = "Serial ATA|Network" # Delimiter: "|"
$targetOs = "Windows 11"

# create root folder for all files required 
New-Item -Path $rootFolder -ItemType Directory -ErrorAction:SilentlyContinue | Out-Null


Write-Output "`n`t --- CatalogIndexPC ---"
#region

# declare variable for next section
$CatalogIndexPCUrl = "https://downloads.dell.com/catalog/CatalogIndexPC.cab"
$CatalogIndexPCCab = "$rootFolder\CatalogIndexPC.cab"
$CatalogIndexPCXml = $CatalogIndexPCCab -replace ("cab","xml")

# download index cab-file
Write-Output "$(Get-Date) :: Download: $CatalogIndexPCUrl"
If (Test-Path $CatalogIndexPCCab -ErrorAction:SilentlyContinue) {Remove-Item -Path $CatalogIndexPCCab -Force}
Invoke-RestMethod -Uri $CatalogIndexPCUrl -OutFile $CatalogIndexPCCab -UseBasicParsing

# expand index cab-file
Write-Output "$(Get-Date) :: Expand: $CatalogIndexPCCab"
If (Test-Path $CatalogIndexPCXml -ErrorAction:SilentlyContinue) {Remove-Item -Path $CatalogIndexPCXml -Force}
$Expand = EXPAND $CatalogIndexPCCab $CatalogIndexPCXml

# filter index cab-file for the model required  
Write-Output "$(Get-Date) :: Load: $CatalogIndexPCXml"
[xml]$XmlContent = Get-Content $CatalogIndexPCXml -Verbose
$CatalogIndexPC = $XmlContent.ManifestIndex.GroupManifest | Where-Object {$_.SupportedSystems.Brand.Model.systemID -eq $systemSku }
#endregion


Write-Output "`n`t --- InventoryComponent ---"
#region

# declare variable for next section
$InventoryComponentUrl = "https://downloads.dell.com/$($CatalogIndexPC.ManifestInformation.path)"
$InventoryComponentCab = "$rootFolder\$($CatalogIndexPC.ManifestInformation.path.Split("/") | Where-Object {$_ -match ".cab"})"
$InventoryComponentXml = $InventoryComponentCab -replace ("cab","xml")

# download model specific cab-file
Write-Output "$(Get-Date) :: Download: $InventoryComponentUrl"
If (Test-Path $InventoryComponentCab -ErrorAction:SilentlyContinue) {Remove-Item -Path $InventoryComponentCab -Force}
Invoke-RestMethod -Uri $InventoryComponentUrl -OutFile $InventoryComponentCab -UseBasicParsing

# expand model specific cab-file 
Write-Output "$(Get-Date) :: Expand: $InventoryComponentXml"
If (Test-Path $InventoryComponentXml -ErrorAction:SilentlyContinue) {Remove-Item -Path $InventoryComponentXml -Force}
$Expand = EXPAND $InventoryComponentCab $InventoryComponentXml

# filter model specific cab-file for drivers required
Write-Output "$(Get-Date) :: Load: $InventoryComponentXml"
[xml]$XmlContent = Get-Content $InventoryComponentXml -Verbose
$InventoryComponent = $XmlContent.Manifest.SoftwareComponent | Where-Object { $_.ComponentType.value -eq "DRVR" -and $_.Category.Display.'#cdata-section' -match $driverCategory -and $_.SupportedOperatingSystems.OperatingSystem.Display.'#cdata-section' -eq $targetOs }
#endregion


Write-Output "`n`t --- SoftwareComponent ---"
#region


# declare variable for next section
$SoftwareComponentExtract = "$rootFolder\$($targetOs -Replace(' '))"
If (Test-Path $SoftwareComponentExtract -ErrorAction:SilentlyContinue) {Remove-Item -Path $SoftwareComponentExtract -Force -Recurse}
New-Item -Path $SoftwareComponentExtract -ItemType Directory -ErrorAction:SilentlyContinue | Out-Null

ForEach ($SoftwareComponent In $InventoryComponent) {
    
    # declare variable for next section
    $SoftwareComponentUrl = "https://downloads.dell.com/$($SoftwareComponent.path)"
    $SoftwareComponentExe = "$rootFolder\$($SoftwareComponent.path.Split("/") | Where-Object {$_ -match ".exe"})"

    # download driver exe-file
    Write-Output "$(Get-Date) :: Download: $SoftwareComponentUrl"
    If (Test-Path $SoftwareComponentExe -ErrorAction:SilentlyContinue) {Remove-Item -Path $SoftwareComponentExe -Force}
    Invoke-RestMethod -Uri $SoftwareComponentUrl -OutFile $SoftwareComponentExe -UseBasicParsing

    If (($SoftwareComponent.Cryptography.Hash | Where-Object {$_.algorithm -eq "MD5"}).'#text' -eq (Get-FileHash $SoftwareComponentExe -Algorithm MD5).Hash) {
        Try {
            # extract driver exe-file
            Write-Output "$(Get-Date) :: Extract: $SoftwareComponentUrl"
            Start-Process $SoftwareComponentExe "/s /e=""$SoftwareComponentExtract\$($SoftwareComponent.packageID)""" -Wait
        } Catch {}
    }
}
#endregion

If ($TSEnv) {
    $TSEnv.value('DRIVERS') = $SoftwareComponentExtract
}