// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Cheoma} from "../src/Cheoma.sol";

/// Deploy CHEOMA to GIWA Sepolia:
///   forge script script/Deploy.s.sol --rpc-url https://sepolia-rpc.giwa.io --broadcast
/// Env: PRIVATE_KEY, ROOF_FUND (defaults to deployer)
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address fund = vm.envOr("ROOF_FUND", vm.addr(pk));
        vm.startBroadcast(pk);
        Cheoma cheoma = new Cheoma(fund);
        vm.stopBroadcast();
        console.log("CHEOMA deployed at", address(cheoma));
        console.log("roofFund", fund);
    }
}
