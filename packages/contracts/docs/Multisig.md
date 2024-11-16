# Solidity API

## Multisig

The on-chain multisig governance plugin in which a proposal passes if X out of Y approvals are met.

_v1.3 (Release 1, Build 3). For each upgrade, if the reinitialization step is required,
     increment the version numbers in the modifier for both the initialize and initializeFrom functions._

### Proposal

```solidity
struct Proposal {
  bool executed;
  uint16 approvals;
  struct Multisig.ProposalParameters parameters;
  mapping(address => bool) approvers;
  struct Action[] actions;
  uint256 allowFailureMap;
  struct IPlugin.TargetConfig targetConfig;
}
```

### ProposalParameters

```solidity
struct ProposalParameters {
  uint16 minApprovals;
  uint64 snapshotBlock;
  uint64 startDate;
  uint64 endDate;
}
```

### MultisigSettings

```solidity
struct MultisigSettings {
  bool onlyListed;
  uint16 minApprovals;
}
```

### MULTISIG_INTERFACE_ID

```solidity
bytes4 MULTISIG_INTERFACE_ID
```

The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.

### UPDATE_MULTISIG_SETTINGS_PERMISSION_ID

```solidity
bytes32 UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
```

The ID of the permission required to call the
        `addAddresses`, `removeAddresses` and `updateMultisigSettings` functions.

### CREATE_PROPOSAL_PERMISSION_ID

```solidity
bytes32 CREATE_PROPOSAL_PERMISSION_ID
```

The ID of the permission required to call the `createProposal` function.

### EXECUTE_PROPOSAL_PERMISSION_ID

```solidity
bytes32 EXECUTE_PROPOSAL_PERMISSION_ID
```

The ID of the permission required to call the `execute` function.

### proposals

```solidity
mapping(uint256 => struct Multisig.Proposal) proposals
```

A mapping between proposal IDs and proposal information.

### multisigSettings

```solidity
struct Multisig.MultisigSettings multisigSettings
```

The current plugin settings.

### lastMultisigSettingsChange

```solidity
uint64 lastMultisigSettingsChange
```

Keeps track at which block number the multisig settings have been changed the last time.

_This variable prevents a proposal from being created in the same block in which the multisig
     settings change._

### ProposalCreationForbidden

```solidity
error ProposalCreationForbidden(address sender)
```

Thrown when a sender is not allowed to create a proposal.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| sender | address | The sender address. |

### NonexistentProposal

```solidity
error NonexistentProposal(uint256 proposalId)
```

Thrown when a proposal doesn't exist.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The ID of the proposal which doesn't exist. |

### ApprovalCastForbidden

```solidity
error ApprovalCastForbidden(uint256 proposalId, address sender)
```

Thrown if an approver is not allowed to cast an approve. This can be because the proposal
        - is not open,
        - was executed, or
        - the approver is not on the address list

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The ID of the proposal. |
| sender | address | The address of the sender. |

### ProposalExecutionForbidden

```solidity
error ProposalExecutionForbidden(uint256 proposalId)
```

Thrown if the proposal execution is forbidden.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The ID of the proposal. |

### MinApprovalsOutOfBounds

```solidity
error MinApprovalsOutOfBounds(uint16 limit, uint16 actual)
```

Thrown if the minimal approvals value is out of bounds (less than 1 or greater than the number of
        members in the address list).

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| limit | uint16 | The maximal value. |
| actual | uint16 | The actual value. |

### AddresslistLengthOutOfBounds

```solidity
error AddresslistLengthOutOfBounds(uint16 limit, uint256 actual)
```

Thrown if the address list length is out of bounds.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| limit | uint16 | The limit value. |
| actual | uint256 | The actual value. |

### ProposalAlreadyExists

```solidity
error ProposalAlreadyExists(uint256 proposalId)
```

Thrown if the proposal with the same id already exists.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The id of the proposal. |

### DateOutOfBounds

```solidity
error DateOutOfBounds(uint64 limit, uint64 actual)
```

Thrown if a date is out of bounds.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| limit | uint64 | The limit value. |
| actual | uint64 | The actual value. |

### Approved

```solidity
event Approved(uint256 proposalId, address approver)
```

Emitted when a proposal is approve by an approver.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The ID of the proposal. |
| approver | address | The approver casting the approve. |

### MultisigSettingsUpdated

```solidity
event MultisigSettingsUpdated(bool onlyListed, uint16 minApprovals)
```

