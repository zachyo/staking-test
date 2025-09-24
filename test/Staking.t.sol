// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/Staking.sol";
import {MockERC20} from "src/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(
            address(stakingToken),
            address(rewardToken)
        );
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(
            address(staking.stakingToken()),
            address(stakingToken),
            "Wrong staking token address"
        );
        assertEq(
            address(staking.rewardsToken()),
            address(rewardToken),
            "Wrong reward token address"
        );

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(
            staking.totalSupply(),
            _totalSupplyBeforeStaking + 5e18,
            "totalsupply didnt update correctly"
        );
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(
            staking.balanceOf(bob),
            userStakebefore - 2e18,
            "Balance didnt update correctly"
        );
        assertLt(
            staking.totalSupply(),
            totalSupplyBefore,
            "total supply didnt update correctly"
        );
    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks));
        assertEq(
            staking.finishAt(),
            uint256(block.timestamp) + uint256(1 weeks)
        );
        assertEq(staking.updatedAt(), block.timestamp);

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    }

    function test_getReward_functionality() public {
        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();

        // Bob stakes
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(
            address(staking),
            type(uint256).max
        );
        staking.stake(10e18);

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        uint256 earnedBefore = staking.earned(bob);
        uint256 balanceBefore = rewardToken.balanceOf(bob);

        staking.getReward();

        assertEq(staking.rewards(bob), 0, "Rewards should be reset to 0");
        assertEq(
            rewardToken.balanceOf(bob),
            balanceBefore + earnedBefore,
            "Should receive rewards"
        );
        vm.stopPrank();
    }

    function test_getReward_with_zero_rewards() public {
        // Test getReward when no rewards are available
        vm.prank(bob);
        staking.getReward(); // Should not revert, just do nothing
        assertEq(staking.rewards(bob), 0, "Rewards should remain 0");
    }

    function test_rewardPerToken_with_zero_totalSupply() public {
        // Test rewardPerToken calculation when totalSupply is 0
        uint256 rewardPerToken = staking.rewardPerToken();
        assertEq(
            rewardPerToken,
            staking.rewardPerTokenStored(),
            "Should return stored value when totalSupply is 0"
        );
    }

    function test_lastTimeRewardApplicable() public {
        // Setup rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);

        // Before any rewards are set, finishAt should be 0
        uint256 lastTime = staking.lastTimeRewardApplicable();
        assertEq(lastTime, 0, "Should return 0 when finishAt is 0");

        deal(address(rewardToken), owner, 100 ether);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();
    }
    
}
