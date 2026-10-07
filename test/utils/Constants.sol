// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @notice Values the tests assert against. Computed from their definitions (strings and signatures),
///         never read from the contracts under test, so that a change in the contracts is caught.
abstract contract Constants {
    // Permissions
    bytes32 internal constant ROOT_PERMISSION_ID = keccak256("ROOT_PERMISSION");
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 internal constant UPDATE_MULTISIG_SETTINGS_PERMISSION_ID = keccak256("UPDATE_MULTISIG_SETTINGS_PERMISSION");
    bytes32 internal constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 internal constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");
    bytes32 internal constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");
    bytes32 internal constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");
    bytes32 internal constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");

    address internal constant ANY_ADDR = address(type(uint160).max);
    address internal constant NO_CONDITION = address(0);

    // ERC-165 interface IDs
    bytes4 internal constant IERC165_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 internal constant IPLUGIN_ID = bytes4(keccak256("pluginType()"));
    bytes4 internal constant IPROTOCOL_VERSION_ID = bytes4(keccak256("protocolVersion()"));
    bytes4 internal constant IERC1822_ID = bytes4(keccak256("proxiableUUID()"));
    bytes4 internal constant TARGET_CONFIG_ID = bytes4(keccak256("setTargetConfig((address,uint8))"))
        ^ bytes4(keccak256("getTargetConfig()")) ^ bytes4(keccak256("getCurrentTargetConfig()"));
    bytes4 internal constant METADATA_EXTENSION_ID =
        bytes4(keccak256("setMetadata(bytes)")) ^ bytes4(keccak256("getMetadata()"));
    bytes4 internal constant IMEMBERSHIP_ID = bytes4(keccak256("isMember(address)"));
    bytes4 internal constant ADDRESSLIST_ID = bytes4(keccak256("isListedAtBlock(address,uint256)"))
        ^ bytes4(keccak256("isListed(address)")) ^ bytes4(keccak256("addresslistLengthAtBlock(uint256)"))
        ^ bytes4(keccak256("addresslistLength()"));
    bytes4 internal constant IPROPOSAL_CREATE_SELECTOR =
        bytes4(keccak256("createProposal(bytes,(address,uint256,bytes)[],uint64,uint64,bytes)"));
    bytes4 internal constant IPROPOSAL_ID = IPROPOSAL_CREATE_SELECTOR ^ bytes4(keccak256("hasSucceeded(uint256)"))
        ^ bytes4(keccak256("execute(uint256)")) ^ bytes4(keccak256("canExecute(uint256)"))
        ^ bytes4(keccak256("customProposalParamsABI()")) ^ bytes4(keccak256("proposalCount()"));
    /// @dev OSx v1.0 IProposal (only `proposalCount()`), still advertised by `ProposalUpgradeable` for compatibility.
    bytes4 internal constant IPROPOSAL_LEGACY_ID = bytes4(keccak256("proposalCount()"));
    bytes4 internal constant IMULTISIG_ID = bytes4(keccak256("addAddresses(address[])"))
        ^ bytes4(keccak256("removeAddresses(address[])")) ^ bytes4(keccak256("approve(uint256,bool)"))
        ^ bytes4(keccak256("canApprove(uint256,address)")) ^ bytes4(keccak256("canExecute(uint256)"))
        ^ bytes4(keccak256("hasApproved(uint256,address)")) ^ bytes4(keccak256("execute(uint256)"));
    bytes4 internal constant MULTISIG_ID = bytes4(keccak256("updateMultisigSettings((bool,uint16))"))
        ^ bytes4(keccak256("createProposal(bytes,(address,uint256,bytes)[],uint256,bool,bool,uint64,uint64)"))
        ^ bytes4(keccak256("getProposal(uint256)"));

    // ERC-1967
    bytes32 internal constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // Defaults
    bytes internal constant PLUGIN_METADATA = "ipfs://plugin-metadata";
    bytes internal constant PROPOSAL_METADATA = "ipfs://proposal-metadata";
    uint256 internal constant START_BLOCK = 100;
    uint256 internal constant START_TIMESTAMP = 1_700_000_000;
    uint64 internal constant PROPOSAL_DURATION = 7 days;
}
