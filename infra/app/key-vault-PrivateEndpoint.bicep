@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('Name of the Key Vault')
param name string

@description('Tags to apply to resources')
param tags object = {}

@description('If true, deploy private endpoint and disable public access')
param vnetEnabled bool = false

@description('Virtual Network ID for Private DNS Zone linking')
param virtualNetworkId string = ''

@description('Subnet ID for the Private Endpoint')
param subnetPrivateEndpointId string = ''

@description('Principal ID of the Managed Identity to grant access to')
param principalId string = ''

@description('The Tenant ID for the Key Vault')
param tenantId string = subscription().tenantId

// Role Definition ID for 'Key Vault Secrets User'
// Allows reading secrets (GET/LIST) but not managing them.
var keyVaultSecretsUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// 1. Create the Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true // Switch to RBAC
    accessPolicies: [] // Clear Access Policies
    publicNetworkAccess: vnetEnabled ? 'Disabled' : 'Enabled' // Explicitly disable public access if VNet is enabled
    networkAcls: {
      bypass: 'AzureServices'
      // If VNet is enabled, deny public access. Otherwise allow it.
      defaultAction: vnetEnabled ? 'Deny' : 'Allow'
      virtualNetworkRules: []
    }
  }
}

// 2. Assign 'Key Vault Secrets User' role to the Managed Identity
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// 3. Create Private Endpoint (Only if vnetEnabled)
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = if (vnetEnabled) {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetPrivateEndpointId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${name}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// 4. Create Private DNS Zone Group (Links PE to DNS Zone)
resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = if (vnetEnabled) {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

// 5. Create Private DNS Zone
resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (vnetEnabled) {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

// 6. Link DNS Zone to VNet
resource keyVaultPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (vnetEnabled) {
  parent: keyVaultPrivateDnsZone
  name: '${name}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
