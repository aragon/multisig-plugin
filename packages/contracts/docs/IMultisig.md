# Solidity API

## IMultisig

An interface for an on-chain multisig governance plugin in which a proposal passes
if X out of Y approvals are met.

### addAddresses

```solidity
function addAddresses(address[] _members) external
```

Adds new members to the address list. Previously, it checks if the new address
list length would be greater than `type(uint16).max`, the maximal number of approvals.

#### Parameters

| Name      | Type      | Description                               |
| --------- | --------- | ----------------------------------------- |
| \_members | address[] | The addresses of the members to be added. |

### removeAddresses

```solidity
function removeAddresses(address[] _members) external
```

Removes existing members from the address list. Previously, it checks if the
new address list length is at least as long as the minimum approvals parameter requires.
Note that `minApprovals` is must be at least 1 so the address list cannot become empty.

#### Parameters

| Name      | Type      | Description                                 |
| --------- | --------- | ------------------------------------------- |
| \_members | address[] | The addresses of the members to be removed. |

### approve

```solidity
function approve(uint256 _proposalId, bool _tryExecution) external
```

Records an approval for a proposal and, if specified, attempts execution if certain conditions are met.

#### Parameters

| Name           | Type    | Description                                                                                 |
| -------------- | ------- | ------------------------------------------------------------------------------------------- |
| \_proposalId   | uint256 | The ID of the proposal to approve.                                                          |
| \_tryExecution | bool    | If `true`, attempts execution of the proposal after approval, without reverting on failure. |

### canApprove

```solidity
function canApprove(uint256 _proposalId, address _account) external view returns (bool)
```

Checks if an account is eligible to participate in a proposal vote.
Confirms that the proposal is open, the account is listed as a member,
and the account has not previously voted or approved this proposal.

#### Parameters

| Name         | Type    | Description                          |
| ------------ | ------- | ------------------------------------ |
| \_proposalId | uint256 | The ID of the proposal.              |
| \_account    | address | The address of the account to check. |

#### Return Values

| Name | Type | Description                              |
| ---- | ---- | ---------------------------------------- |
| [0]  | bool | True if the account is eligible to vote. |

### canExecute

```solidity
function canExecute(uint256 _proposalId) external view returns (bool)
```

Checks if a proposal can be executed.

#### Parameters

| Name         | Type    | Description                           |
| ------------ | ------- | ------------------------------------- |
| \_proposalId | uint256 | The ID of the proposal to be checked. |

#### Return Values

| Name | Type | Description                                            |
| ---- | ---- | ------------------------------------------------------ |
| [0]  | bool | True if the proposal can be executed, false otherwise. |

### hasApproved

```solidity
function hasApproved(uint256 _proposalId, address _account) external view returns (bool)
```

Returns whether the account has approved the proposal.

#### Parameters

| Name         | Type    | Description                        |
| ------------ | ------- | ---------------------------------- |
| \_proposalId | uint256 | The ID of the proposal.            |
| \_account    | address | The account address to be checked. |

#### Return Values

| Name | Type | Description                                             |
| ---- | ---- | ------------------------------------------------------- |
| [0]  | bool | The vote option cast by a voter for a certain proposal. |

### execute

```solidity
function execute(uint256 _proposalId) external
```

Executes a proposal if all execution conditions are met.

#### Parameters

| Name         | Type    | Description                            |
| ------------ | ------- | -------------------------------------- |
| \_proposalId | uint256 | The ID of the proposal to be executed. |
