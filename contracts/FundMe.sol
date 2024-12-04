// Get Funds from users
// withdraw funds
// Set minimum finding value in USD

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";

error NotOwner();

contract FundMe{

    using PriceConverter for uint256;

    uint256 public constant MINIMUM_USD =5 * 1e18;

    address[] public funders;

    mapping(address funder => uint256 amountFunded) public addressToAmountFunded;

    address public immutable Owner;

    constructor() {
        Owner = msg.sender;
    }

    function fund() public payable {
        msg.value.getConversionRate();
        require(msg.value.getConversionRate() >= MINIMUM_USD, "Didn't send enough ETH");
        funders.push(msg.sender);
        addressToAmountFunded[msg.sender] += msg.value;
    }

    function withdraw() public onlyOwner {

        for(uint256 FunderIndex=0; FunderIndex < funders.length; FunderIndex++) {
            address funder = funders[FunderIndex];
            addressToAmountFunded[funder] = 0;
        }

        funders = new address[](0);
        (bool CallSuccess, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(CallSuccess, "Call Failed");
    }

    function getVersion() internal view returns(uint256) {
        return AggregatorV3Interface(0xfEefF7c3fB57d18C5C6Cdd71e45D2D0b4F9377bF).version();
    }
    

    modifier onlyOwner() {
        //require(msg.sender == Owner, "Sender Must Be Owner");
        if(msg.sender != Owner) {revert NotOwner();}
        _;
    }

    receive() external payable { 
        fund();
    }

    fallback() external payable { 
        fund();
    }

}