// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../BaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

import {Multisig} from "../../../src/Multisig.sol";
import {MultisigSetup} from "../../../src/MultisigSetup.sol";
import {CustomExecutorMock} from "../../utils/mocks/CustomExecutorMock.sol";

/// @notice The build metadata is the contract between UIs/scripts and the setup: a UI encodes the setup
///         payloads from these input types. The tests pin the declared types to what the contracts decode.
contract BuildMetadata_UnitTest is BaseTest {
    string internal buildMetadata;
    string internal releaseMetadata;

    function setUp() public override {
        super.setUp();
        buildMetadata = vm.readFile("script/metadata/build-metadata.json");
        releaseMetadata = vm.readFile("script/metadata/release-metadata.json");
    }

    // ==== Helpers ====

    /// @dev Canonical ABI type of the input at `_path` (tuples expanded recursively), e.g. `tuple(bool,uint16)`.
    function _canonicalType(string memory _path) internal view returns (string memory) {
        string memory t = vm.parseJsonString(buildMetadata, string.concat(_path, ".type"));
        if (keccak256(bytes(t)) != keccak256("tuple")) return t;

        string memory inner;
        for (uint256 i;; ++i) {
            string memory component = string.concat(_path, ".components[", vm.toString(i), "]");
            if (!vm.keyExistsJson(buildMetadata, component)) break;
            inner = string.concat(inner, i == 0 ? "" : ",", _canonicalType(component));
        }
        return string.concat("tuple(", inner, ")");
    }

    /// @dev Comma-separated canonical types of all inputs at `_inputsPath`.
    function _signature(string memory _inputsPath) internal view returns (string memory sig) {
        for (uint256 i;; ++i) {
            string memory input = string.concat(_inputsPath, "[", vm.toString(i), "]");
            if (!vm.keyExistsJson(buildMetadata, input)) break;
            sig = string.concat(sig, i == 0 ? "" : ",", _canonicalType(input));
            // Every input documents itself for the UI.
            assertGt(
                bytes(vm.parseJsonString(buildMetadata, string.concat(input, ".description"))).length,
                0,
                string.concat(input, " has no description")
            );
        }
    }

    // ==== prepareInstallation ====

    function test_WhenReadingTheInstallationInputs() external view {
        // it should declare exactly (address[], (bool,uint16), (address,uint8), bytes).
        assertEq(
            _signature(".pluginSetup.prepareInstallation.inputs"),
            "address[],tuple(bool,uint16),tuple(address,uint8),bytes"
        );
    }

    function test_WhenEncodingWithTheDeclaredInstallationTypes() external {
        // it should be accepted by prepareInstallation and land in the right fields.
        CustomExecutorMock executor = new CustomExecutorMock();
        bytes memory data = abi.encode(
            _members(alice, bob),
            _settings(true, 2),
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall}),
            PLUGIN_METADATA
        );

        (address pluginAddress,) = new MultisigSetup().prepareInstallation(address(dao), data);
        Multisig plugin = Multisig(pluginAddress);

        assertEq(plugin.addresslistLength(), 2, "members");
        (bool onlyListed, uint16 minApprovals) = plugin.multisigSettings();
        assertTrue(onlyListed, "onlyListed");
        assertEq(minApprovals, 2, "minApprovals");
        assertEq(plugin.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(plugin.getCurrentTargetConfig().operation), 1, "operation");
        assertEq(plugin.getMetadata(), PLUGIN_METADATA, "metadata");
    }

    // ==== prepareUpdate (keyed by the source build) ====

    function test_WhenReadingTheUpdateKeys() external view {
        // it should only describe updates from builds 1 and 2 (this is build 3).
        string[] memory keys = vm.parseJsonKeys(buildMetadata, ".pluginSetup.prepareUpdate");
        assertEq(keys.length, 2, "keys");
        assertEq(keys[0], "1", "first key");
        assertEq(keys[1], "2", "second key");
        assertFalse(vm.keyExistsJson(buildMetadata, ".pluginSetup.prepareUpdate.3"), "no key 3");
    }

    function test_WhenReadingTheUpdateInputs() external view {
        // it should declare (TargetConfig, bytes) for both legacy builds, matching initializeFrom.
        assertEq(_signature(".pluginSetup.prepareUpdate.1.inputs"), "tuple(address,uint8),bytes", "from 1");
        assertEq(_signature(".pluginSetup.prepareUpdate.2.inputs"), "tuple(address,uint8),bytes", "from 2");
        assertGt(bytes(vm.parseJsonString(buildMetadata, ".pluginSetup.prepareUpdate.1.description")).length, 0);
        assertGt(bytes(vm.parseJsonString(buildMetadata, ".pluginSetup.prepareUpdate.2.description")).length, 0);
    }

    function test_WhenEncodingWithTheDeclaredUpdateTypes() external {
        // it should be decoded by initializeFrom (the init data the setup returns for builds 1 and 2).
        CustomExecutorMock executor = new CustomExecutorMock();
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.Call});
        bytes memory data = abi.encode(target, PLUGIN_METADATA);

        for (uint16 fromBuild = 1; fromBuild <= 2; ++fromBuild) {
            (bytes memory initData,) = new MultisigSetup().prepareUpdate(address(dao), fromBuild, _payload(data));
            // A bare proxy stands in for a build 1/2 proxy (initializer version below 2).
            Multisig bare = Multisig(address(new ERC1967Proxy(address(new Multisig()), "")));
            (bool ok,) = address(bare).call(initData);
            assertTrue(ok, "initializeFrom");
            assertEq(bare.getCurrentTargetConfig().target, address(executor), "target");
            assertEq(bare.getMetadata(), PLUGIN_METADATA, "metadata");
        }
    }

    function test_WhenReadingTheUninstallationInputs() external view {
        // it should declare no inputs.
        assertEq(_signature(".pluginSetup.prepareUninstallation.inputs"), "");
    }

    // ==== Release metadata ====

    function test_WhenReadingTheReleaseMetadata() external view {
        // it should have a non-empty name and description.
        assertGt(bytes(vm.parseJsonString(releaseMetadata, ".name")).length, 0, "name");
        assertGt(bytes(vm.parseJsonString(releaseMetadata, ".description")).length, 0, "description");
    }

    function _payload(bytes memory _data) internal view returns (IPluginSetup.SetupPayload memory) {
        return IPluginSetup.SetupPayload({plugin: address(multisig), currentHelpers: new address[](0), data: _data});
    }
}
