<#
    Author:  Michael 
    Version: 1.0
    Created: 2022-10-27

    Download the latest Dell driver package.
#>

# system variables
If (Test-Path -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlset\Control\MiniNT -ErrorAction:SilentlyContinue) {
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
    $rootFolder = "$($TSEnv.Value("OSDTargetSystemDrive"))\Windows\Temp\DellDrivers"
} Else {
    $rootFolder = "$($env:SystemRoot)\Temp\DellDrivers"
}

$systemModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
# $systemModel = "Latitude 7320" 
$targetOs = "Windows10"

# create root folder for all files required 
New-Item -Path $rootFolder -ItemType Directory -ErrorAction:SilentlyContinue | Out-Null


Write-Output "`n`t --- DriverPackCatalog ---"
#region

# declare variable for next section
$DriverPackCatalogUrl = "https://downloads.dell.com/catalog/DriverPackCatalog.cab"
$DriverPackCatalogCab = "$rootFolder\DriverPackCatalog.cab"
$DriverPackCatalogXml = $DriverPackCatalogCab -replace ("cab","xml")

# download cab-file
Write-Output "$(Get-Date) :: Download: $DriverPackCatalogUrl"
If (Test-Path $DriverPackCatalogCab -ErrorAction:SilentlyContinue) {Remove-Item -Path $DriverPackCatalogCab -Force}
Invoke-RestMethod -Uri $DriverPackCatalogUrl -OutFile $DriverPackCatalogCab -UseBasicParsing

# expand cab-file
Write-Output "$(Get-Date) :: Expand: $DriverPackCatalogCab"
If (Test-Path $DriverPackCatalogXml -ErrorAction:SilentlyContinue) {Remove-Item -Path $DriverPackCatalogXml -Force}
$Expand = EXPAND $DriverPackCatalogCab $DriverPackCatalogXml

# filter cab-file for the model required  
Write-Output "$(Get-Date) :: Load: $DriverPackCatalogXml"
[xml]$XmlContent = Get-Content $DriverPackCatalogXml -Verbose
$DriverPackage = $XmlContent.DriverPackManifest.DriverPackage | Where-Object {$_.SupportedOperatingSystems.OperatingSystem.osCode -eq $targetOs -and $_.SupportedSystems.Brand.Model.Name -eq $systemModel}
#endregion


Write-Output "`n`t --- DriverPackage ---"
#region

# declare variable for next section
$DriverPackageUrl = "https://downloads.dell.com/$($DriverPackage.path)"
$DriverPackageExe = "$rootFolder\$($DriverPackage.path.Split("/") | Where-Object {$_ -match ".exe"})"

$DriverPackageExtract = "$rootFolder\$($DriverPackage.dellVersion)"
If (Test-Path $DriverPackageExtract -ErrorAction:SilentlyContinue) {Remove-Item -Path $DriverPackageExtract -Force -Recurse}
New-Item -Path $DriverPackageExtract -ItemType Directory -ErrorAction:SilentlyContinue | Out-Null

# download driver packeage
Write-Output "$(Get-Date) :: Download: $DriverPackageUrl; Size: $([math]::round($DriverPackage.size /1Mb,2))Mb"
Invoke-RestMethod -Uri $DriverPackageUrl -OutFile $DriverPackageExe -UseBasicParsing
    
If (($DriverPackage.Cryptography.Hash | Where-Object {$_.algorithm -eq "MD5"}).'#text' -eq (Get-FileHash $DriverPackageExe -Algorithm MD5).Hash) {
    Try {
        # extract driver packeage
        Write-Output "$(Get-Date) :: Extract: $DriverPackageExe"
        Start-Process $DriverPackageExe "/s /e=""$DriverPackageExtract""" -Wait
    } Catch {}
}
#endregion

If ($TSEnv) {
    $TSEnv.Value('DRIVERS') = $DriverPackageExtract
    # DISM /Image:C:\ /Add-Driver /Driver:C:\WINDOWS\Temp\DellDrivers\ /Recurse
}