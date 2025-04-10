// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Invnex} from "../src/Invnex.sol";

contract DeployInvnex is Script {
    function run() external {
        address usyt = 0x5118055D5d09E237C5524C2375CdE673c080aed2;

        vm.startBroadcast();

        Invnex invnexContract = new Invnex(usyt);

        vm.stopBroadcast();

        console.log("Invnex deployed to:", address(invnexContract));
    }
}