Emitted when the plugin settings are set.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| onlyListed | bool | Whether only listed addresses can create a proposal. |
| minApprovals | uint16 | The minimum amount of approvals needed to pass a proposal. |

### initialize

```solidity
function initialize(contract IDAO _dao, address[] _members, struct Multisig.MultisigSettings _multisigSettings, struct IPlugin.TargetConfig _targetConfig, bytes _pluginMetadata) external
```

Initializes Release 1, Build 3.

_This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _dao | contract IDAO | The IDAO interface of the associated DAO. |
| _members | address[] | The addresses of the initial members to be added. |
| _multisigSettings | struct Multisig.MultisigSettings | The multisig settings. |
| _targetConfig | struct IPlugin.TargetConfig | Configuration for the execution target, specifying the target address and     operation type(either `Call` or `DelegateCall`). Defined by `TargetConfig` in the `IPlugin`     interface of `osx-commons-contracts` package, added in build 3. |
| _pluginMetadata | bytes | The plugin specific information encoded in bytes.     This can also be an ipfs cid encoded in bytes. |

### initializeFrom

```solidity
function initializeFrom(uint16 _fromBuild, bytes _initData) external
```

Reinitializes the Multisig after an upgrade from a previous build version. For each
        reinitialization step, use the `_fromBuild` version to decide which internal functions to call
        for reinitialization.

_WARNING: The contract should only be upgradeable through PSP to ensure that _fromBuild is not
     incorrectly passed, and that the appropriate permissions for the upgrade are properly configured._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _fromBuild | uint16 | The build version number of the previous implementation contract     this upgrade is transitioning from. |
