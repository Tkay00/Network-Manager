///////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Base Parameters ==                               

targetScope = 'subscription'

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                == Resource Name Gen Parameters ==

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                   == Global Parameters ==

///////////////////////////////////////////////////////////////////////////////////////////////////
//                                == Module Specific Parameters ==            

@description('A list of policy definitions applied to the network groups')
param policies array = []

var policyType = 'Custom'
var mode = 'Microsoft.Network.Data'
var category = 'Virtual Network Manager'
var effect = 'addToNetworkGroup'

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                       == Resources ==

// == Policy Definition ==
resource policyDefinition 'Microsoft.Authorization/policyDefinitions@2023-04-01' = [for (policy, i)  in policies: {
  name: policy.name
  properties: {
    displayName: policy.name
    policyType: policyType 
    mode: mode
    description: policy.description
    metadata: {
      category: category
    }
    policyRule:  {
      if: policy.policyRulePattern
      then: {
        effect: effect
        details: {
          networkGroupId: policy.networkGroupId
        }                                                                   
      }    
    }       
  }      
}]

// Policy Assignment ==
resource policyAssignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = [for (policy, i) in policies: {
  name: policy.name
  properties: {
    displayName: policy.name
    description: policy.description
    policyDefinitionId: policyDefinition[i].id
  }
}]

// ///////////////////////////////////////////////////////////////////////////////////////////////////
//                                            == Outputs == 

@description('The resource ID of the policy')
output policyDefinitionId array = [for (policy, i) in policies: {
  policyDefinitionId: policyDefinition[i].id
}]

