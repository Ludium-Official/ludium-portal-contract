// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILdInvestmentProgram {
    function acceptMilestone(uint256 _projectId, uint256 _milestoneIndex) external;
    function reclaimFund(uint256 _projectId) external;
}

/**
 * @title MaliciousReentrancy
 * @dev Contract designed to test reentrancy protection in LdInvestmentProgram
 * This contract should NOT be able to successfully attack the main contract
 */
contract MaliciousReentrancy {
    ILdInvestmentProgram public targetContract;
    uint256 public projectId;
    uint256 public milestoneIndex;
    uint256 public amount;
    bool public attacking = false;
    
    // Track received payments
    uint256 public totalReceived;
    uint256 public callCount;

    receive() external payable {
        totalReceived += msg.value;
        callCount++;
        
        // Attempt reentrancy if we're in attack mode
        if (attacking && callCount < 3) {
            try targetContract.acceptMilestone(projectId, milestoneIndex) {
                // If this succeeds, the contract is vulnerable
            } catch {
                // Expected - reentrancy should be prevented
            }
        }
    }

    function attemptReentrancy(
        address _target,
        uint256 _projectId,
        uint256 _milestoneIndex,
        uint256 _amount
    ) external {
        targetContract = ILdInvestmentProgram(_target);
        projectId = _projectId;
        milestoneIndex = _milestoneIndex;
        amount = _amount;
        attacking = true;
        callCount = 0;
        
        // This should fail due to reentrancy protection
        targetContract.acceptMilestone(_projectId, _milestoneIndex);
        
        attacking = false;
    }

    function attemptReclaimReentrancy(
        address _target,
        uint256 _projectId
    ) external {
        targetContract = ILdInvestmentProgram(_target);
        projectId = _projectId;
        attacking = true;
        callCount = 0;
        
        // This should fail due to reentrancy protection
        targetContract.reclaimFund(_projectId);
        
        attacking = false;
    }

    // Helper function to reset state
    function reset() external {
        totalReceived = 0;
        callCount = 0;
        attacking = false;
    }
}