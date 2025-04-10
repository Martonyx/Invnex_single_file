// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Utils} from "../src/utils/InvnexUtils.sol";

contract ERC20Token is ERC20, Utils {
    address public admin;

    constructor() ERC20("", "") {}

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialHolder,
        uint256 initialSupply
    ) external {
        if(admin != address(0)) revert ERC20_AlreadyInitialized();
        if(bytes(name_).length == 0) revert ERC20_EmptyName();
        if(bytes(symbol_).length == 0) revert ERC20_EmptySymbol();

        admin = msg.sender;
        _mint(initialHolder, initialSupply);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}