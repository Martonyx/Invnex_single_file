// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USYT is ERC20 {
    address private owner;
    address private converter;

    event ConverterUpdated(address indexed newConverter);

    constructor() ERC20("Invnex USYT", "USYT") {
        owner = msg.sender;
    }

    function setConverter(address _converter) external {
        require(msg.sender == owner, "UnAuthourized");
        require(_converter != address(0), "Invalid address");
        converter = _converter;
        emit ConverterUpdated(_converter);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner || msg.sender == converter, "UnAuthourized");
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function TransferOwnership(address newOwner) external {
        require(msg.sender == owner, "UnAuthourized");
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
}