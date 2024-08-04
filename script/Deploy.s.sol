// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DZapReward} from "../src/DZapReward.sol";
import {DZapNFT} from "../src/DZapNFT.sol";
import {DZapStaking} from "../src/DZapStaking.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        uint256 rewardPerBlock = 100; 

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("Deployer: ", deployer);
        vm.startBroadcast(deployerKey);

        // deploying DZapReward contract
        DZapReward dZapReward = new DZapReward(deployer);
        console.log("DZapReward deployed at: ", address(dZapReward));

        // deploying DZapNFT contract
        DZapNFT dZapNFT = new DZapNFT(deployer);
        console.log("DZapNFT deployed at: ", address(dZapNFT));

        // deploying DZapStaking implementation contract
        DZapStaking dZapStakingImpl = new DZapStaking();
        console.log("DZapStaking implementation deployed at: ", address(dZapStakingImpl));

        // deploying DZapStaking proxy contract
        bytes memory data = abi.encodeCall(DZapStaking.initialize, (deployer, address(dZapReward), address(dZapNFT), rewardPerBlock));
        ERC1967Proxy dZapStaking = new ERC1967Proxy(address(dZapStakingImpl), data);
        console.log("DZapStaking proxy deployed at: ", address(dZapStaking));

        vm.stopBroadcast();
    }
}
