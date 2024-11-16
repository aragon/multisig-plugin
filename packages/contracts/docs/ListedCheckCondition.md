# Solidity API

## ListedCheckCondition

A condition contract that checks if an address is listed as a member in the associated Multisig contract.

### constructor

```solidity
constructor(address _multisig) public
```

Initializes the condition with the address of the Multisig plugin.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _multisig | address | The address of the Multisig plugin that stores listing and other configuration settings. |

### isGranted

```solidity
function isGranted(address _where, address _who, bytes32 _permissionId, bytes _data) public view returns (bool)
```

Checks if a call is permitted.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _where | address | The address of the target contract. |
| _who | address | The address (EOA or contract) for which the permissions are checked. |
| _permissionId | bytes32 | The permission identifier. |
| _data | bytes | Optional data passed to the `PermissionCondition` implementation. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool |  |

