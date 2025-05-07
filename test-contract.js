require('dotenv').config();

const { ethers } = require('ethers');
const fs = require('fs');


// Load environment variables
const {
  RPC_URL,
  PRIVATE_KEY,
  CONTRACT_ADDRESS,
  VALIDATOR_ADDRESS, 
  BUILDER_ADDRESS,
} = process.env;

// Load contract ABI
const contractABI = JSON.parse(fs.readFileSync('./abi/LdEduProgram.json', 'utf8')).abi;


// Setup provider and signer (ethers v5)
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// Create contract instance
const contract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, wallet);

// Deploy the contract
async function deployProgramContract() {
  console.log("🚀 Deploying the contract...");

  const bytecode = JSON.parse(fs.readFileSync('./abi/LdEduProgram.json', 'utf8')).bytecode;
  const factory = new ethers.ContractFactory(contractABI, bytecode, wallet);
  const contract = await factory.deploy(wallet.address);
  await contract.deployed();

  console.log("✅ Deployment complete!");
  console.log(`📍 Contract address: ${contract.address}`);

  return contract.address;
}

//  Create a program
async function createProgram() {
  try {
    console.log("📝 Creating a program...");
    const programName = "Ludium Program Test";
    const price = ethers.utils.parseEther("0.001");
    const startTime = Math.floor(Date.now() / 1000) + 60; 
    const endTime = startTime + 3600; 

    console.log(`Name: ${programName}`);
    console.log(`Price: ${ethers.utils.formatEther(price)} EDU`);
    console.log(`Start: ${new Date(startTime * 1000).toLocaleString()}`);
    console.log(`End: ${new Date(endTime * 1000).toLocaleString()}`);
    console.log(`Validator: ${VALIDATOR_ADDRESS}`);

    const tx = await contract.createEduProgram(
      programName,
      price,
      startTime,
      endTime,
      VALIDATOR_ADDRESS,
      { value: price }
    );
    console.log(`✅ Transaction : ${tx.hash}`);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === 'ProgramCreated');
    if (event) {
      const programId = event.args[0].toString();
      console.log(`🎉 Program created! ID: ${programId}`);
      return programId;
    } else {
      console.log("⚠️ Program ID not found in event.");
      return null;
    }
  } catch (error) {
    console.log("error",error)
    console.error("❌ Program creation failed:", error.message);
    throw error;
  }
}


async function acceptMilestone(programId) {
  try {

    const milestoneReward = ethers.utils.parseEther("0.0003");
    const builder = BUILDER_ADDRESS;
    const tx = await contract.acceptMilestone(programId,builder, milestoneReward);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "MilestoneAccepted");
    if (!event) throw new Error("MilestoneAccepted event not found");
    console.log(`✅ Milestone accepted successfully`);
  } catch (error) {
    console.error("❌ Failed to accept milestone:", error.message);
    throw error;
  }
}

async function reclaimFunds(programId) {
  try {
    console.log(`💸 Attempting to reclaim funds... (ID: ${programId})`);
    const tx = await contract.reclaimFunds(programId);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "FundsReclaimed");
    if (!event) throw new Error("FundsReclaimed event not found");

    console.log(`✅ Funds reclaimed!`);
  } catch (error) {
    console.error("❌ Failed to reclaim funds:", error.message);
    throw error;
  }
}

async function updateProgram(programId) {
  try {
    const newPrice = ethers.utils.parseEther("0.0008");
    const newStartTime = Math.floor(Date.now() / 1000) + 120;
    const newEndTime = newStartTime + 3600;
    const newValidator = VALIDATOR_ADDRESS;

    console.log("🛠️ Updating program...");
    const tx = await contract.updateProgram(programId, newPrice, newStartTime, newEndTime, newValidator);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "ProgramEdited");
    if (!event) throw new Error("ProgramEdited event not found");

    console.log(`✅ Program updated!`);
    console.log(` New price: ${ethers.utils.formatEther(newPrice)} EDU`);
  } catch (error) {
    console.error("❌ Failed to update program:", error.message);
    throw error;
  }
}


async function getProgramInfo(programId) {
  try {
    console.log(`\n🔍 Fetching program info... (ID: ${programId})`);

    const program = await contract.eduPrograms(programId);

    console.log("\n📋 Program Info:");
    console.log(`ID: ${program.id.toString()}`);
    console.log(`Name: ${program.name}`);
    console.log(`Price: ${ethers.utils.formatEther(program.price)} EDU`);
    console.log(`Start Date: ${new Date(program.startTime.toNumber() * 1000).toLocaleString()}`);
    console.log(`End Date: ${new Date(program.endTime.toNumber() * 1000).toLocaleString()}`);
    console.log(`Sponsor: ${program.maker}`);
    console.log(`Validator: ${program.validator}`);
    console.log(`Claimed: ${program.claimed ? 'Yes' : 'No'}`);

    return program;
  } catch (error) {
    console.error("❌ Failed to fetch program info:", error.message);
    throw error;
  }
}


async function main() {
  const args = process.argv.slice(2);
  const [command, arg1] = args;
  const num1 = arg1 ? parseInt(arg1) : undefined;

  try {
    switch (command) {
      case 'deploy':
        await deployProgramContract();
        break;

      case 'create':
        await createProgram();
        break;

      case 'accept-milestone':
        if (!num1) throw new Error("Program ID is required");
        await acceptMilestone(num1);
        break;

      case 'reclaim':
        if (!num1) throw new Error("Program ID is required");
        await reclaimFunds(num1);
        break;
  
      case 'update-program':
        if (!num1) throw new Error("Program ID is required");
        await updateProgram(num1);
        break;
  
      case 'info':
        if (!num1) throw new Error("Program ID is required");
        await getProgramInfo(num1);
        break;

      default:
        console.log(`
Usage: node test.js <command> [id]

Commands:
  deploy                              Deploy contract
  create                              Create a program
  accept-milestone [programId]        Accept a milestone
  reclaim                             reclaim funds
  update-program                      Update a program
  info <programId>                    View program information
`);
    }
  } catch (err) {
    console.error("❌ Error:", err.message);
  }
}

main();
