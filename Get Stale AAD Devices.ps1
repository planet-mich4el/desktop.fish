﻿<#
    Author:  Michael 
    Version: 1.0
    Created: 2023-08-15

    Get me all stale AAD devices not managed by Intune.
    My definition of a stale AAD device is: 
    * it has not signin the last 120 days; 
    * it is not hybrid joined; 
    * it is not in AutoPilot; 
    * it is not in Intune;
#>

#region authentication
$tenantId = ""
$clientId = ""; $clientSecret = ""

$body = @{
    'tenant' = $tenantId
    'client_id' = $clientId
    'scope' = 'https://graph.microsoft.com/.default'
    'client_secret' = $clientSecret
    'grant_type' = 'client_credentials'
}

$params = @{
    'Uri' = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    'Method' = 'Post'
    'Body' = $body
    'ContentType' = 'application/x-www-form-urlencoded'
}

$authResponse = Invoke-RestMethod @params

$authHeader = @{
    'Authorization' = "Bearer $($authResponse.access_token)"
}
#endregion 

#region function
function Get-PageResult {
    param ($uri, $authHeader)

    $queryResult = @()
    do {
        $result = Invoke-RestMethod -Headers $authHeader -Uri $uri -UseBasicParsing -Method "GET" -ContentType "application/json"
        if ($result.value) { $queryResult += $result.value }
        else { $queryResult += $result }
        $uri = $result.'@odata.nextlink'
    } until (!($uri))
    return $queryResult
}
#endregion

#region AAD device
# include Sale devices (120 days last sign-in)
# exclude AutoPilot devices
# exclude Hybrid Azure AD joined devices
$aadDeviceStart = Get-Date
$approximateLastSignInDateTime = (Get-Date).AddDays(-120)
$approximateLastSignInDateTime = Get-Date -Date $approximateLastSignInDateTime -Format  "yyyy-MM-dd"
$approximateLastSignInDateTime = $approximateLastSignInDateTime + "T00:00:00Z" 

$uri = "https://graph.microsoft.com/v1.0/devices?`$select=displayName,deviceId,id,approximateLastSignInDateTime,trustType&`$filter=approximateLastSignInDateTime le $($approximateLastSignInDateTime) and not (physicalIds/any(p:startswith(p,'[ZTDID]'))) and trustType ne 'ServerAd'&`$count=true&ConsistencyLevel=eventual"
$aadDevice = Get-PageResult -uri $uri -authHeader $global:authHeader;
$aadDevice = $aadDevice | Sort-Object deviceId
$aadDeviceEnd = Get-Date

Write-Output "REST call for AAD devices established time: $($aadDeviceEnd - $aadDeviceStart)"
#endregion

#region Intune device
# get all managed devices without exclusions
$intuneDeviceStart = Get-Date
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$select=deviceName,managedDeviceOwnerType,deviceEnrollmentType,id,azureADDeviceId,operatingSystem,lastSyncDateTime&`$orderby=azureADDeviceId"
$intuneDevice = Get-PageResult -uri $uri -authHeader $global:authHeader
$intuneDeviceEnd = Get-Date

Write-Output "REST call for Intune enrolled devices established time: $($intuneDeviceEnd- $intuneDeviceStart)"
#endregion

#region comparison
$calculationStart = Get-Date

# array comparisons with regular expression
# https://devblogs.microsoft.com/scripting/speed-up-array-comparisons-in-powershell-with-a-runtime-regex/
$aadStaleDevice = @{}
$myRegex = '(?i)^(' + (($intuneDevice | ForEach-Object {[regex]::escape($_.azureADDeviceId)}) -join "|") + ')$'
$aadStaleDevice = $aadDevice | Where-Object { $_.deviceId -notmatch $myRegex }

$calculationEnd = Get-Date
Write-Output "Comparison established time: $($calculationEnd - $calculationStart)"
#endregion

#region summary
Write-Output "AAD devices: $($aadDevice.Count)"
Write-Output "Intune enrolled devices: $($IntuneDevice.Count)"
Write-Output "Stale devices: $($aadStaleDevice.Count)"

try {
    $aadStaleDevice | Export-Csv -Path "C:\Temp\RemoveMe_$(Get-Date -Format "yyyy-MM-dd_HH.mm.ss").csv" -NoTypeInformation -Delimiter ";"
} catch {}
#endregion