| _initData | bytes | The initialization data to be passed to via `upgradeToAndCall`     (see [ERC-1967](https://docs.openzeppelin.com/contracts/4.x/api/proxy#ERC1967Upgrade)). |

### supportsInterface

```solidity
function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool)
```

Checks if this or the parent contract supports an interface by its ID.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _interfaceId | bytes4 | The ID of the interface. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Returns `true` if the interface is supported. |

### addAddresses

```solidity
function addAddresses(address[] _members) external
```

Adds new members to the address list. Previously, it checks if the new address
        list length would be greater than `type(uint16).max`, the maximal number of approvals.

_Requires the `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _members | address[] | The addresses of the members to be added. |

### removeAddresses

```solidity
function removeAddresses(address[] _members) external
```

Removes existing members from the address list. Previously, it checks if the
        new address list length is at least as long as the minimum approvals parameter requires.
        Note that `minApprovals` is must be at least 1 so the address list cannot become empty.

_Requires the `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _members | address[] | The addresses of the members to be removed. |

### updateMultisigSettings

```solidity
function updateMultisigSettings(struct Multisig.MultisigSettings _multisigSettings) external
```

Updates the plugin settings.

_Requires the `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _multisigSettings | struct Multisig.MultisigSettings | The new settings. |

### createProposal

```solidity
function createProposal(bytes _metadata, struct Action[] _actions, uint256 _allowFailureMap, bool _approveProposal, bool _tryExecution, uint64 _startDate, uint64 _endDate) public returns (uint256 proposalId)
```

Creates a new multisig proposal.

_Requires the `CREATE_PROPOSAL_PERMISSION_ID` permission._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _metadata | bytes | The metadata of the proposal. |
| _actions | struct Action[] | The actions that will be executed after the proposal passes. |
| _allowFailureMap | uint256 | A bitmap allowing the proposal to succeed, even if individual actions might revert.     If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts.     A failure map value of 0 requires every action to not revert. |
| _approveProposal | bool | If `true`, the sender will approve the proposal. |
| _tryExecution | bool | If `true`, execution is tried after the vote cast. The call does not revert if     execution is not possible. |
| _startDate | uint64 | The start date of the proposal. |
| _endDate | uint64 | The end date of the proposal. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The ID of the proposal. |

### createProposal

```solidity
function createProposal(bytes _metadata, struct Action[] _actions, uint64 _startDate, uint64 _endDate, bytes _data) external returns (uint256 proposalId)
```

Creates a new proposal.

_Calls a public function that requires the `CREATE_PROPOSAL_PERMISSION_ID` permission._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _metadata | bytes | The metadata of the proposal. |
| _actions | struct Action[] | The actions that will be executed after the proposal passes. |
| _startDate | uint64 | The start date of the proposal. |
| _endDate | uint64 | The end date of the proposal. |
| _data | bytes | The additional abi-encoded data to include more necessary fields. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposalId | uint256 | The id of the proposal. |

### customProposalParamsABI

```solidity
function customProposalParamsABI() external pure returns (string)
```

The human-readable abi format for extra params included in `data` of `createProposal`.

_Used for UI to easily detect what extra params the contract expects._

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | string | ABI of params in `data` of `createProposal`. |

### approve

```solidity
function approve(uint256 _proposalId, bool _tryExecution) public
```

Records an approval for a proposal and, if specified, attempts execution if certain conditions are met.

_If `_tryExecution` is `true`, the function attempts execution after recording the approval.
     Execution will only proceed if the proposal is no longer open, the minimum approval requirements are met,
     and the caller has been granted execution permission. If execution conditions are not met,
     the function does not revert._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal to approve. |
| _tryExecution | bool | If `true`, attempts execution of the proposal after approval, without reverting on failure. |

### canApprove

```solidity
function canApprove(uint256 _proposalId, address _account) external view returns (bool)
```

Checks if an account is eligible to participate in a proposal vote.
        Confirms that the proposal is open, the account is listed as a member,
        and the account has not previously voted or approved this proposal.

_Reverts if the proposal with the given `_proposalId` does not exist._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal. |
| _account | address | The address of the account to check. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the account is eligible to vote. |

### canExecute

```solidity
function canExecute(uint256 _proposalId) external view virtual returns (bool)
```

Checks if a proposal can be executed.

_Reverts if the proposal with the given `_proposalId` does not exist._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal to be checked. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the proposal can be executed, false otherwise. |

### hasSucceeded

```solidity
function hasSucceeded(uint256 _proposalId) external view virtual returns (bool)
```

Whether proposal succeeded or not.

_Note that this must not include time window checks and only make a decision based on the thresholds._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The id of the proposal. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Returns if proposal has been succeeded or not without including time window checks. |

### getProposal

```solidity
function getProposal(uint256 _proposalId) public view returns (bool executed, uint16 approvals, struct Multisig.ProposalParameters parameters, struct Action[] actions, uint256 allowFailureMap)
```

Returns all information for a proposal by its ID.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| executed | bool | Whether the proposal is executed or not. |
| approvals | uint16 | The number of approvals casted. |
| parameters | struct Multisig.ProposalParameters | The parameters of the proposal. |
| actions | struct Action[] | The actions to be executed in the associated DAO after the proposal has passed. |
| allowFailureMap | uint256 |  |

### hasApproved

```solidity
function hasApproved(uint256 _proposalId, address _account) public view returns (bool)
```

Returns whether the account has approved the proposal.

_May return false if the `_proposalId` or `_account` do not exist,
    as the function does not verify their existence._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal. |
| _account | address | The account address to be checked. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | The vote option cast by a voter for a certain proposal. |

### execute

```solidity
function execute(uint256 _proposalId) public
```

Executes a proposal if all execution conditions are met.

_Requires the `EXECUTE_PROPOSAL_PERMISSION_ID` permission.
Reverts if the proposal is still open or if the minimum approval threshold has not been met._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal to be executed. |

### isMember

```solidity
function isMember(address _account) external view returns (bool)
```

Checks if an account is a member of the DAO.

_This function must be implemented in the plugin contract that introduces the members to the DAO._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _account | address | The address of the account to be checked. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Whether the account is a member or not. |

### _execute

```solidity
function _execute(uint256 _proposalId) internal
```

Internal function to execute a proposal.

_It assumes the queried proposal exists._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal. |

### _canApprove

```solidity
function _canApprove(uint256 _proposalId, address _account) internal view returns (bool)
```

Internal function to check if an account can approve.

_It assumes the queried proposal exists._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal. |
| _account | address | The account to check. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Returns `true` if the given account can approve on a certain proposal and `false` otherwise. |

### _canExecute

```solidity
function _canExecute(uint256 _proposalId) internal view returns (bool)
```

Internal function to check if a proposal can be executed.

_It assumes the queried proposal exists._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _proposalId | uint256 | The ID of the proposal. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | Returns `true` if the proposal can be executed and `false` otherwise. |

### _isProposalOpen

```solidity
function _isProposalOpen(struct Multisig.Proposal proposal_) internal view returns (bool)
```

Internal function to check if a proposal is still open.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proposal_ | struct Multisig.Proposal | The proposal struct. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the proposal is open, false otherwise. |

### _updateMultisigSettings

```solidity
function _updateMultisigSettings(struct Multisig.MultisigSettings _multisigSettings) internal
```

Internal function to update the plugin settings.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _multisigSettings | struct Multisig.MultisigSettings | The new settings. |

