# Solidity API

## MultisigSetup

The setup contract of the `Multisig` plugin.

_v1.3 (Release 1, Build 3)_

### EXECUTE_PERMISSION_ID

```solidity
bytes32 EXECUTE_PERMISSION_ID
```

The ID of the permission required to call the `execute` function on a DAO.

### UPGRADE_PLUGIN_PERMISSION_ID

```solidity
bytes32 UPGRADE_PLUGIN_PERMISSION_ID
```

The ID of the permission required to call the `upgradeToAndCall` function.

### SET_TARGET_CONFIG_PERMISSION_ID

```solidity
bytes32 SET_TARGET_CONFIG_PERMISSION_ID
```

The ID of the permission required to call the `setTargetConfig` function.

### SET_METADATA_PERMISSION_ID

```solidity
bytes32 SET_METADATA_PERMISSION_ID
```

The ID of the permission required to call the `setMetadata` function on a DAO.

### UPDATE_MULTISIG_SETTINGS_PERMISSION_ID

```solidity
bytes32 UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
```

The ID of the permission required to call the `updateMultisigSettings` function.

### ANY_ADDR

```solidity
address ANY_ADDR
```

A special address encoding permissions that are valid for any address `who` or `where`.

### constructor

```solidity
constructor() public
```

The contract constructor, that deploys the `Multisig` plugin logic contract.

### prepareInstallation

```solidity
function prepareInstallation(address _dao, bytes _data) external returns (address plugin, struct IPluginSetup.PreparedSetupData preparedSetupData)
```

Prepares the installation of a plugin.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _dao | address | The address of the installing DAO. |
| _data | bytes | The bytes-encoded data containing the input parameters for the installation as specified in the plugin's build metadata JSON file. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| plugin | address | The address of the `Plugin` contract being prepared for installation. |
| preparedSetupData | struct IPluginSetup.PreparedSetupData | The deployed plugin's relevant data which consists of helpers and permissions. |

### prepareUpdate

```solidity
function prepareUpdate(address _dao, uint16 _fromBuild, struct IPluginSetup.SetupPayload _payload) external returns (bytes initData, struct IPluginSetup.PreparedSetupData preparedSetupData)
```

Prepares the update of a plugin.

_Revoke the upgrade plugin permission to the DAO for all builds prior the current one (3)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _dao | address | The address of the updating DAO. |
| _fromBuild | uint16 | The build number of the plugin to update from. |
| _payload | struct IPluginSetup.SetupPayload | The relevant data necessary for the `prepareUpdate`. See above. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| initData | bytes | The initialization data to be passed to upgradeable contracts when the update is applied in the `PluginSetupProcessor`. |
| preparedSetupData | struct IPluginSetup.PreparedSetupData | The deployed plugin's relevant data which consists of helpers and permissions. |

### prepareUninstallation

```solidity
function prepareUninstallation(address _dao, struct IPluginSetup.SetupPayload _payload) external view returns (struct PermissionLib.MultiTargetPermission[] permissions)
```

Prepares the uninstallation of a plugin.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _dao | address | The address of the uninstalling DAO. |
| _payload | struct IPluginSetup.SetupPayload | The relevant data necessary for the `prepareUninstallation`. See above. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| permissions | struct PermissionLib.MultiTargetPermission[] | The array of multi-targeted permission operations to be applied by the `PluginSetupProcessor` to the uninstalling DAO. |

