<#
    Author:  Michael 
    Version: 1.4
    Created: 2022-11-18

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
#$systemModel = "Precision 5470"
$targetOs = "Windows 11"; $targetOs = $targetOs.Replace(" ","")
$targetArch = "x64"

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
$DriverPackage = $XmlContent.DriverPackManifest.DriverPackage | Where-Object {$_.SupportedOperatingSystems.OperatingSystem.osCode -eq $targetOs -and $_.SupportedOperatingSystems.OperatingSystem.osArch -eq $targetArch -and $_.SupportedSystems.Brand.Model.Name -eq $systemModel}
If (-not $DriverPackage) { Exit 1 }
#endregion


Write-Output "`n`t --- DriverPackage ---"
#region

# declare variable for next section
$DriverPackageUrl = "https://downloads.dell.com/$($DriverPackage.path)"
$DriverPackageExe = "$rootFolder\$($DriverPackage.path.Split("/") | Where-Object {$_ -match ".exe"})"

$DriverPackageExtract = ("$rootFolder\$($systemModel)_$($targetOs)_DriverPackage_$($DriverPackage.dellVersion)") -Replace(' ')
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

        # remove non-F6 drivers (in Windows XP you had to tap the F6 key to inject additional drivers during installation)
        $pathF6 = Get-ChildItem $DriverPackageExtract -Recurse -Directory | Where-Object {$_.Name -eq "F6"} 
        $pathNonF6 = Get-Item ($pathF6.FullName + "\..\Drivers") -ErrorAction:SilentlyContinue
        If (Test-Path $pathNonF6 -ErrorAction:SilentlyContinue) {Remove-Item -Path $pathNonF6 -Force -Recurse}
    } Catch {}
}
#endregion

If ($TSEnv) {
    $TSEnv.Value('DRIVERS') = $DriverPackageExtract
    # DISM /Image:C:\ /Add-Driver /Driver:C:\WINDOWS\Temp\DellDrivers\ /Recurse
}