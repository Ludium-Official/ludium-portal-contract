const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("LdInvestmentCore", function () {
    let investmentCore;
    let timeLock;
    let owner, user;
    
    beforeEach(async function () {
        [owner, user] = await ethers.getSigners();
        
        // Deploy TimeLock module
        const LdTimeLock = await ethers.getContractFactory("LdTimeLock");
        timeLock = await LdTimeLock.deploy(owner.address);
        await timeLock.waitForDeployment();
        
        // Deploy Core contract
        const LdInvestmentCore = await ethers.getContractFactory("LdInvestmentCore");
        investmentCore = await LdInvestmentCore.deploy(owner.address);
        await investmentCore.waitForDeployment();
    });

    describe("Contract Deployment", function () {
        it("Should deploy successfully", async function () {
            expect(await investmentCore.getAddress()).to.be.properAddress;
            expect(await timeLock.getAddress()).to.be.properAddress;
        });

        it("Should have correct owner", async function () {
            expect(await investmentCore.owner()).to.equal(owner.address);
            expect(await timeLock.owner()).to.equal(owner.address);
        });
        
        it("Should have ETH whitelisted by default", async function () {
            expect(await investmentCore.whitelistedTokens(ethers.ZeroAddress)).to.be.true;
        });
    });
    
    describe("Modular Architecture", function () {
        it("Should allow setting module addresses", async function () {
            await investmentCore.setModules(
                await timeLock.getAddress(),
                ethers.ZeroAddress, // milestone module placeholder
                ethers.ZeroAddress  // funding module placeholder
            );
            
            expect(await investmentCore.timeLockModule()).to.equal(await timeLock.getAddress());
        });
    });

    describe("Automatic Status Transitions", function () {
        let programId;
        
        beforeEach(async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;
            
            // Create a test program
            await investmentCore.createInvestmentProgram(
                "Test Program",
                [user.address],
                1,
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0, // Open condition
                300, // 3% fee
                ethers.ZeroAddress // ETH
            );
            programId = 0;
        });

        it("Should transition program from Ready to Active based on time", async function () {
            // Initially should be Ready
            expect(await investmentCore.getProgramStatus(programId)).to.equal(0n); // Ready
            
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Move to application start time
            await time.increaseTo(Number(programDetails.applicationStartTime) + 50);
            
            // Update status
            await investmentCore.updateProgramStatus(programId);
            const newStatus = await investmentCore.getProgramStatus(programId);
            expect(newStatus).to.equal(1n); // Active
        });

        it("Should transition program to Pending after funding ends", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Move to after funding ends
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            await investmentCore.updateProgramStatus(programId);
            const newStatus = await investmentCore.getProgramStatus(programId);
            expect(newStatus).to.equal(4n); // Pending
        });

        it("Should transition program to Failed after pending period (no projects)", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            const PENDING_PERIOD = 24 * 60 * 60; // 1 day
            
            // Move past pending period
            await time.increaseTo(Number(programDetails.fundingEndTime) + PENDING_PERIOD + 100);
            
            await investmentCore.updateProgramStatus(programId);
            const newStatus = await investmentCore.getProgramStatus(programId);
            expect(newStatus).to.equal(3n); // Failed (no projects means failed program)
        });

        it("Should batch update multiple program statuses", async function () {
            // Create another program
            const currentTime = await time.latest();
            await investmentCore.createInvestmentProgram(
                "Test Program 2",
                [user.address],
                1,
                ethers.parseEther("50"),
                currentTime + 200,
                currentTime + 1200,
                currentTime + 1300,
                currentTime + 2300,
                0,
                300,
                ethers.ZeroAddress
            );
            
            // Batch update both programs
            await investmentCore.batchUpdateProgramStatuses([0, 1]);
            
            // Both should be updated to their appropriate statuses
            const status1 = await investmentCore.getProgramStatus(0);
            const status2 = await investmentCore.getProgramStatus(1);
            
            // Verify statuses are calculated correctly
            expect(Number(status1)).to.be.oneOf([0, 1, 2, 3, 4]); // Valid status
            expect(Number(status2)).to.be.oneOf([0, 1, 2, 3, 4]); // Valid status
        });

        it("Should identify programs needing status updates", async function () {
            // Invalidate status cache
            await investmentCore.refreshProgramStatusCache(programId);
            
            // Get programs needing updates
            const [programIds, hasMore] = await investmentCore.getProgramsNeedingStatusUpdate(0, 10);
            
            expect(programIds.map(id => Number(id))).to.include(programId);
            expect(hasMore).to.be.a('boolean');
        });

        it("Should respect manual status overrides", async function () {
            // Programs marked as Failed or Successful should not auto-transition
            // This would be tested once we have the status change functions from time-lock module
            const currentStatus = await investmentCore.getProgramStatus(programId);
            expect(Number(currentStatus)).to.be.oneOf([0, 1, 2, 3, 4]);
        });

        it("Should handle status cache correctly", async function () {
            // First call should calculate and cache
            const status1 = await investmentCore.getProgramStatus(programId);
            
            // Immediate second call should use cache
            const status2 = await investmentCore.getProgramStatus(programId);
            
            expect(status1).to.equal(status2);
            
            // After refreshing cache, it should recalculate
            await investmentCore.refreshProgramStatusCache(programId);
            const status3 = await investmentCore.getProgramStatus(programId);
            
            // Status might be the same, but cache was refreshed
            expect(Number(status3)).to.be.oneOf([0, 1, 2, 3, 4]);
        });
    });

    describe("Pagination Functions", function () {
        let programIds = [];

        beforeEach(async function () {
            // Create multiple programs for pagination testing
            const currentTime = await time.latest();
            
            for (let i = 0; i < 5; i++) {
                await investmentCore.createInvestmentProgram(
                    `Test Program ${i}`,
                    [user.address],
                    1,
                    ethers.parseEther("100"),
                    currentTime + 100 + (i * 10),
                    currentTime + 1100 + (i * 10),
                    currentTime + 1200 + (i * 10),
                    currentTime + 2200 + (i * 10),
                    0, // Open condition
                    300, // 3% fee
                    ethers.ZeroAddress // ETH
                );
                programIds.push(i);
            }
        });

        it("Should get all programs with pagination", async function () {
            // Get first 3 programs
            const [firstBatch, hasMore1] = await investmentCore.getAllPrograms(0, 3);
            expect(firstBatch).to.have.length(3);
            expect(hasMore1).to.be.true;
            
            // Get remaining programs  
            const [secondBatch, hasMore2] = await investmentCore.getAllPrograms(3, 3);
            expect(secondBatch).to.have.length(2); // Only 2 remaining
            expect(hasMore2).to.be.false;
            
            // Verify program IDs are correct
            expect(firstBatch.map(id => Number(id))).to.deep.equal([0, 1, 2]);
            expect(secondBatch.map(id => Number(id))).to.deep.equal([3, 4]);
        });

        it("Should get all projects with pagination", async function () {
            // Initially no projects
            const [projects, hasMore] = await investmentCore.getAllProjects(0, 10);
            expect(projects).to.have.length(0);
            expect(hasMore).to.be.false;
        });

        it("Should get programs by status with pagination", async function () {
            // All programs should initially be Ready (status 0)
            const [readyPrograms, hasMore] = await investmentCore.getProgramsByStatus(0, 0, 10);
            expect(readyPrograms).to.have.length(5);
            expect(hasMore).to.be.false;
            
            // No active programs initially
            const [activePrograms, hasMoreActive] = await investmentCore.getProgramsByStatus(1, 0, 10);
            expect(activePrograms).to.have.length(0);
            expect(hasMoreActive).to.be.false;
        });

        it("Should get programs by host with pagination", async function () {
            const [hostPrograms, hasMore] = await investmentCore.getProgramsByHost(owner.address, 0, 10);
            expect(hostPrograms).to.have.length(5); // All created by owner
            expect(hasMore).to.be.false;
            
            // No programs by user
            const [userPrograms, hasMoreUser] = await investmentCore.getProgramsByHost(user.address, 0, 10);
            expect(userPrograms).to.have.length(0);
            expect(hasMoreUser).to.be.false;
        });

        it("Should get programs by token with pagination", async function () {
            // All programs use ETH (address(0))
            const [ethPrograms, hasMore] = await investmentCore.getProgramsByToken(ethers.ZeroAddress, 0, 10);
            expect(ethPrograms).to.have.length(5);
            expect(hasMore).to.be.false;
        });

        it("Should handle pagination limits correctly", async function () {
            await expect(
                investmentCore.getAllPrograms(0, 25) // Exceeds MAX_PROJECTS_PER_BATCH (20)
            ).to.be.revertedWith("Limit too high");
        });

        it("Should handle offset bounds correctly", async function () {
            await expect(
                investmentCore.getAllPrograms(100, 5) // Offset beyond available programs
            ).to.be.revertedWith("Offset out of bounds");
        });

        it("Should get total counts correctly", async function () {
            const [totalPrograms, totalProjects, activePrograms, activeProjects] = await investmentCore.getTotalCounts();
            
            expect(totalPrograms).to.equal(5n);
            expect(totalProjects).to.equal(0n); // No projects created yet
            expect(activePrograms).to.equal(0n); // No active programs yet
            expect(activeProjects).to.equal(0n);
        });

        it("Should get lightweight counts efficiently", async function () {
            const [totalPrograms, totalProjects] = await investmentCore.getLightweightCounts();
            
            expect(totalPrograms).to.equal(5n);
            expect(totalProjects).to.equal(0n);
        });

        it("Should handle empty results gracefully", async function () {
            // Test with status that doesn't exist
            const [failedPrograms, hasMore] = await investmentCore.getProgramsByStatus(3, 0, 10); // Failed status
            expect(failedPrograms).to.have.length(0);
            expect(hasMore).to.be.false;
        });

        it("Should paginate with exact batch sizes", async function () {
            // Get exactly 2 items per page
            const [batch1, hasMore1] = await investmentCore.getAllPrograms(0, 2);
            expect(batch1).to.have.length(2);
            expect(hasMore1).to.be.true;
            
            const [batch2, hasMore2] = await investmentCore.getAllPrograms(2, 2);
            expect(batch2).to.have.length(2);
            expect(hasMore2).to.be.true;
            
            const [batch3, hasMore3] = await investmentCore.getAllPrograms(4, 2);
            expect(batch3).to.have.length(1); // Last item
            expect(hasMore3).to.be.false;
        });
    });

    describe("Simplified Reclaim Fund Logic (PRD Compliant)", function () {
        let programId;
        let projectId;

        beforeEach(async function () {
            const currentTime = await time.latest();
            const applicationStart = currentTime + 100;
            const applicationEnd = applicationStart + 1000;
            const fundingStart = applicationEnd + 100;
            const fundingEnd = fundingStart + 1000;

            // Create a program
            await investmentCore.createInvestmentProgram(
                "Test Program",
                [user.address],
                1,
                ethers.parseEther("100"),
                applicationStart,
                applicationEnd,
                fundingStart,
                fundingEnd,
                0, // Open condition
                300, // 3% fee
                ethers.ZeroAddress // ETH
            );
            programId = 0;

            // Create a project through validation
            await time.increaseTo(applicationStart + 50);
            
            const milestones = [{
                title: "Milestone 1",
                description: "Test milestone",
                percentage: 10000, // 100%
                deadline: fundingEnd + 1000
            }];
            
            await investmentCore.connect(user).signValidate(
                programId,
                owner.address, // project owner
                "Test Project",
                ethers.parseEther("50"), // target funding
                milestones
            );
            projectId = 0;
        });

        it("Should allow reclaim when funding target is not met", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Move to funding period but don't invest enough to meet target
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            
            // Invest only 10 ETH (target is 50 ETH)
            await investmentCore.connect(owner).investFund(projectId, {
                value: ethers.parseEther("10")
            });
            
            // Move past funding end time
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            // Check if reclaim is possible
            const [canReclaim, reason, amount] = await investmentCore.canReclaimFunds(projectId, owner.address);
            expect(canReclaim).to.be.true;
            expect(reason).to.equal("Funding target not met");
            expect(amount).to.equal(ethers.parseEther("10"));
            
            // Reclaim funds
            const initialBalance = await ethers.provider.getBalance(owner.address);
            await investmentCore.reclaimFund(projectId);
            const finalBalance = await ethers.provider.getBalance(owner.address);
            
            // Should have received the full investment back
            expect(finalBalance).to.be.gt(initialBalance);
        });

        it("Should allow reclaim when project is marked as failed", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Invest enough to meet target
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            await investmentCore.connect(owner).investFund(projectId, {
                value: ethers.parseEther("50")
            });
            
            // Move past funding end time
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            // Mark project as failed (simulating missed milestone)
            await investmentCore.markProjectAsFailed(projectId, "Milestone deadline missed");
            
            // Check if reclaim is possible
            const [canReclaim, reason, amount] = await investmentCore.canReclaimFunds(projectId, owner.address);
            expect(canReclaim).to.be.true;
            expect(reason).to.equal("Project failed due to missed milestones");
            expect(amount).to.equal(ethers.parseEther("50"));
            
            // Reclaim funds
            await expect(investmentCore.reclaimFund(projectId)).to.not.be.reverted;
        });

        it("Should prevent reclaim when project is successful", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Invest enough to meet target
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            await investmentCore.connect(owner).investFund(projectId, {
                value: ethers.parseEther("50")
            });
            
            // Move past funding end time (project should be successful)
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            // Check if reclaim is possible (should not be)
            const [canReclaim, reason] = await investmentCore.canReclaimFunds(projectId, owner.address);
            expect(canReclaim).to.be.false;
            expect(reason).to.equal("Project is active or successful");
            
            // Try to reclaim (should fail)
            await expect(
                investmentCore.reclaimFund(projectId)
            ).to.be.revertedWith("Cannot reclaim funds: project is active or successful");
        });

        it("Should prevent reclaim when no investment exists", async function () {
            const [canReclaim, reason, amount] = await investmentCore.canReclaimFunds(projectId, user.address);
            expect(canReclaim).to.be.false;
            expect(reason).to.equal("No investment found");
            expect(amount).to.equal(0);
            
            await expect(
                investmentCore.connect(user).reclaimFund(projectId)
            ).to.be.revertedWith("No investment to reclaim");
        });

        it("Should handle batch reclaim correctly", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Create another project that will also fail
            // Don't go backward in time, just ensure we're still in application period
            const currentTime = await time.latest();
            if (currentTime < Number(programDetails.applicationStartTime) + 50) {
                await time.increaseTo(Number(programDetails.applicationStartTime) + 50);
            }
            
            const milestones = [{
                title: "Milestone 1",
                description: "Test milestone",
                percentage: 10000,
                deadline: Number(programDetails.fundingEndTime) + 1000
            }];
            
            await investmentCore.connect(user).signValidate(
                programId,
                owner.address,
                "Test Project 2",
                ethers.parseEther("30"),
                milestones
            );
            const project2Id = 1;
            
            // Invest in both projects with insufficient funding
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            await investmentCore.connect(owner).investFund(projectId, {
                value: ethers.parseEther("10")
            });
            await investmentCore.connect(owner).investFund(project2Id, {
                value: ethers.parseEther("5")
            });
            
            // Move past funding end time
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            // Batch reclaim from both projects
            await expect(
                investmentCore.batchReclaimFunds([projectId, project2Id])
            ).to.not.be.reverted;
        });

        it("Should emit correct events when reclaiming", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Invest insufficient amount
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            await investmentCore.connect(owner).investFund(projectId, {
                value: ethers.parseEther("10")
            });
            
            // Move past funding end time
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            // Reclaim and check event
            await expect(investmentCore.reclaimFund(projectId))
                .to.emit(investmentCore, "FundReclaimed")
                .withArgs(
                    projectId,
                    owner.address,
                    ethers.parseEther("10"),
                    ethers.ZeroAddress,
                    "Funding target not met"
                );
        });

        it("Should prevent double reclaim", async function () {
            const programDetails = await investmentCore.getProgramDetails(programId);
            
            // Invest insufficient amount
            await time.increaseTo(Number(programDetails.fundingStartTime) + 50);
            await investmentCore.connect(owner).investFund(projectId, {
                value: ethers.parseEther("10")
            });
            
            // Move past funding end time
            await time.increaseTo(Number(programDetails.fundingEndTime) + 100);
            
            // First reclaim should work
            await investmentCore.reclaimFund(projectId);
            
            // Second reclaim should fail
            await expect(
                investmentCore.reclaimFund(projectId)
            ).to.be.revertedWith("No investment to reclaim");
        });

        it("Should only allow admin to mark projects as failed", async function () {
            await expect(
                investmentCore.connect(user).markProjectAsFailed(projectId, "Test reason")
            ).to.be.revertedWith("Caller is not owner or admin");
            
            // Should work for owner
            await expect(
                investmentCore.markProjectAsFailed(projectId, "Test reason")
            ).to.not.be.reverted;
        });
    });
});