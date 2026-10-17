// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Briefs.fun (BRIEFS)
/// @notice A fixed supply ERC-20 with all tokens minted once to its deployer.
contract BriefsToken is ERC20 {
    /// @notice One billion tokens, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev For a factory deployment, msg.sender is the factory receiving the launch supply.
    constructor() ERC20("Briefs.fun", "BRIEFS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
