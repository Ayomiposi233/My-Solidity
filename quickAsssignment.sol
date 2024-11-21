// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract store {

    struct Animal {string name;}

    Animal[] public names_of_animals;



    function add_animal(string memory name) public {
        names_of_animals.push(Animal(name));
    }
}