// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PeakDefiSale.sol";


contract SalesFactory {

    address public allocationStaking;
    address public admin;

    mapping (address => bool) public isSaleCreatedThroughFactory;

    address [] public allSales;

    modifier onlyAdmin() {
        require(
            msg.sender == admin ,
            "Only admin can call this function."
        );
        _;
    }

    constructor (address _adminAddress, address _allocationStaking)  {
        require(_adminAddress != address(0), "error admin");
        require(_allocationStaking != address(0), "error staking");
        admin = _adminAddress;
        allocationStaking = _allocationStaking;
    }

    function setAllocationStaking(address _allocationStaking) public onlyAdmin {
        require(_allocationStaking != address(0), "address error");
        allocationStaking = _allocationStaking;
    }


    function deploySale()
    external
    onlyAdmin
    {
        PeakDefiSale sale = new PeakDefiSale(address(admin), allocationStaking);

        isSaleCreatedThroughFactory[address(sale)] = true;
        allSales.push(address(sale));
    }

    function getNumberOfSalesDeployed() external view returns (uint) {
        return allSales.length;
    }

    function getLastDeployedSale() external view returns (address) {
        //
        if(allSales.length > 0) {
            return allSales[allSales.length - 1];
        }
        return address(0);
    }


    function getAllSales(uint startIndex, uint endIndex) external view returns (address[] memory) {
        require(endIndex > startIndex, "Bad input");
        require(endIndex <= allSales.length, "Request more sale than created");

        address[] memory sales = new address[](endIndex - startIndex);
        uint index = 0;

        for(uint i = startIndex; i < endIndex; i++) {
            sales[index] = allSales[i];
            index++;
        }

        return sales;
    }

}