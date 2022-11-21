<#
    Author:  Michael 
    Version: 1.4
    Created: 2022-11-18

    Download the latest Dell driver components as needed. It doesn't download an entire Driver Package, which is huge in size. 
    Only download the categories you specify to keep the downloaded files minimal.
#>

# system variables
If (Test-Path -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlset\Control\MiniNT -ErrorAction:SilentlyContinue) {
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $rootFolder = "$($TSEnv.Value("OSDTargetSystemDrive"))\Windows\Temp\DellDrivers"
} Else {
    $rootFolder = "$($env:SystemRoot)\Temp\DellDrivers"
}

$systemModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
#$systemModel = "Precision 5470"
$driverCategory = "Serial ATA|Network|Camera" # Delimiter: "|"
$targetOs = "Windows 11"
$targetArch = "x64"

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
$CatalogIndexPC = $XmlContent.ManifestIndex.GroupManifest | Where-Object {$_.SupportedSystems.Brand.Model.Display.'#cdata-section' -eq $systemModel }
If (-not $CatalogIndexPC) { Exit 1 }
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
$InventoryComponent = $XmlContent.Manifest.SoftwareComponent | Where-Object { $_.Category.Display.'#cdata-section' -match $driverCategory -and $_.SupportedOperatingSystems.OperatingSystem.Display.'#cdata-section' -eq $targetOs }
If (-not $InventoryComponent) { Exit 1 }

# only get latest drivers
$InventoryComponentLatest = ($InventoryComponent.Name.Display.'#cdata-section' | Group-Object) | ForEach-Object {
    $Group = $_
    $InventoryComponent | Where-Object {$_.Name.Display.'#cdata-section' -eq $Group.Name } | Sort-Object dellVersion -Descending | Select-Object -First 1
}
#endregion


Write-Output "`n`t --- SoftwareComponent ---"
#region

# declare variable for next section
$SoftwareComponentExtract = ("$rootFolder\$($systemModel)_$($targetOs)") -Replace(' ')
If (Test-Path $SoftwareComponentExtract -ErrorAction:SilentlyContinue) {Remove-Item -Path $SoftwareComponentExtract -Force -Recurse}
New-Item -Path $SoftwareComponentExtract -ItemType Directory -ErrorAction:SilentlyContinue | Out-Null

ForEach ($SoftwareComponent In $InventoryComponentLatest) {
    
    # declare variable for next section
    $SoftwareComponentUrl = "https://downloads.dell.com/$($SoftwareComponent.path)"
    $SoftwareComponentExe = "$rootFolder\$($SoftwareComponent.path.Split("/") | Where-Object {$_ -match ".exe"})"

    # download driver exe-file
    Write-Output "$(Get-Date) :: Download: $SoftwareComponentUrl; Size: $([math]::round($SoftwareComponent.size /1Mb,2))Mb"
    If (Test-Path $SoftwareComponentExe -ErrorAction:SilentlyContinue) {Remove-Item -Path $SoftwareComponentExe -Force}
    Invoke-RestMethod -Uri $SoftwareComponentUrl -OutFile $SoftwareComponentExe -UseBasicParsing
    
    If (($SoftwareComponent.Cryptography.Hash | Where-Object {$_.algorithm -eq "MD5"}).'#text' -eq (Get-FileHash $SoftwareComponentExe -Algorithm MD5).Hash) {
        Try {
            # extract driver exe-file
            Write-Output "$(Get-Date) :: Extract: $SoftwareComponentExe"
            Start-Process $SoftwareComponentExe "/s /e=""$SoftwareComponentExtract\$($SoftwareComponent.packageID)""" -Wait
            
            # remove non-F6 drivers (in Windows XP you had to tap the F6 key to inject additional drivers during installation)
            $pathF6 = Get-ChildItem $SoftwareComponentExtract\$($SoftwareComponent.packageID) -Recurse -Directory | Where-Object {$_.Name -eq "F6"} 
            $pathNonF6 = Get-Item ($pathF6.FullName + "\..\Drivers") -ErrorAction:SilentlyContinue
            If (Test-Path $pathNonF6 -ErrorAction:SilentlyContinue) {Remove-Item -Path $pathNonF6 -Force -Recurse}
        } Catch {}
    }
}
#endregion

If ($TSEnv) {
    $TSEnv.Value('DRIVERS') = $SoftwareComponentExtract
    # DISM /Image:C:\ /Add-Driver /Driver:C:\WINDOWS\Temp\DellDrivers\Windows11\ /Recurse
}