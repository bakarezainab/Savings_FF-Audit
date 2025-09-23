# TimeLockSavings – Smart Contract Audit Report

## Overview

This audit examines the TimeLockSavings smart contract, a time-locked savings protocol that allows users to deposit ERC20 tokens and earn rewards based on lock duration. The contract includes features for early withdrawal penalties, bonus rewards for extended locking, and administrative functions.

## Executive Summary
The contract contains 1 CRITICAL vulnerabilities, 2 HIGH severity issues, and several MEDIUM/LOW severity problems. The most critical issues include reentrancy vulnerabilities that could lead to fund theft, parameter swapping bugs that cause incorrect reward calculations, and emergency functions that allow owner rug pulls.


## Summary of Findings

| ID | Severity  | Title |
|----|-----------|-------|
| 1  | Critical  | Reward calculation parameter mixup |
| 2  | High  | Emergency withdraw allows owner to steal all funds |
| 3  | High      | No `withdrawn` flag check → double withdrawals |
| 4  | Medium    | Arithmetic overflow in reward calculation |
| 5  | Low    | Incorrect event emission parameter order |
| 6  | Low    | Early withdraw event logs wrong values |
| 7  | Low    | Reentrancy risk in `withdraw` |
| 8  | Low       | Division truncation leads to zero reward for small deposits |
| 9 | Low       | Missing zero address checks |
| 10 | Informational | Deposit design flaw: user cannot top-up existing deposit ID |

---

## Detailed Findings

### 1. Reward Calculation Parameter Mixup (Critical)
**Description:**  
In `withdraw`, reward calculation is called as:
```solidity
uint256 reward = calculateReward(timeElapsed, amount);
```
but calculateReward expects `(amount, timeElapsed)`
This results in incorrect reward payouts.

**Impact:**
Users may receive zero rewards or extremely large values depending on timeElapsed.

Causes financial inconsistencies.

**PoC:**
See `testBug_RewardCalculationParameterMixup` in test suite.
Expected payout ≠ actual payout.

Mitigation:
Swap parameter order in call:
```solidity
uint256 reward = calculateReward(amount, timeElapsed);
```
### 2. Emergency Withdraw Allows Owner to Steal Funds

**Description:**
`emergencyWithdraw` transfers all contract tokens to the owner.

**Impact:** Owner can rug-pull all users.
This is a centralization risk.

**PoC:** See `testBug_EmergencyWithdrawStealsFunds`

**Mitigation:**
Restrict `emergencyWithdraw` to only recover mistakenly sent tokens, not user deposits.
Or disable entirely

### 3. Withdraw Already Withdrawn Deposit

**Description:** No check for `userDeposit.withdrawn` before allowing withdraw
```solidity
require(userDeposit.amount > 0, "No deposit found");
```
User can withdraw repeatedly

**Impact:** Double spend of deposits.

**PoC:** `testBug_WithdrawAlreadyWithdrawnDeposit` → second withdraw does not revert.

**Mitigation:**
Add check:
```solidity
require(!userDeposit.withdrawn, "Already withdrawn");
```

### 4. Arithmetic Overflow in Reward Calculation

**Description:** In extreme cases:
```solidity
uint256 bonusReward = (_amount * BONUS_REWARD_RATE * extraPeriods) / BASIS_POINTS;
``` 
can overflow before division.

**Impact:** In Solidity 0.8+, this reverts. Still a DoS risk if inputs are huge.

**PoC:** `test_ArithmeticOverflowVulnerability` & `test_RewardCalculationOverflow`

**Mitigation:** Use SafeCast or cap inputs

### 5. Incorrect Event Emission Parameter Order

**Description:** 
```solidity
emit Deposited(msg.sender, userDeposits[msg.sender].length - 1, _amount);
```

 But event is defined as `(user, amount, depositId)`

**Impact:** Off-chain consumers (indexers, dapps) get wrong data.

**PoC:** `testBug_IncorrectEventOrder`

**Mitigation:** Fix ordering
```solidity
emit Deposited(msg.sender, _amount, userDeposits[msg.sender].length - 1);
```

### 6. Early Withdraw Event Mismatch

**Description:** Emits `withdrawAmount` instead of original `amount`

**Impact:** Event logs do not match business logic

**PoC:** `testBug_EarlyWithdrawEventMismatch`

**Mitigation:** Fix event to log original `amount`

### 7. Reentrancy in Withdraw

**Description:**
In `withdraw`, the state is updated before external token transfer:

```solidity
userDeposit.withdrawn = true;
totalLocked -= amount;
...
require(token.transfer(msg.sender, totalAmount), "Transfer failed");

```
If the token is malicious and re-enters, attacker can re-withdraw.

**Impact:**

Critical fund drain.

**PoC:**
`test_ReentrancyVulnerability` (commented out in test contract) demonstrates how a malicious token could reenter.

**Mitigation:** Use checks-effects-interactions pattern:

```solidity
userDeposit.withdrawn = true;
...
uint256 oldBalance = token.balanceOf(address(this));
require(token.transfer(msg.sender, totalAMount), "Transfer failed");
require(token.balanceOf(address(this)) == oldBalance - totalAmount, "Invariant failed");

```
Or add `nonReentrant` modifier

### 8. Division Truncation

**Description:** Small deposits (like 1 wei) → reward rounds to 0

**Impact:** Low financial fairness issue

**PoC:** `test_DivisionTruncation`

**Mitigation:** Consider scaling reward rates to minimize truncation

### 9. Missing Zero Address Checks

**Description:** No check in constructor or emergencyWithdraw to ensure addresses ≠ 0

**Impact:** Contract could be deployed with token = address(0)
Funds locked forever.
Mitigation:
Add:
```solidity
require(_token != address(0), "Zero address");
```
### 10. Deposit Design Issue (Informational)

**Description:** Same user making multiple deposits creates separate IDs.
No function to add funds to an existing deposit.

**Impact:** UX limitation, but not a vulnerability
---

## Conclusion

The `TimeLockSavings` contract contains **critical vulnerabilities** including:  
- Wrong reward payouts,  
- Double withdrawals,  
- Reentrancy risk,  
- Owner rug-pull ability.  

These issues pose **severe risks to user funds**

---