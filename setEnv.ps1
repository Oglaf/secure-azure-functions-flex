param(
	[Parameter(Mandatory=$true)]
	[ValidateSet('dev','hml','stg','prd')]
	[string]$Environment,

	[Parameter(Mandatory=$true)]
	[string]$AppName,

	[Parameter(Mandatory=$false)]
	[string]$Location = 'eastus',

	[Parameter(Mandatory=$false)]
	[string]$BusinessUnit = 'my-company',

	[Parameter(Mandatory=$false)]
	[string]$functionAppRuntime = 'dotnet-isolated',

	[Parameter(Mandatory=$false)]
	[string]$functionAppRuntimeVersion = '10.0',

	[Parameter(Mandatory=$false)]
	[string]$instanceMemoryMB = '512',

	[Parameter(Mandatory=$false)]
	[bool]$vnetEnabled = $true,

	[Parameter(Mandatory=$false)]
	[switch]$Apply,

	[Parameter(Mandatory=$false)]
	[bool]$createKV = $false,

    [Parameter(Mandatory=$false)]
	[bool]$createServiceBus = $false
)

function Remove-InvalidChars([string]$s) {
    if (-not $s) { return $s }
    # Allowing letters, digits, and dashes
    return ($s -replace '[^a-zA-Z0-9-]', '')
}

function Get-ShortLocation([string]$loc) {
    $map = @{
        'eastus'           = 'eus'
        'eastus2'          = 'eus2'
        'westus'           = 'wus'
        'westus2'          = 'wus2'
        'centralus'        = 'cus'
        'northcentralus'   = 'ncus'
        'southcentralus'   = 'scus'
        'westeurope'       = 'weu'
        'northeurope'      = 'neu'
        'brazilsouth'      = 'brs'
        'ukwest'           = 'ukw'
        'uksouth'          = 'uks'
    }
    $l = $loc.ToLower()
    if ($map.ContainsKey($l)) { return $map[$l] }
    if ($l.Length -gt 4) { return $l.Substring(0,4) }
    return $l
}

function Get-ShortBU([string]$bu) {
    $map = @{
        'mobilize' = 'mob'
    }
    $b = $bu.ToLower()
    if ($map.ContainsKey($b)) { return $map[$b] }
    if ($b.Length -gt 3) { return $b.Substring(0,3) }
    return $b
}

function New-ResourceNames {
    param(
        [string]$env,
        [string]$app,
        [string]$location,
        [string]$bu,
        [bool]$createKV,
        [bool]$createServiceBus
    )
    
    # 1. Standard Inputs (Cleaned but NOT shortened for general resources)
    $envL = Remove-InvalidChars($env.ToLower())
    $appSafe = Remove-InvalidChars($app.ToLower())
    $locSafe = Remove-InvalidChars($location.ToLower())
    $buSafe = Remove-InvalidChars($bu.ToLower())
    
    # 2. General Base Name (Uses full location/bu for descriptive resources)
    $base = "$appSafe-$envL-$locSafe-$buSafe"
    
    $names = [ordered]@{}
    $names.resourceGroup = "rg-$base"
    # Function App will be calculated separately below
    $names.appServicePlanName = "plan-$base"
    $names.logAnalyticsName = "log-$base"
    $names.applicationInsightsName = "appi-$base"
    $names.vNetName = "vnet-$base"
    $names.apiUserAssignedIdentityName = "id-$base"
    $names.createKV = if ($createKV) { 'true' } else { 'false' }
    $names.createServiceBus = if ($createServiceBus) { 'true' } else { 'false' }

    # 3. Helpers for Short Constraints
    $locShort = Get-ShortLocation($location)
    $buShort = Get-ShortBU($bu)

    # 4. Function App Specific Logic (Strict 32 char limit)
    #    Format: func-{app}-{env}-{loc}-{bu}
    
    $funcOverhead = 8 # "func-" (5) + 3 dashes (3)
    $funcSuffixLength = $envL.Length + $locShort.Length + $buShort.Length
    $maxFuncTotal = 32
    $maxFuncAppLength = $maxFuncTotal - $funcOverhead - $funcSuffixLength

    if ($maxFuncAppLength -lt 2) { $maxFuncAppLength = 2 }

    $funcAppSafe = $appSafe
    if ($funcAppSafe.Length -gt $maxFuncAppLength) {
        $funcAppSafe = $funcAppSafe.Substring(0, $maxFuncAppLength)
    }

    $names.apiServiceName = "func-$($funcAppSafe)-$($envL)-$($locShort)-$($buShort)"

    # 5. Key Vault Specific Logic (Strict 24 char limit)
    #    Format: kv-{app}-{env}-{loc}-{bu}{rnd}
    $kvRnd = Get-Random -Minimum 10 -Maximum 99
    
    $kvOverhead = 8 # "kv-" (3) + 3 dashes (3) + 2 digits (2)
    $kvSuffixLength = $envL.Length + $locShort.Length + $buShort.Length
    $maxKvTotal = 24
    $maxKvAppLength = $maxKvTotal - $kvOverhead - $kvSuffixLength
    
    if ($maxKvAppLength -lt 2) { $maxKvAppLength = 2 }
    
    $kvAppSafe = $appSafe
    if ($kvAppSafe.Length -gt $maxKvAppLength) {
        $kvAppSafe = $kvAppSafe.Substring(0, $maxKvAppLength)
    }
    
    $names.keyVaultName = "kv-$($kvAppSafe)-$($envL)-$($locShort)-$($buShort)$($kvRnd)"

    # 6. Service Bus (Unique name required, 50 chars limit)
    #    We can use the base name logic but add 'sb-'
    $names.serviceBusName = "sb-$base"
    $names.serviceBusQueueName = "sbq-$appSafe"
    
    # 7. Storage account rules (Existing logic)
    $storageBase = "$appSafe$envL$locSafe$buSafe" -replace '[^a-z0-9]',''
    if ($storageBase.Length -gt 16) { $storageBase = $storageBase.Substring(0,16) }
    if ($storageBase -match '^[0-9]') { $storageBase = "a$storageBase" }
    
    $names.storageAccountName = ("st" + $storageBase + (Get-Random -Minimum 10 -Maximum 99)).ToLower()
    
    $names.blobPrivateEndpointName = "pe-blob-$($names.storageAccountName)"
    $names.queuePrivateEndpointName = "pe-queue-$($names.storageAccountName)"
    $names.tablePrivateEndpointName = "pe-table-$($names.storageAccountName)"
    
    return $names
}

