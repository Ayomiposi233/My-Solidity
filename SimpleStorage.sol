// SPDX-License-Identifier: MIT
pragma solidity 0.8.19; // stating our solidity version


contract SimpleStorage {

    uint256 favouriteNumber = 9;

    uint256[] public list_of_favourite_numbers = [1, 69, 87]; // State Variable, when a visibility specifier isnt given, it defaults to internal, Arrays are zero-indexed

    struct person {
        uint256 favourite_number;
        string name;
    }

    person public my_friend = person({favourite_number: 8, name: 'Tofunmi'});

    person[] public listofpeople;

    function store(uint256 _favouriteNumber) public {
        favouriteNumber = _favouriteNumber; // Local Variable in Function 
    }

    function retrieve() public view returns(uint256){
        return favouriteNumber; // view function can only call a state variable and not local and it can not alter the variable while pure function cannot call a state variable or alter and therefore must be explicitly specified. 
    }

    function add_person(string memory name, uint256 favourite_number) public {
        listofpeople.push(person(favourite_number, name));
}

}