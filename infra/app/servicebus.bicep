@description('The Azure region for the specified resources.')
param location string = resourceGroup().location

@description('Name of the Service Bus Namespace')
param name string

@description('Name of the Service Bus Queue')
param queueName string = 'queue1'

@description('Tags to apply to resources')
param tags object = {}

@description('Principal ID of the Managed Identity to grant access to')
param principalId string = ''

// Azure Service Bus Data Owner Role
// Allows full access to Service Bus resources (Send, Receive, Manage)
var serviceBusDataOwnerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')

// 1. Create Service Bus Namespace (Basic Tier)
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    // Basic tier does not support Private Endpoints, so Public Network Access must be Enabled.
    // Access is restricted via RBAC (disableLocalAuth: true).
    publicNetworkAccess: 'Enabled'
    minimumTlsVersion: '1.2'
    disableLocalAuth: true // Disables SAS, enforcing Entra ID (RBAC) authentication
  }
}

// 2. Create Service Bus Queue
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = if (!empty(queueName)) {
  parent: serviceBusNamespace
  name: queueName
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 10
    enablePartitioning: false
    enableExpress: false
  }
}

// 3. Assign 'Azure Service Bus Data Owner' role to the Managed Identity
resource serviceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(serviceBusNamespace.id, principalId, serviceBusDataOwnerRole)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: serviceBusDataOwnerRole
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output serviceBusName string = serviceBusNamespace.name
output serviceBusEndpoint string = serviceBusNamespace.properties.serviceBusEndpoint
output serviceBusQueueName string = !empty(queueName) ? serviceBusQueue.name : ''
