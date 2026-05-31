// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BurnMintRebaseTokenPool} from "../src/BurnMintRebaseTokenPool.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RegistryModuleOwnerCustom} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {Script} from "forge-std/Script.sol";

contract TokenAndPoolDeployerScript is Script {

    function run() public returns (RebaseToken token, BurnMintRebaseTokenPool tokenPool) {
        // CCIP Local simulator
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // Network details
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startBroadcast();
        // Deploy token
        token = new RebaseToken();
        // Deploy the token pool
        tokenPool = new BurnMintRebaseTokenPool(
            IERC20(address(token)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );
        // Grant burn and mint role to the token pool
        token.grantMintAndBurnRole(address(tokenPool));
        // Register token admin and accept admin role
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        // Link token to the pool
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(token), address(tokenPool));

        vm.stopBroadcast();
    }

}

contract VaultDeployerScript is Script {

    function run(address _rebaseToken) public returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
    }

}
