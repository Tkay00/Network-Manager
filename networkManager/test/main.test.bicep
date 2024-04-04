/*
az group create -l westus2 -n rg-bmt-vnm
az deployment group what-if --resource-group rg-bmt-vnm --template-file test\main.test.bicep

== Run the commands to commit the deployment to the target region ==
get security config id using - az network manager security-admin-config list --network-manager-name vnm-iqbo --resource-group rg-bmt-vnm
commit the config using - az network manager post-commit --resource-group rg-bmt-vnm --target-locations westus2 --network-manager-name vnm-iqbo --commit-type SecurityAdmin --configuration-ids 
*/

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Base Parameters ==                                       //

param resourceNameEnv string = 'sbx'
param locationName string = 'westus2'
param tags object = {
    purpose: 'Bicep Module Testing (network/virtual-network-manager)'
}

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                    == Parameters ==

param resourceGrpName string = resourceGroup().name

var netwrkMgrName = vnetManager.outputs.virtualNetworkManagerName
var policies = [
  {
    name: 'Add all virtual networks to a network group'
    description: 'Adds all the virtual network within a specific target scope to a network group.'
    networkGroupId: '${subscription().id}/resourceGroups/${resourceGrpName}/providers/Microsoft.Network/networkManagers/${netwrkMgrName}/networkGroups/${'${netwrkMgrName}-ng-${networkGroups[0]}'}'
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
    networkGroupId: '${subscription().id}/resourceGroups/${resourceGrpName}/providers/Microsoft.Network/networkManagers/${netwrkMgrName}/networkGroups/${'${netwrkMgrName}-ng-${networkGroups[1]}'}'
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
    networkGroupId: '${subscription().id}/resourceGroups/${resourceGrpName}/providers/Microsoft.Network/networkManagers/${netwrkMgrName}/networkGroups/${'${netwrkMgrName}-ng-${networkGroups[2]}'}'
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
              equals:'nonprd'
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

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Prerequisite Resources ==                               //

// == Virtual Network == 
var vNets = {
  vNet1: {
    name: toLower('vNet01-${uniqueString(resourceGroup().id)}')
    tags: {
      environment: 'prd'
    }
    addressPrefixes: ['192.168.168.0/24']
  } 
  vNet2: {
    name: toLower('vNet02-${uniqueString(resourceGroup().id)}')
    tags: {
      environment: 'nonprd'
    }
    addressPrefixes: ['192.168.169.0/24']
  }
  vNet3: {
    name: toLower('vNet03-${uniqueString(resourceGroup().id)}')
    tags: {
      environment: ''
    }
    addressPrefixes:['192.168.167.0/24']
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = [for vNet in items(vNets): {
  name: vNet.value.name
  location: locationName
  tags: vNet.value.tags
  properties: {
    addressSpace: {
      addressPrefixes: vNet.value.addressPrefixes
    }
  }
}]

// == Log Analytics Workspace == 
var logAnalyticsWorkspaceName = toLower('log-${uniqueString(resourceGroup().id)}')

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: locationName
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 120
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                == Module Specific Parameters ==

@description('A list of network groups. Usually contain virtual networks to apply configuration at scale')
param networkGroups array = [
  'allVnets'
  'prdVnets'
  'nonPrdVnets'
]

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Module Tests ==                                         //

// Test - networkManager with networkGroups, and a securityAdmin config(contains a list ruleCollections and rules)
module vnetManager '../main.bicep'= {
  name: 'vnetManagerDeployment-${uniqueString(deployment().name, locationName)}-01'
  params: {
    resourceNameEnv: resourceNameEnv
    locationName: locationName
    tags: tags
    networkManagerScopes: {
      subscriptions: [subscription().id]
    }
    vnmDescription: 'Azure Virtual Network Manager - Prod'
    securityAdminDescription: 'CompanyX Security rule'
    networkGroups: networkGroups
    ruleCollections: [
      {
        name: 'ops1'
        targetGroups: [
          {
            name:'allVnets'
          }
          {
            name:'prdVnets'
          }
        ]
        rulesTemplate: 'rule1'
      }
      {
        name: 'ops2'
        targetGroups: [{
          name:'prdVnets'
        }]
        rulesTemplate: 'rule2'
      }
      {
        name: 'ops3'
        targetGroups: [{
          name:'nonPrdVnets'
        }]
        rulesTemplate: 'rule3'
      }
    ]
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
  }   
}

// Poliy to add the virtual networks to the network groups. The policy uses tags to add the vnet to the respective network groups
module vnetManagerPolicy '../data/policy.bicep' = {
  scope: subscription()
  name: 'vnetManagerPolicyDeployment-${uniqueString(deployment().name, locationName)}-01'
  params: {
    policies: policies
  }
}
