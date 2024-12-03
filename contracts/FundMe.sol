// Get Funds from users
// withdraw funds
// Set minimum finding value in USD

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {PriceConverter} from "./PriceConverter.sol";

contract FundMe{

    using PriceConverter for uint256;

    uint256 public  minimumUsd =5 * 1e18;

    address[] public funders;

    mapping(address funder => uint256 amountFunded) public addressToAmountFunded;

    address public Owner;

    constructor() {
        Owner = msg.sender;
    }

    function fund() public payable {
        msg.value.getConversionRate();
        require(msg.value.getConversionRate() >= minimumUsd, "Didn't send enough ETH");
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

    modifier onlyOwner() {
        require(msg.sender == Owner, "Sender Must Be Owner");
        _;
    }

}