# Generate names
$generated = New-ResourceNames -env $Environment -app $AppName -location $Location -bu $BusinessUnit -createKV $createKV -createServiceBus $createServiceBus

# Override runtime/memory/vnet settings from parameters
$generated.functionAppRuntime = $functionAppRuntime
$generated.functionAppRuntimeVersion = $functionAppRuntimeVersion
$generated.instanceMemoryMB = $instanceMemoryMB
$generated.vnetEnabled = if ($vnetEnabled) { 'true' } else { 'false' }

Write-Host "Generated resource names (dry-run). Use -Apply to set in azd."
$generated.GetEnumerator() | ForEach-Object { Write-Host ("{0,-28} : {1}" -f $_.Key, $_.Value) }

if ($Apply) {
	Write-Host "Applying names to azd environment..."
	azd env set AZURE_ENV_NAME "$($AppName)-$Environment"
	azd env set AZURE_LOCATION "$Location"
	azd config set defaults.resource_group "$($generated.resourceGroup)"
	azd env set AZURE_RESOURCE_GROUP "$($generated.resourceGroup)"

	azd env set apiServiceName "$($generated.apiServiceName)"
	azd env set appServicePlanName "$($generated.appServicePlanName)"
	azd env set storageAccountName "$($generated.storageAccountName)"
	azd env set logAnalyticsName "$($generated.logAnalyticsName)"
	azd env set applicationInsightsName "$($generated.applicationInsightsName)"
	azd env set vNetName "$($generated.vNetName)"
    azd env set apiUserAssignedIdentityName "$($generated.apiUserAssignedIdentityName)"
    azd env set keyVaultName "$($generated.keyVaultName)"
    azd env set createKV "$($generated.createKV)"
    azd env set createServiceBus "$($generated.createServiceBus)"
    azd env set serviceBusName "$($generated.serviceBusName)"

	azd env set vnetEnabled "$($generated.vnetEnabled)"
	azd env set blobPrivateEndpointName "$($generated.blobPrivateEndpointName)"
    azd env set queuePrivateEndpointName "$($generated.queuePrivateEndpointName)"
    azd env set tablePrivateEndpointName "$($generated.tablePrivateEndpointName)"
    
    azd env set serviceBusQueueName "$($generated.serviceBusQueueName)"

	azd env set functionAppRuntime "$($generated.functionAppRuntime)"
	azd env set functionAppRuntimeVersion "$($generated.functionAppRuntimeVersion)"
	azd env set instanceMemoryMB "$($generated.instanceMemoryMB)"

	Write-Host "azd environment variables updated."
}

# End of script