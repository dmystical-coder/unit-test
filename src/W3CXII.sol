// SPDX-License-Identifier: MIT
pragma solidity 0.8.13; 

contract W3CXII{
    bool public dosed;
    mapping(address => uint) public balanceOf;
    constructor() payable { }

    function deposit() external payable{
        require(msg.value == 0.5 ether, "InvalidAmount");
        balanceOf[msg.sender] += msg.value;
        if (balanceOf[msg.sender] > 1 ether) {
            revert ("Max deposit exceeded");
        }
        if (address(this).balance >= 2 ether){
            revert ("deposit locked");
        }
    }

    function withdraw() external {
        uint bal = balanceOf[msg.sender];
        require(balanceOf[msg.sender] > 0, "No deposit");
        if(address(this).balance >= 20 ether){
            dosed = true;
            return;
        }
        balanceOf[msg.sender] = 0;
       (bool s,) = msg.sender.call{value: bal}("");
       require(s, "Transfer failed");
    }

    function dest() external {
        require(dosed, "Not dosed"); 
        selfdestruct(payable(msg.sender));
    }
}