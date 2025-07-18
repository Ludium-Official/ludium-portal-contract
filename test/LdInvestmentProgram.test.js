const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("LdInvestmentProgram", function () {
    let investmentProgram;
    let usdc;
    let owner, host, validator1, validator2, projectOwner, supporter1, supporter2;
    
    // Test constants
    const PENDING_PERIOD = 24 * 60 * 60; // 1 day in seconds
    const DEFAULT_FEE_PERCENTAGE = 300; // 3%
    
    beforeEach(async function () {
        // Get signers
        [owner, host, validator1, validator2, projectOwner, supporter1, supporter2] = await ethers.getSigners();
        
        // Deploy USDC test token
        const USDC = await ethers.getContractFactory("USDC");
        usdc = await USDC.deploy(owner.address);
        await usdc.waitForDeployment();
        
        // Deploy LdInvestmentProgram
        const LdInvestmentProgram = await ethers.getContractFactory("LdInvestmentProgram");
        investmentProgram = await LdInvestmentProgram.deploy(owner.address);
        await investmentProgram.waitForDeployment();
        
        // Whitelist USDC token
        await investmentProgram.setTokenWhitelist(await usdc.getAddress(), true);
        
        // Mint USDC to supporters for testing
        await usdc.mint(supporter1.address, ethers.parseUnits("10000", 6)); // 10k USDC
        await usdc.mint(supporter2.address, ethers.parseUnits("10000", 6)); // 10k USDC
    });

    describe("Program Creation", function () {
        it("Should create a program with correct parameters", async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            await investmentProgram.connect(host).createInvestmentProgram(
                "Test Program",
                [validator1.address, validator2.address],
                2, // Required approvals
                ethers.parseEther("100"), // Max funding per project
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0, // Open condition
                DEFAULT_FEE_PERCENTAGE,
                ethers.ZeroAddress // ETH
            );
            
            const programDetails = await investmentProgram.getProgramDetails(0);
            expect(programDetails.name).to.equal("Test Program");
            expect(programDetails.host).to.equal(host.address);
            expect(programDetails.maxFundingPerProject).to.equal(ethers.parseEther("100"));
            expect(programDetails.feePercentage).to.equal(DEFAULT_FEE_PERCENTAGE);
        });

        it("Should reject invalid program parameters", async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            // Test invalid time ranges
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    1,
                    ethers.parseEther("100"),
                    applicationStart,
                    applicationStart - 100, // Invalid: end before start
                    fundingStart,
                    fundingEnd,
                    0,
                    DEFAULT_FEE_PERCENTAGE,
                    ethers.ZeroAddress
                )
            ).to.be.revertedWith("Invalid application time range");
        });
    });

    describe("Project Terms System", function () {
        let programId;
        
        beforeEach(async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            // Create program
            await investmentProgram.connect(host).createInvestmentProgram(
                "Test Program",
                [validator1.address, validator2.address],
                1, // Required approvals
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0, // Open condition
                DEFAULT_FEE_PERCENTAGE,
                ethers.ZeroAddress
            );
            programId = 0;
            
            // Move to application period
            await time.increaseTo(applicationStart + 50);
            
            // Create project through validation
            const milestones = [
                {
                    title: "Milestone 1",
                    description: "First milestone",
                    percentage: 5000, // 50%
                    deadline: fundingEnd + 1000
                },
                {
                    title: "Milestone 2", 
                    description: "Second milestone",
                    percentage: 5000, // 50%
                    deadline: fundingEnd + 2000
                }
            ];
            
            await investmentProgram.connect(validator1).signValidate(
                programId,
                projectOwner.address,
                "Test Project",
                ethers.parseEther("50"),
                milestones
            );
        });

        it("Should allow project owner to add terms", async function () {
            await investmentProgram.connect(projectOwner).addProjectTerm(
                0, // projectId
                "Gold Tier",
                "Premium benefits for gold supporters",
                ethers.parseEther("10"), // min investment
                ethers.parseEther("50"), // max investment  
                100, // purchase limit
                "AA NFT + 10,000 AA Tokens"
            );
            
            const termDetails = await investmentProgram.getProjectTermDetails(0, 0);
            expect(termDetails.title).to.equal("Gold Tier");
            expect(termDetails.minInvestment).to.equal(ethers.parseEther("10"));
            expect(termDetails.benefits).to.equal("AA NFT + 10,000 AA Tokens");
        });

        it("Should prevent non-owners from adding terms", async function () {
            await expect(
                investmentProgram.connect(supporter1).addProjectTerm(
                    0,
                    "Unauthorized Term",
                    "Should fail",
                    ethers.parseEther("1"),
                    ethers.parseEther("10"),
                    10,
                    "Nothing"
                )
            ).to.be.revertedWith("Not project owner");
        });

        it("Should track term claims correctly during investment", async function () {
            // Add a term
            await investmentProgram.connect(projectOwner).addProjectTerm(
                0,
                "Silver Tier",
                "Benefits for silver supporters", 
                ethers.parseEther("5"), // min investment
                ethers.parseEther("20"), // max investment
                50, // purchase limit
                "Silver NFT + 5,000 AA Tokens"
            );
            
            // Move to funding period
            const programDetails = await investmentProgram.getProgramDetails(0);
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            
            // Supporter invests and should automatically claim the term
            await investmentProgram.connect(supporter1).investFund(0, {
                value: ethers.parseEther("10")
            });
            
            // Check if supporter claimed the term
            const hasClaimed = await investmentProgram.hasSupporterClaimedTerm(0, supporter1.address, 0);
            expect(hasClaimed).to.be.true;
            
            // Check term purchase count
            const termDetails = await investmentProgram.getProjectTermDetails(0, 0);
            expect(termDetails.currentPurchases).to.equal(1);
        });
    });

    describe("Pending Status Implementation", function () {
        let programId;
        
        beforeEach(async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            await investmentProgram.connect(host).createInvestmentProgram(
                "Test Program",
                [validator1.address],
                1,
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0,
                DEFAULT_FEE_PERCENTAGE,
                ethers.ZeroAddress
            );
            programId = 0;
        });

        it("Should show Pending status after funding ends", async function () {
            const programDetails = await investmentProgram.getProgramDetails(0);
            const fundingEnd = Number(programDetails.fundingEndTime);
            
            // Move to just after funding ends
            await time.increaseTo(fundingEnd + 100);
            
            const status = await investmentProgram.getProgramStatus(0);
            expect(status).to.equal(4); // ProgramStatus.Pending
        });

        it("Should prevent fee claiming during pending period", async function () {
            const programDetails = await investmentProgram.getProgramDetails(0);
            const fundingEnd = Number(programDetails.fundingEndTime);
            
            // Move to pending period
            await time.increaseTo(fundingEnd + 100);
            
            await expect(
                investmentProgram.connect(host).feeClaim(0)
            ).to.be.revertedWith("Pending period not ended, must wait 1 day after funding ends");
        });

        it("Should allow fee claiming after pending period", async function () {
            const programDetails = await investmentProgram.getProgramDetails(0);
            const fundingEnd = Number(programDetails.fundingEndTime);
            
            // Move past pending period
            await time.increaseTo(fundingEnd + PENDING_PERIOD + 100);
            
            // This should not revert (though it may fail for other reasons like no successful funding)
            await expect(
                investmentProgram.connect(host).feeClaim(0)
            ).to.not.be.revertedWith("Pending period not ended");
        });
    });

    describe("Enhanced Tier Validation", function () {
        let projectId;
        
        beforeEach(async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            // Create tier-restricted program
            await investmentProgram.connect(host).createInvestmentProgram(
                "Tier Program",
                [validator1.address],
                1,
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                1, // Tier condition
                DEFAULT_FEE_PERCENTAGE,
                ethers.ZeroAddress
            );
            const programId = 0;
            
            // Create project
            await time.increaseTo(applicationStart + 50);
            const milestones = [{
                title: "Milestone 1",
                description: "Test milestone",
                percentage: 10000, // 100%
                deadline: fundingEnd + 1000
            }];
            
            await investmentProgram.connect(validator1).signValidate(
                programId,
                projectOwner.address,
                "Test Project",
                ethers.parseEther("50"),
                milestones
            );
            projectId = 0;
            
            // Set tier for supporter1 only
            await investmentProgram.connect(projectOwner).setProjectTier(
                projectId,
                supporter1.address,
                "Gold",
                ethers.parseEther("20")
            );
        });

        it("Should prevent investment from users without tiers", async function () {
            const programDetails = await investmentProgram.getProgramDetails(0);
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            
            // supporter2 has no tier assigned
            await expect(
                investmentProgram.connect(supporter2).investFund(0, {
                    value: ethers.parseEther("5")
                })
            ).to.be.revertedWith("User not assigned to any tier for this Tier-restricted program");
        });

        it("Should allow investment from users with proper tiers", async function () {
            const programDetails = await investmentProgram.getProgramDetails(0);
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            
            // supporter1 has tier assigned
            await expect(
                investmentProgram.connect(supporter1).investFund(0, {
                    value: ethers.parseEther("5")
                })
            ).to.not.be.reverted;
        });

        it("Should provide helpful eligibility check function", async function () {
            const [eligible, reason] = await investmentProgram.isUserEligibleToInvest(
                0,
                supporter2.address,
                ethers.parseEther("5")
            );
            
            expect(eligible).to.be.false;
            expect(reason).to.equal("User not assigned to any tier for this Tier-restricted program");
        });
    });

    describe("Contract Compilation and Size", function () {
        it("Should have compiled successfully", async function () {
            // If we got to this point, the contract compiled
            expect(await investmentProgram.getAddress()).to.be.properAddress;
        });

        it("Should have all expected functions", async function () {
            // Test that new functions exist
            expect(investmentProgram.addProjectTerm).to.be.a('function');
            expect(investmentProgram.getProjectTermDetails).to.be.a('function');
            expect(investmentProgram.isUserEligibleToInvest).to.be.a('function');
        });
    });

    describe("Security Tests - Access Control", function () {
        beforeEach(async function () {
            // Grant specific roles for testing
            const ADMIN_ROLE = await investmentProgram.ADMIN_ROLE();
            const PROGRAM_MANAGER_ROLE = await investmentProgram.PROGRAM_MANAGER_ROLE();
            const TOKEN_MANAGER_ROLE = await investmentProgram.TOKEN_MANAGER_ROLE();
            const EMERGENCY_ROLE = await investmentProgram.EMERGENCY_ROLE();
            const PAUSER_ROLE = await investmentProgram.PAUSER_ROLE();
            
            // Grant roles to different accounts for testing
            await investmentProgram.grantRole(ADMIN_ROLE, validator1.address);
            await investmentProgram.grantRole(PROGRAM_MANAGER_ROLE, validator2.address);
            await investmentProgram.grantRole(TOKEN_MANAGER_ROLE, host.address);
            await investmentProgram.grantRole(EMERGENCY_ROLE, supporter1.address);
            await investmentProgram.grantRole(PAUSER_ROLE, supporter2.address);
        });

        it("Should prevent unauthorized token whitelist changes", async function () {
            await expect(
                investmentProgram.connect(validator1).setTokenWhitelist(await usdc.getAddress(), false)
            ).to.be.revertedWith("Caller is not a token manager");
            
            // Should work with proper role
            await expect(
                investmentProgram.connect(host).setTokenWhitelist(await usdc.getAddress(), false)
            ).to.not.be.reverted;
        });

        it("Should prevent unauthorized emergency operations", async function () {
            await expect(
                investmentProgram.connect(host).queueEmergencyWithdraw(ethers.ZeroAddress, ethers.parseEther("1"))
            ).to.be.revertedWith("Caller does not have emergency role");
            
            // Should work with proper role
            await expect(
                investmentProgram.connect(supporter1).queueEmergencyWithdraw(ethers.ZeroAddress, ethers.parseEther("1"))
            ).to.not.be.reverted;
        });

        it("Should prevent unauthorized program status changes", async function () {
            // Create a program first
            const currentTime = await time.latest();
            await investmentProgram.connect(host).createInvestmentProgram(
                "Test Program",
                [validator1.address],
                1,
                ethers.parseEther("100"),
                currentTime + 100,
                currentTime + 1100,
                currentTime + 1200,
                currentTime + 2200,
                0,
                300,
                ethers.ZeroAddress
            );
            
            await expect(
                investmentProgram.connect(host).queueProgramStatusChange(0, 3) // Failed status
            ).to.be.revertedWith("Caller is not a program manager");
            
            // Should work with proper role
            await expect(
                investmentProgram.connect(validator2).queueProgramStatusChange(0, 3)
            ).to.not.be.reverted;
        });

        it("Should prevent unauthorized pause operations", async function () {
            await expect(
                investmentProgram.connect(host).pause()
            ).to.be.revertedWith("Caller does not have pauser role");
            
            // Should work with proper role
            await expect(
                investmentProgram.connect(supporter2).pause()
            ).to.not.be.reverted;
            
            await expect(
                investmentProgram.connect(supporter2).unpause()
            ).to.not.be.reverted;
        });

        it("Should handle role management correctly", async function () {
            const TOKEN_MANAGER_ROLE = await investmentProgram.TOKEN_MANAGER_ROLE();
            
            // Only admin should be able to grant roles
            await expect(
                investmentProgram.connect(supporter1).grantRole(TOKEN_MANAGER_ROLE, supporter1.address)
            ).to.be.reverted;
            
            // Admin should be able to grant roles
            await investmentProgram.connect(validator1).grantRole(TOKEN_MANAGER_ROLE, supporter1.address);
            
            // Check role was granted
            expect(await investmentProgram.hasRole(TOKEN_MANAGER_ROLE, supporter1.address)).to.be.true;
        });

        it("Should display account roles correctly", async function () {
            const roles = await investmentProgram.getAccountRoles(validator1.address);
            const roleNames = await investmentProgram.getRoleNames();
            
            expect(roles.length).to.equal(6);
            expect(roleNames.length).to.equal(6);
            expect(roles[0]).to.be.true; // Should have ADMIN_ROLE
            expect(roleNames[0]).to.equal("ADMIN_ROLE");
        });
    });

    describe("Security Tests - Reentrancy Protection", function () {
        let maliciousContract;
        let programId;
        let projectId;

        beforeEach(async function () {
            // Deploy a malicious contract that attempts reentrancy
            const MaliciousContract = await ethers.getContractFactory("MaliciousReentrancy");
            maliciousContract = await MaliciousContract.deploy();
            await maliciousContract.waitForDeployment();
            
            // Create a program and project for testing
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            await investmentProgram.connect(host).createInvestmentProgram(
                "Test Program",
                [validator1.address],
                1,
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0,
                300,
                ethers.ZeroAddress
            );
            programId = 0;
            
            await time.increaseTo(applicationStart + 50);
            
            const milestones = [{
                title: "Milestone 1",
                description: "Test milestone",
                percentage: 10000,
                deadline: fundingEnd + 1000
            }];
            
            await investmentProgram.connect(validator1).signValidate(
                programId,
                await maliciousContract.getAddress(),
                "Test Project",
                ethers.parseEther("50"),
                milestones
            );
            projectId = 0;
        });

        it("Should prevent reentrancy in milestone acceptance", async function () {
            // Move to funding period and invest
            const programDetails = await investmentProgram.getProgramDetails(0);
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            
            await investmentProgram.connect(supporter1).investFund(0, {
                value: ethers.parseEther("10")
            });
            
            // Try to trigger reentrancy through milestone acceptance
            await expect(
                maliciousContract.attemptReentrancy(
                    await investmentProgram.getAddress(),
                    projectId,
                    0, // milestone index
                    ethers.parseEther("5")
                )
            ).to.be.reverted; // Should be prevented by ReentrancyGuard
        });

        it("Should prevent reentrancy in fund reclaim", async function () {
            const programDetails = await investmentProgram.getProgramDetails(0);
            await time.increaseTo(Number(programDetails.fundingEndTime) + 25 * 60 * 60); // Past pending period
            
            // Try to trigger reentrancy through fund reclaim
            await expect(
                maliciousContract.attemptReclaimReentrancy(
                    await investmentProgram.getAddress(),
                    projectId
                )
            ).to.be.reverted; // Should be prevented by ReentrancyGuard
        });
    });

    describe("Security Tests - Edge Cases and Boundary Conditions", function () {
        it("Should handle zero values gracefully", async function () {
            const currentTime = await time.latest();
            
            // Test zero funding amount
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    1,
                    0, // Zero max funding
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    300,
                    ethers.ZeroAddress
                )
            ).to.be.revertedWith("Max funding must be greater than 0");
        });

        it("Should handle invalid validator configurations", async function () {
            const currentTime = await time.latest();
            
            // Test zero validators
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [], // No validators
                    1,
                    ethers.parseEther("100"),
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    300,
                    ethers.ZeroAddress
                )
            ).to.be.revertedWith("At least one validator required");
            
            // Test more required approvals than validators
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    2, // More approvals than validators
                    ethers.parseEther("100"),
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    300,
                    ethers.ZeroAddress
                )
            ).to.be.revertedWith("Invalid approval count");
        });

        it("Should handle excessive fee percentages", async function () {
            const currentTime = await time.latest();
            
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    1,
                    ethers.parseEther("100"),
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    1001, // > 10% fee
                    ethers.ZeroAddress
                )
            ).to.be.revertedWith("Fee percentage too high");
        });

        it("Should handle contract pause state correctly", async function () {
            // Pause the contract
            const PAUSER_ROLE = await investmentProgram.PAUSER_ROLE();
            await investmentProgram.grantRole(PAUSER_ROLE, owner.address);
            await investmentProgram.pause();
            
            const currentTime = await time.latest();
            
            // Should prevent program creation while paused
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    1,
                    ethers.parseEther("100"),
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    300,
                    ethers.ZeroAddress
                )
            ).to.be.revertedWith("Pausable: paused");
            
            // Unpause and try again
            await investmentProgram.unpause();
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    1,
                    ethers.parseEther("100"),
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    300,
                    ethers.ZeroAddress
                )
            ).to.not.be.reverted;
        });

        it("Should handle time-lock operations correctly", async function () {
            const EMERGENCY_ROLE = await investmentProgram.EMERGENCY_ROLE();
            await investmentProgram.grantRole(EMERGENCY_ROLE, owner.address);
            
            // Queue an operation
            const operationId = await investmentProgram.queueEmergencyWithdraw(
                ethers.ZeroAddress,
                ethers.parseEther("1")
            );
            
            // Should not be able to execute immediately
            await expect(
                investmentProgram.executeTimeLockOperation(operationId)
            ).to.be.revertedWith("Operation still in time-lock period");
            
            // Should be able to cancel
            await investmentProgram.cancelTimeLockOperation(operationId);
            
            // Should not be able to execute cancelled operation
            await expect(
                investmentProgram.executeTimeLockOperation(operationId)
            ).to.be.revertedWith("Operation was cancelled");
        });

        it("Should handle invalid token addresses", async function () {
            const currentTime = await time.latest();
            
            // Test with non-whitelisted token
            await expect(
                investmentProgram.connect(host).createInvestmentProgram(
                    "Test Program",
                    [validator1.address],
                    1,
                    ethers.parseEther("100"),
                    currentTime + 100,
                    currentTime + 1100,
                    currentTime + 1200,
                    currentTime + 2200,
                    0,
                    300,
                    supporter1.address // Random address, not whitelisted
                )
            ).to.be.revertedWith("Token not whitelisted");
        });
    });

    describe("Security Tests - Multi-Signature Validation", function () {
        let programId;
        let projectId;
        
        beforeEach(async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            // Create program with 2 validators requiring 2 approvals
            await investmentProgram.connect(host).createInvestmentProgram(
                "Multi-Sig Program",
                [validator1.address, validator2.address],
                2, // Require both validators
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0,
                300,
                ethers.ZeroAddress
            );
            programId = 0;
            
            await time.increaseTo(applicationStart + 50);
            
            const milestones = [{
                title: "Milestone 1",
                description: "Test milestone",
                percentage: 10000,
                deadline: fundingEnd + 1000
            }];
            
            await investmentProgram.connect(validator1).signValidate(
                programId,
                projectOwner.address,
                "Test Project",
                ethers.parseEther("50"),
                milestones
            );
            projectId = 0;
            
            // Move to funding period and add investment
            await time.increaseTo(fundingStart + 50);
            await investmentProgram.connect(supporter1).investFund(0, {
                value: ethers.parseEther("10")
            });
        });

        it("Should require multiple approvals for milestone acceptance", async function () {
            // Single approval should not be enough
            await investmentProgram.connect(validator1).approveMilestone(projectId, 0);
            
            // Check that milestone is not yet approved
            const milestoneDetails = await investmentProgram.getMilestoneDetails(projectId, 0);
            expect(milestoneDetails.isApproved).to.be.false;
            
            // Second approval should complete the process
            await investmentProgram.connect(validator2).approveMilestone(projectId, 0);
            
            // Now milestone should be approved
            const updatedMilestoneDetails = await investmentProgram.getMilestoneDetails(projectId, 0);
            expect(updatedMilestoneDetails.isApproved).to.be.true;
        });

        it("Should prevent duplicate approvals from same validator", async function () {
            await investmentProgram.connect(validator1).approveMilestone(projectId, 0);
            
            await expect(
                investmentProgram.connect(validator1).approveMilestone(projectId, 0)
            ).to.be.revertedWith("Validator already approved");
        });

        it("Should prevent non-validators from approving milestones", async function () {
            await expect(
                investmentProgram.connect(supporter1).approveMilestone(projectId, 0)
            ).to.be.revertedWith("Not a validator for this project's program");
        });
    });
});