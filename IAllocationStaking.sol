// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAllocationStaking {
    function deposited(address _user) external view returns (uint256);
}