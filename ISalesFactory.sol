// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISalesFactory {
    function setSaleOwnerAndToken(address saleOwner, address saleToken) external;
    function isSaleCreatedThroughFactory(address sale) external view returns (bool);
}