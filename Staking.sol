//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract StakingRewards is Ownable {
    IERC20 public rewardsToken;
    IERC1155 public mouseToken;

    struct RewardChanged {
        uint block;
        uint rewardPerBlock;
    }

    RewardChanged[] rewardChanges; 

    uint public rewardPerBlock;

    mapping(address => uint) private mouseBalance;
    mapping(address => uint) public rewards;
    mapping(address => uint) public lastWithdraw;
    mapping(address => uint) public lastUpdatedBlock;

    address private catPool;

    constructor(address _mouseToken, address _rewardsToken, address _catPool, uint _rewardPerBlock) {
        mouseToken = IERC1155(_mouseToken);
        rewardsToken = IERC20(_rewardsToken);
        catPool = _catPool;
        rewardPerBlock = _rewardPerBlock;
        rewardChanges.push(RewardChanged(uint(block.number), _rewardPerBlock));
    }     

    function calculateRewards() public view returns (uint _rewards) {
        uint _blocksPassed;

        uint _rewardsRate = rewardPerBlock; 
        uint _currentBal = rewards[msg.sender];
        uint _mouseBalance = mouseBalance[msg.sender]; 
        uint updateBlockQueue = rewardChanges.length;

        uint _lastUpdatedBlock = lastUpdatedBlock[msg.sender];

        if (_lastUpdatedBlock > updateBlockQueue) {
        _blocksPassed = block.number - _lastUpdatedBlock;
        _rewards = _mouseBalance * _blocksPassed * _rewardsRate + _currentBal;
        return _rewards;
        }
        else {
            _rewards = rewards[msg.sender];
            while (rewardChanges[updateBlockQueue].block > _lastUpdatedBlock) {
                _rewards += _mouseBalance * (block.number - rewardChanges[updateBlockQueue].block) * rewardChanges[updateBlockQueue].rewardPerBlock;
                updateBlockQueue -= 1;
            }
        return _rewards;
        }
    }

    function setRewardsPerBlock(uint _rewardPerBlock) public onlyOwner {
        rewardPerBlock = _rewardPerBlock;
        rewardChanges.push(RewardChanged(block.number, _rewardPerBlock));
    }

    function stake(uint _id, uint _amount) external {
        mouseBalance[msg.sender] += _amount;
        mouseToken.safeTransferFrom(msg.sender, address(this), _id, _amount, "");
        lastUpdatedBlock[msg.sender] = block.number;
        rewards[msg.sender] = calculateRewards();
    }

    function withdraw(uint _id, uint _amount) external {
        // require 2 days of staking before a full withdraw
        // harmony one blocks occur every two seconds
        require((block.number - lastWithdraw[msg.sender]) > 2073600);
        calculateRewards();

        lastWithdraw[msg.sender] = block.number;
        lastUpdatedBlock[msg.sender] = block.number;

        uint reward = rewards[msg.sender];
        rewards[msg.sender] = 0;

        mouseBalance[msg.sender] -= _amount;
        mouseToken.safeTransferFrom(address(this), msg.sender, _amount, _id, "");

        // 50% chance to lose your tokens to the cat pool
        uint rand = (uint(vrf()) % 2);
        if (rand == 0) {
            rewardsToken.transfer(msg.sender, reward);
        }
        else {
            rewardsToken.transfer(catPool, reward);
        }
    }

    function getReward() external {
        calculateRewards();
        uint reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        // 20% extortion fee paid to cat pool
        rewardsToken.transfer(msg.sender, reward * 4 / 5);
        rewardsToken.transfer(catPool, reward * 1 / 5);
        lastWithdraw[msg.sender] = block.number;
    }

    // harmony one VRF function
    function vrf() public view returns (bytes32 result) {
        uint[1] memory bn;
        bn[0] = block.number;
        assembly {
            let memPtr := mload(0x40)
            if iszero(staticcall(not(0), 0xff, bn, 0x20, memPtr, 0x20)) {
            invalid()
        }
        result := mload(memPtr)
        }
    }
}