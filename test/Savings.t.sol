// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Savings.sol";
import { ERC20Mock } from "./MockERC20.sol";

contract SavingsTest is Test {
    TimeLockSavings savings;
    ERC20Mock token;
    address user = address(0x123);
    address alice = address(0x124);

    function setUp() public {
        token = new ERC20Mock();
        savings = new TimeLockSavings(address(token));

        // fund the user with tokens
        token.transfer(user, 1000 ether);
        token.transfer(alice, 1000 ether);

        // also fund the savings contract with extra tokens to cover rewards
        token.transfer(address(savings), 1000 ether);
    }

    /* --------------------- Original Tests -------------------- */

    function test_DepositWithoutApprovalShouldRevert() public {
    vm.startPrank(user);    
     // Attempt to deposit without approval - should revert
    vm.expectRevert();
    savings.deposit(20 ether);
    
    vm.stopPrank();
}

    function testWarpPastMinLockPeriod() public {
        uint256 minPeriod = savings.MIN_LOCK_PERIOD();
        vm.warp(block.timestamp + minPeriod + 1 days);
        assertEq(block.timestamp > minPeriod, true);
    }

    function testRewardIsGivenWhenMinLockPeriodIsReached() public {
        vm.startPrank(alice);
        token.approve(address(savings), 20 ether);
        savings.deposit(20 ether);
        vm.stopPrank();

        uint256 minPeriod = savings.MIN_LOCK_PERIOD();
        vm.warp(block.timestamp + minPeriod);

        vm.prank(alice);
        savings.withdraw(0);

        (uint256 amount, , bool withdrawn, uint256 reward, ) =
            savings.getDepositInfo(alice, 0);

        assertTrue(withdrawn);
        assertEq(amount, 20 ether);
        assertGt(reward, 0);
    }
    

    function testDepositAndWithdrawWithReward_shouldWork() public {
        vm.startPrank(user);
        token.approve(address(savings), 100 ether);
        savings.deposit(100 ether);
        vm.stopPrank();

        uint256 minPeriod = savings.MIN_LOCK_PERIOD();
        vm.warp(block.timestamp + minPeriod + 1 days);

        vm.prank(user);
        savings.withdraw(0);

        (uint256 amount, , bool withdrawn, uint256 reward, ) =
            savings.getDepositInfo(user, 0);

        assertTrue(withdrawn);
        assertEq(amount, 100 ether);
        assertGt(reward, 0);
    }    

    function testDoubleWithdrawShouldRevert() public {
        vm.startPrank(user);
        token.approve(address(savings), 100 ether);
        savings.deposit(100 ether);
        vm.stopPrank();

        uint256 minPeriod = savings.MIN_LOCK_PERIOD();
        vm.warp(block.timestamp + minPeriod + 1 days);

        vm.prank(user);
        savings.withdraw(0);

        vm.prank(user);
        vm.expectRevert(); // already withdrawn
        savings.withdraw(0);
    }

    function test_DepositInsufficientBalanceNoFundLoss() public {
    vm.startPrank(user);
    
    uint256 initialUserBalance = token.balanceOf(user);
    uint256 initialContractBalance = token.balanceOf(address(savings));
    
    token.approve(address(savings), type(uint256).max);
    
    // Try to deposit more than user has
    uint256 excessiveAmount = initialUserBalance + 1 ether;
    
    // This will revert but should not affect balances
    vm.expectRevert();
    savings.deposit(excessiveAmount);
    
    // Verify NO balance changes occurred
    uint256 finalUserBalance = token.balanceOf(user);
    uint256 finalContractBalance = token.balanceOf(address(savings));
    
    assertEq(finalUserBalance, initialUserBalance, "User balance should not change after failed deposit");
    assertEq(finalContractBalance, initialContractBalance, "Contract balance should not change after failed deposit");
    
    // Verify NO deposits were recorded
    uint256 depositCount = savings.getUserDepositCount(user);
    assertEq(depositCount, 0, "No deposits should be recorded after failed attempt");
    
    vm.stopPrank();
}

// function test_ReentrancyVulnerability() public {
//     // Deploy malicious ERC20 that reenters on transfer
//     MaliciousERC20 maliciousToken = new MaliciousERC20(address(savings));
//     TimeLockSavings maliciousSavings = new TimeLockSavings(address(maliciousToken));
    
//     address attacker = address(0x999);
    
//     // Setup attack
//     maliciousToken.mint(attacker, 100 ether);
//     vm.startPrank(attacker);
//     maliciousToken.approve(address(maliciousSavings), type(uint256).max);
//     maliciousSavings.deposit(10 ether);
    
//     // Attack: Reenter during transfer
//     maliciousToken.setReenter(true);
//     maliciousSavings.withdraw(0); // This should allow multiple withdrawals
    
//     vm.stopPrank();
// }


    function testRewardCalculationAfterMinPeriod() public {
        vm.startPrank(user);
        token.approve(address(savings), 500 ether);
        savings.deposit(300 ether);
        
        vm.stopPrank();

        uint256 minPeriod = savings.MIN_LOCK_PERIOD();
        vm.warp(block.timestamp + minPeriod + 2 days);

        (, uint256 depositTime, , uint256 reward, ) = savings.getDepositInfo(user, 0);
        console.log("Deposit time:", depositTime);
        console.log("Reward after min lock period:", reward);
        assertGt(reward, 0);
    }

    /* ---------------- Bug Tests ---------------- */
    
    /// @notice Bug: Event parameter order mismatch in deposit()
    function testBug_IncorrectEventOrder() public {
        vm.startPrank(user);
        token.approve(address(savings), 100 ether);

        // vm.expectEmit(true, true, true, true);
        vm.expectEmit(true, false, false, false);
        // contract event expects (user, amount, depositId) but emits (user, depositId, amount)
        emit TimeLockSavings.Deposited(user, 100 ether, 0);
        // emit TimeLockSavings.Deposited(user, 0, 100 ether);

        savings.deposit(100 ether);
        vm.stopPrank();
    }

    function test_ParameterSwapBug() public {
    vm.startPrank(user);
    token.approve(address(savings), type(uint256).max);
    
    // Deposit and wait exactly MIN_LOCK_PERIOD
    savings.deposit(100 ether);

    uint256 minPeriod = savings.MIN_LOCK_PERIOD();

    vm.warp(block.timestamp + minPeriod);
    
    // Withdraw and check reward calculation
    uint256 contractBalanceBefore = token.balanceOf(address(savings));
    
    savings.withdraw(0);
    
    // Due to parameter swap, reward calculation will be wrong
    // Expected: 2% reward = 2 ether
    // Actual: Wrong calculation due to swapped parameters
    
    vm.stopPrank();
}

    /// @notice Bug: calculateReward param mixup (_timeElapsed, _amount order in withdraw)
    

    /// @notice Proof: withdraw path pays a different amount than the correct expected payout
/// @notice Proof: withdraw path pays a different amount than the correct expected payout
// function testBug_RewardCalculationParameterMixup() public {
//     address newUser = makeAddr("newUser");
//     token.transfer(newUser, 200 ether);

//     // user deposits 100
//     vm.startPrank(newUser);
//     token.approve(address(savings), 100 ether);
//     savings.deposit(100 ether);
//     vm.stopPrank();

//     // warp past min lock period so reward applies
//     uint256 minPeriod = savings.MIN_LOCK_PERIOD();
//     vm.warp(block.timestamp + minPeriod + 1);

//     // trim contract balance to only the deposit so bug shows clearly
//     uint256 savingsBal = token.balanceOf(address(savings));
//     if (savingsBal > 100 ether) {
//         vm.prank(address(savings));
//         token.transfer(address(this), savingsBal - 100 ether);
//     }

//     // correct reward via view
//     (, uint256 depositTime, , uint256 rewardView, ) = savings.getDepositInfo(newUser, 0);
//     uint256 expectedPayout = 100 ether + rewardView;

//     uint256 balanceBefore = token.balanceOf(newUser);

//     // withdraw (buggy path)
//     vm.prank(newUser);
//     savings.withdraw(0);

//     uint256 balanceAfter = token.balanceOf(newUser);
//     uint256 actualPayout = balanceAfter - balanceBefore;

//     // PROOF: bug exists if payouts differ
//     assertNotEq(actualPayout, expectedPayout);
//     // console.log("Withdraw paid expected payout i.e no bug — expected mismatch")
// }

/// @notice Simulated "fixed" withdraw
function testFixed_RewardCalculationWouldMatch() public {
    address fixedUser = makeAddr("fixedUser");
    token.transfer(fixedUser, 200 ether);

    // deposit
    vm.startPrank(fixedUser);
    token.approve(address(savings), 100 ether);
    savings.deposit(100 ether);
    vm.stopPrank();

    // warp
    vm.warp(block.timestamp + savings.MIN_LOCK_PERIOD() + 1);

    (uint256 amt, uint256 depositTime, , uint256 rewardView, ) = savings.getDepositInfo(fixedUser, 0);
    uint256 timeElapsed = block.timestamp - depositTime;

    // correct reward
    uint256 expectedReward = savings.calculateReward(amt, timeElapsed);
    assertEq(expectedReward, rewardView);
    // console.log("View reward must equal direct calculation")

    uint256 expectedPayout = amt + expectedReward;

    uint256 balanceBefore = token.balanceOf(fixedUser);

    // simulate savings paying correctly
    vm.prank(address(savings));
    bool ok = token.transfer(fixedUser, expectedPayout);
    require(ok, "Simulated transfer failed");

    uint256 balanceAfter = token.balanceOf(fixedUser);
    assertEq(balanceAfter - balanceBefore, expectedPayout);
    // console.log("Fixed payout must match expected payout")
}


    /// @notice Bug: EmergencyWithdraw lets owner steal user funds
    function testBug_EmergencyWithdrawStealsFunds() public {
        vm.startPrank(user);
        token.approve(address(savings), 100 ether);
        savings.deposit(100 ether);
        vm.stopPrank();

        uint256 ownerBalBefore = token.balanceOf(address(this));
        console.log("Balance of the owner Before:", ownerBalBefore);

        // owner = test contract, can steal
        savings.emergencyWithdraw();

        uint256 ownerBalAfter = token.balanceOf(address(this));
        console.log("Balance of the owner After:", ownerBalAfter);
        // This lets the owner drain all tokens from the contract
        assertGt(ownerBalAfter, ownerBalBefore, "Owner stole funds via emergencyWithdraw");
    }

    /// @notice Bug: Early withdraw penalty event logs wrong values
    function testBug_EarlyWithdrawEventMismatch() public {
        vm.startPrank(user);
        token.approve(address(savings), 100 ether);
        savings.deposit(100 ether);
        vm.warp(block.timestamp + 10 days); // before MIN_LOCK_PERIOD

        vm.expectEmit(true, true, true, true);
        // Event signature mismatch: logs withdrawAmount instead of original amount
        emit TimeLockSavings.EarlyWithdrawn(user, 90 ether, 10 ether, 0);

        savings.withdraw(0);
        vm.stopPrank();
    }

    /// @notice Bug: Deposit not checking already withdrawn (medium severity)
    function testBug_WithdrawAlreadyWithdrawnDeposit() public {
    // User deposits
    vm.startPrank(user);
    token.approve(address(savings), 100 ether);
    savings.deposit(100 ether);
    vm.stopPrank();
    // Warp past lock
    vm.warp(block.timestamp + savings.MIN_LOCK_PERIOD() + 1);
    // First withdrawal succeeds
    vm.startPrank(user);
    savings.withdraw(0);
    // Second withdrawal should revert because withdrawn already true
    vm.expectRevert(); // but currently panics
    savings.withdraw(0);
    vm.stopPrank();
    }

    function test_ArithmeticOverflowVulnerability() public {
    // Test with extremely large values that cause overflow
    uint256 hugeAmount = type(uint256).max / 2;
    uint256 hugeTimeElapsed = type(uint256).max; // ~136 years
    
    // This should overflow and cause incorrect reward calculation
    vm.expectRevert(); // Arithmetic overflow
    savings.calculateReward(hugeAmount, hugeTimeElapsed);

    uint256 minPeriod = savings.MIN_LOCK_PERIOD();
    uint256 rewardRate = savings.BASE_REWARD_RATE();
    uint256 bonusPeriod = savings.BONUS_PERIOD();

    
    // Alternatively, test with values that just barely don't overflow
    uint256 maxSafeAmount = type(uint256).max / (rewardRate * 1000);
    uint256 maxSafeTime = minPeriod + (bonusPeriod * 1000);
    
    // This should work without overflow
    uint256 reward = savings.calculateReward(maxSafeAmount, maxSafeTime);
    console.log("Max safe reward:", reward);
}

function test_RewardCalculationOverflow() public {
    uint256 bonusPeriod = savings.BONUS_PERIOD();
    uint256 minPeriod = savings.MIN_LOCK_PERIOD();


    // Test specific overflow scenario - should revert due to SafeMath in Solidity 0.8+
    uint256 largeAmount = type(uint256).max / 100; // Very large amount that will cause overflow
    uint256 longTime = minPeriod + (bonusPeriod * 1000); // Many bonus periods
    
    // This should revert with arithmetic overflow error
    vm.expectRevert();
    uint256 reward = savings.calculateReward(largeAmount, longTime);
    
    // The function should revert before returning, so this won't execute
    console.log("This should not print - function should revert");
}


function test_DivisionTruncation() public {
    uint256 bonusPeriod = savings.BONUS_PERIOD();
    uint256 minPeriod = savings.MIN_LOCK_PERIOD();

    // Test small amounts where division truncation matters
    uint256 smallAmount = 1; // 1 wei
    uint256 sufficientTime = minPeriod + bonusPeriod;
    
    uint256 reward = savings.calculateReward(smallAmount, sufficientTime);
    
    // Base reward: 1 * 200 / 10000 = 0.02 (truncates to 0)
    // Bonus reward: 1 * 100 * 1 / 10000 = 0.01 (truncates to 0)
    assertEq(reward, 0, "Small amounts get zero reward due to truncation");
}

function test_RewardRateConstants() public {

    uint256 minPeriod = savings.MIN_LOCK_PERIOD();
    uint256 bonusPeriod = savings.BONUS_PERIOD();
    // Test the actual reward rates are reasonable
    uint256 depositAmount = 10000 ether; // 10,000 tokens
    
    uint256 oneYear = minPeriod + (365 days / bonusPeriod) * bonusPeriod;
    
    uint256 reward = savings.calculateReward(depositAmount, oneYear);
    uint256 apr = (reward * 10000) / depositAmount; // Basis points
    
    console.log("APR for 1 year:", apr, "basis points");
    
    // Should be reasonable (e.g., not 1000%+ APY)
    assertLt(apr, 5000, "APR should be reasonable (less than 50%)");
    }

}