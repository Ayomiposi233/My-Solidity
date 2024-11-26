// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Giveaway{
    

    struct Wallet {
        string Name;
        uint256 EtherAmount;
        address InputAddress;
        bool ConfirmRequest;
    }

    Wallet[] public ListOfWallets;


    mapping(string Name => address InputAddress) public AddressToBalance;


    function AddWallet(string memory Name, uint256 EtherAmount, address InputAddress, bool ConfirmRequest) public {
        ListOfWallets.push(Wallet(Name, EtherAmount, InputAddress, ConfirmRequest));
        AddressToBalance[Name] = InputAddress;
    }

}