// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

/// @dev `script/metadata/new-version-proposal-metadata.json` follows the proposal metadata schema used by
///      the other Aragon plugins: title, summary, description and resources ({name, url}).
contract ProposalMetadata_UnitTest is Test {
    string internal json;

    function setUp() public {
        json = vm.readFile("script/metadata/new-version-proposal-metadata.json");
    }

    function test_WhenReadingTheTextFields() external view {
        // it should have a non-empty title, summary and description.
        assertGt(bytes(vm.parseJsonString(json, ".title")).length, 0, "title");
        assertGt(bytes(vm.parseJsonString(json, ".summary")).length, 0, "summary");
        assertGt(bytes(vm.parseJsonString(json, ".description")).length, 0, "description");
    }

    function test_WhenReadingTheResources() external view {
        // it should list resources with a name and an https URL.
        uint256 count;
        while (vm.keyExistsJson(json, string.concat(".resources[", vm.toString(count), "]"))) {
            string memory path = string.concat(".resources[", vm.toString(count), "]");
            assertGt(bytes(vm.parseJsonString(json, string.concat(path, ".name"))).length, 0, "name");
            assertEq(vm.indexOf(vm.parseJsonString(json, string.concat(path, ".url")), "https://"), 0, "https url");
            assertEq(vm.parseJsonKeys(json, path).length, 2, "only name and url");
            ++count;
        }
        assertGt(count, 0, "resources");
    }

    function test_WhenReadingTheKeys() external view {
        // it should contain only the schema keys.
        string[] memory keys = vm.parseJsonKeys(json, "$");
        assertEq(keys.length, 4, "key count");
        for (uint256 i; i < keys.length; ++i) {
            bytes32 key = keccak256(bytes(keys[i]));
            assertTrue(
                key == keccak256("title") || key == keccak256("summary") || key == keccak256("description")
                    || key == keccak256("resources"),
                keys[i]
            );
        }
    }
}
