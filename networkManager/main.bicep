///////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Base Parameters ==

@description('Resource location')
param locationName string = resourceGroup().location

@description('Resource tags')
param tags object = {}

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                == Resource Name Gen Parameters ==

@description('The resource type count within the resource group. Used in the resource guid generation. (Only required if deploying multiple resources of the same type within the resource group)')
param resourceTypeCount int = 1

@description('The environment of the resource. Used in the resource name generation')
@allowed([
  'sbx'
  'dev'
  'tst'
  'prd'
])
param resourceNameEnv string

var locations = (loadJsonContent('../locationData/locations.json')).locations
var locationCode = locations[toLower(locationName)]

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
param ruleCollections array = []


//////////////////////////////////////////////////////////////////////////////////////////////////
//                                         == Resources ==

// == nNetwork Manager == 
resource networkManager 'Microsoft.Network/networkManagers@2023-09-01' = {
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

// == Network Group ==
resource networkGroup 'Microsoft.Network/networkManagers/networkGroups@2023-09-01' = [for group in networkGroups: {
  parent: networkManager
  name: '${resourceName}-ng-${group.name}'
  properties: {
    description: group.ngDescription
  }
}]

// == Security Config ==
resource securityAdminConfig 'Microsoft.Network/networkManagers/securityAdminConfigurations@2023-09-01' = {
  parent: networkManager
  name: '${resourceName}-securityConfig'
  properties: {
    applyOnNetworkIntentPolicyBasedServices: [
      'None'
    ]
    description: securityAdminDescription 
  }
}

//== Rule Collection ==
resource ruleCollection 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2023-09-01' = [for (collection, i) in ruleCollections: {
  parent: securityAdminConfig
  name: '${resourceName}-rc-${collection.name}'
  properties: {
    appliesToGroups: [ for group in collection.targetGroups: {
        networkGroupId: resourceId('Microsoft.Network/networkManagers/networkGroups', resourceName, '${resourceName}-ng-${group.name}')    
    }]
  }   
}]  

// == Rules ==
var ruleTemplate = (loadJsonContent('data/ruleTemplate.json')).ruleTemplate

resource securityRuletst02 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2023-09-01' = [for (collection, i) in ruleCollections: {
  parent: ruleCollection[i]
  name: contains(collection, 'ruleC') ? ruleTemplate[collection.rulen] : []      
  kind: 'Custom'
  properties: contains(collection, 'ruleC') ? ruleTemplate[collection.rulen] : []
}]

// == Diagnostics ==
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

// == Policy Module ==
module vnetManagerPolicy 'data/policy.bicep' = {
  scope: subscription()
  name: 'vnetManagerPolicyDeployment-${uniqueString(deployment().name, locationName)}-01'
  params: {
    policies: [
      {
        name: 'Add all virtual networks to a network group'
        description: 'Adds all the virtual network within a specific target scope to a network group.'            
        networkGroupId: networkGroup[0].id
        policyRulePattern: {
          allOf: [
            {
              field: 'type'
              equals: 'Microsoft.Network/virtualNetworks'
            }
            {
              anyOf: [
                {
                  field: 'tags[\'environment\']'
                  exists: 'true'
                }
                {
                  field:  'tags[\'environment\']'
                  exists: 'false'
                }
              ]
            }
          ]
        }
      }
      {
        name: 'Add production virtual network to a network group'
        description: 'Adds only production virtual networks within a specific target scope to a network group.'
        networkGroupId: networkGroup[1].id
        policyRulePattern: {
          allOf: [
            {
              field: 'type'
              equals: 'Microsoft.Network/virtualNetworks'
            }
            {
              anyOf: [
                {
                  field: 'tags[\'environment\']'
                  equals: 'prd'
    
                }
                {
                  field: 'tags[\'environment\']'
                  equals: 'prod'
                }
                {
                  field: 'tags[\'environment\']'
                  equals: 'production'
                }
              ]
            }
          ]
        }
      }
      {
        name: 'Add non-production virtual network to a network group'
        description: 'Adds non-production virtual networks within a specific target scope to a network group.'
        networkGroupId: networkGroup[2].id
        policyRulePattern: {
          allOf: [
            {
              field: 'type'
              equals: 'Microsoft.Network/virtualNetworks'
            }
            {
              allOf: [
                {
                  field: 'tags[\'environment\']'
                  notEquals: 'prd'
                }
                {
                  field: 'tags[\'environment\']'
                  notEquals:'prod'
                }
                {
                  field: 'tags[\'environment\']'
                  notEquals: 'production'
                }
              ]
            }
          ]
        }
      }
    ]
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
