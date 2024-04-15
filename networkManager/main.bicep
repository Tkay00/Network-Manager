///////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Base Parameters ==

@description('Resource location')
param locationName string = resourceGroup().location

@description('Resource tags')
param tags object = {}

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                == Resource Name Gen Parameters ==

@description('The resource type count within the resource group. Used in the resource guid generation.')
param resourceTypeCount int = 1

@description('The environment of the resource. Used in the resource name generation')
@allowed([
  'dev'
  'tst'
  'prd'
])
param resourceNameEnv string

var locationCode = 'uw2'

@description('Optional - The resource name to use rather than having it auto generated')
param resourceNameOverride string = ''

var resourceNameGuid = take(uniqueString(resourceGroup().id, string(resourceTypeCount)), 4)

var resourceNameGen = toLower('vnm-${resourceNameGuid}-${locationCode}-${resourceNameEnv}')
var resourceName = !empty(resourceNameOverride) ? resourceNameOverride : resourceNameGen

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                    == Global Parameters ==

@description('Log Analytics Workspace ID, required if Diagnostic Settings is enabled.')
param logAnalyticsWorkspaceId string = ''

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                == Module Specific Parameters ==

@description('The scope of the network manager')
@metadata({
  managementGroups: ['']
  subscriptions: ['']  
})
param networkManagerScopes object = {}

@description('The network manager scope access')
param networkManagerScopeAccesses array = ['SecurityAdmin']

@description('A description of the network manager')
param vnmDescription string = 'Pembina Pipeline Azure Virtual Network Manager - Prod'

@description('Network groups and the respective descriptions')
@metadata({
  name: 'ngSuffix'
  ngDescription: 'string'
})
param networkGroups array = []

@description('The security confifuration of the network manager')
param securityAdminDescription string = 'Pembina Pipeline Security Configuration - Prod'

@description('A list of rule collections applied to the network groups')
@metadata({
  name: 'rcSuffix'
  targetGroups: [{
    name:'string'
  }]
})
param ruleCollections array = []

var networkGroupDescription = 'The use case of the network group'
// var ruleTemplate = (loadJsonContent('data/ruleTemplate.json')).rules

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                        ==  Parameters =

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                         == Resources ==

// == networkManager == 
resource networkManager 'Microsoft.Network/networkManagers@2023-05-01' = {
  name: resourceName
  location: locationName
  tags: tags
  properties: {
    description: vnmDescription
    networkManagerScopeAccesses: networkManagerScopeAccesses
    networkManagerScopes: {
      managementGroups: contains(networkManagerScopes, 'managementGroups') ? networkManagerScopes.managementGroups : null
      subscriptions: contains(networkManagerScopes, 'subscriptions') ? networkManagerScopes.subscriptions : null
    }
  }
}  

// == networkGroup ==
resource networkGroup 'Microsoft.Network/networkManagers/networkGroups@2023-05-01' = [for group in networkGroups: {
  parent: networkManager
  name: '${resourceName}-ng-${group}'
  properties: {
    description: networkGroupDescription
  }
}]

// == SecurityConfig ==
resource securityAdminConfig 'Microsoft.Network/networkManagers/securityAdminConfigurations@2023-05-01' = {
  parent: networkManager
  name: '${resourceName}-securityConfig'
  properties: {
    applyOnNetworkIntentPolicyBasedServices: [
      'None'
    ]
    description: securityAdminDescription 
  }
}

//== ruleCollection == correct original
resource ruleCollection 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2023-05-01' = [for collection in ruleCollections: {
  parent: securityAdminConfig
  name: '${resourceName}-rc-${collection.name}'
  properties: {
    appliesToGroups: [for group in collection.targetGroups: {
        networkGroupId: resourceId('Microsoft.Network/networkManagers/networkGroups', resourceName, '${resourceName}-ng-${group.name}')   
    }]
  }  
}]  

// == securityAdminRules
var ruleTemplate = (loadJsonContent('data/ruleTemplate.json')).rules

resource securityRule01 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2023-05-01' = [for (collection, i) in ruleCollections: {
  parent: ruleCollection[i]
  name: contains(collection, 'rulesTemplate') ? ruleTemplate[collection.ruleTemplate] : []         
  kind: 'Custom'
  properties: contains(collection, 'rulesTemplate') ? ruleTemplate[collection.ruleTemplate] : []
}]

// == Diagnostics 
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'default'
  scope: networkManager
  properties: {
    logAnalyticsDestinationType: 'AzureDiagnostics'
    logs: [
      {
        category: null
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: null
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]    
    workspaceId: logAnalyticsWorkspaceId
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
//                                            == Outputs ==                                     

@description('The resource name of the virtual network manager')
output virtualNetworkManagerName string = networkManager.name

@description('The resource ID of the network group')
output networkGroupId array = [for (group, i) in networkGroups: {
  networkGroupId: networkGroup[i].id
}]
