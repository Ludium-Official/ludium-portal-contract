// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract USDC is ERC20, Ownable, ERC20Permit {
    constructor(
        address initialOwner
    ) ERC20("USDC", "USDC") Ownable(initialOwner) ERC20Permit("USDC") {
        // 초기 공급량: 1,000,000 USDC (6 decimals)
        _mint(initialOwner, 1000000 * 10 ** 6);
    }

    // 6 decimals (실제 USDC와 동일)
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
