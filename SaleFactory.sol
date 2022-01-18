// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeakDefiSale.sol";


contract SalesFactory {

    address public allocationStaking;
    address public admin;

    mapping (address => bool) public isSaleCreatedThroughFactory;

    // Expose so query can be possible only by position as well
    address [] public allSales;

    event SaleDeployed(address saleContract);

    modifier onlyAdmin() {
        require(
            msg.sender == admin ,
            "Only admin can call this function."
        );
        _;
    }

    constructor (address _adminAddress, address _allocationStaking)  {
        admin = _adminAddress;
        allocationStaking = _allocationStaking;
    }

    // Set allocation staking contract address.
    function setAllocationStaking(address _allocationStaking) public onlyAdmin {
        require(_allocationStaking != address(0));
        allocationStaking = _allocationStaking;
    }


    function deploySale()
    external
    onlyAdmin
    {
        PeakDefiSale sale = new PeakDefiSale(address(admin), allocationStaking);

        isSaleCreatedThroughFactory[address(sale)] = true;
        allSales.push(address(sale));

        emit SaleDeployed(address(sale));
    }

    // Function to return number of pools deployed
    function getNumberOfSalesDeployed() external view returns (uint) {
        return allSales.length;
    }

    // Function
    function getLastDeployedSale() external view returns (address) {
        //
        if(allSales.length > 0) {
            return allSales[allSales.length - 1];
        }
        return address(0);
    }


    // Function to get all sales in interval
    function getAllSales(uint startIndex, uint endIndex) external view returns (address[] memory) {
        require(endIndex > startIndex, "Bad input");
        require(endIndex < allSales.length, "Request more sale than created");

        address[] memory sales = new address[](endIndex - startIndex);
        uint index = 0;

        for(uint i = startIndex; i < endIndex; i++) {
            sales[index] = allSales[i];
            index++;
        }

        return sales;
    }

}