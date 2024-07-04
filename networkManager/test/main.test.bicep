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

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Prerequisite Resources ==                               //

// == Virtual Network == 
var vNets = {
  vNet1: {
    name: toLower('vNet01-${uniqueString(resourceGroup().id)}')
    tags: {
      environment: 'prd'
    }
    addressPrefixes: ['192.168.165.0/24']
  } 
  vNet2: {
    name: toLower('vNet02-${uniqueString(resourceGroup().id)}')
    tags: {
      environment: 'test'
    }
    addressPrefixes: ['192.168.169.0/24']
  }
  vNet3: {
    name: toLower('vNet03-${uniqueString(resourceGroup().id)}')
    tags: {
      environment: 'uat'
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
      managementGroups: []
      subscriptions: [subscription().id] 
    }
    vnmDescription: 'Company Azure Virtual Network Manager'
    securityAdminDescription: 'Company Security Configuration'
    networkGroups: [ 
      {
        name: 'allVnets'
        ngDescription: 'All Virtual Networks'
      }
      {
        name: 'prdVnets'
        ngDescription: 'All Production Virtual Networks'
      }
      {
        name: 'nonPrdVnets'
        ngDescription: 'All Non-Production Virtual Networks'
    }]
    ruleCollections: [
      {
        name: 'rcSuffix01'
        targetGroups: [{
          name:'allVnets'
        }
        {
          name:'prdVnets'
        }]
        ruleC: 'rule1'
      }
      {
        name: 'rcSuffix02'
        targetGroups: [{
          name:'prdVnets'
        }]
        rulenC: 'rule2'
      }
      {
        name: 'rcSuffix03'
        targetGroups: [{
          name:'nonPrdVnets'
        }]
        rulenC: 'rule3'
      }
    ]
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
  }   
}
