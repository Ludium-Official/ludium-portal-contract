require('dotenv').config();
const { WepinProvider } = require('@wepin/provider-js');

const { ethers } = require('ethers');
const fs = require('fs');


// 환경 변수 로드
const {
  RPC_URL,
  PRIVATE_KEY,
  CONTRACT_ADDRESS,
  VALIDATOR_ADDRESS, 
  BUILDER_ADDRESS,
} = process.env;

// ABI 파일 로드
const contractABI = JSON.parse(fs.readFileSync('./abi/LdEduProgram.json', 'utf8')).abi;


// 프로바이더와 사이너 설정 (ethers v5 문법)
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// 팩토리 생성
async function deployProgramContract() {
  console.log("🚀 팩토리 컨트랙트 배포 중...");

  const bytecode = JSON.parse(fs.readFileSync('./abi/LdEduProgram.json', 'utf8')).bytecode;
  const factory = new ethers.ContractFactory(contractABI, bytecode, wallet);
  const contract = await factory.deploy(wallet.address);
  await contract.deployed();

  console.log("✅ 배포 완료!");
  console.log(`📍 컨트랙트 주소: ${contract.address}`);

  return contract.address;
}


// 컨트랙트 인스턴스 생성
const contract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, wallet);

// 프로그램 생성 테스트
async function createProgram() {
  try {
    console.log("📝 프로그램 생성 중...");
    const programName = "교육 프로그램 테스트";
    const keywords = ["AI", "교육"];
    const summary = "요약 설명입니다.";
    const description = "이것은 긴 설명입니다.";
    const links = ["https://example.com"];
    const price = ethers.utils.parseEther("0.001");
    const startTime = Math.floor(Date.now() / 1000) + 60; // 시작: 1분 후
    const endTime = startTime + 3600; // 종료: 1시간 후
    console.log("🌍 .env에서 불러온 VALIDATOR_ADDRESS:", process.env.VALIDATOR_ADDRESS);
    console.log("🌍 .env에서 불러온 RPCURL:", process.env.RPC_URL);
    console.log("🌍 .env에서 불러온 contractaddr:", process.env.CONTRACT_ADDRESS);
    console.log("🌍 .env에서 불러온 chainId:", process.env.CHAIN_ID);


    console.log(`이름: ${programName}`);
    console.log(`가격: ${ethers.utils.formatEther(price)} EDU`);
    console.log(`시작: ${new Date(startTime * 1000).toLocaleString()}`);
    console.log(`종료: ${new Date(endTime * 1000).toLocaleString()}`);
    console.log(`벨리데이터: ${VALIDATOR_ADDRESS}`);

    const tx = await contract.createEduProgram(
      programName,
      price,
      keywords,
      startTime,
      endTime,
      VALIDATOR_ADDRESS,
      summary,
      description,
      links,
      { value: price }
    );
    console.log(`✅ 트랜잭션 전송됨: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`tx:`,tx.address);
    const event = receipt.events.find(e => e.event === 'ProgramCreated');
    if (event) {
      const programId = event.args[0].toString();
      
      event.args.id
      console.log(`🎉 프로그램 생성 완료! 프로그램 ID: ${programId}`);
      return programId;
    } else {
      console.log("⚠️ 이벤트에서 프로그램 ID를 찾을 수 없습니다.");
      return null;
    }
  } catch (error) {
    console.log("error",error)
    console.error("❌ 프로그램 생성 실패:", error.message);
    throw error;
  }
}


async function acceptMilestone() {
  try {

    const milestoneReward = ethers.utils.parseEther("0.0003");
    const programId = 1;
    const milestoneId = "id";
    const builder = BUILDER_ADDRESS;
    const tx = await contract.acceptMilestone(programId, milestoneId, builder, milestoneReward);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "MilestoneAccepted");
    if (!event) throw new Error("MilestoneAccepted event not found");
    console.log(`✅ Milestone accepted successfully (milestoneId: ${milestoneId})`);
  } catch (error) {
    console.error("❌ Failed to accept milestone:", error.message);
    throw error;
  }
}



async function getProgramInfo(programId) {
  try {
    console.log(`\n🔍 프로그램 정보 조회 중... (ID: ${programId})`);

    const program = await contract.eduPrograms(programId);

    console.log("\n📋 프로그램 정보:");
    console.log(`ID: ${program.id.toString()}`);
    console.log(`이름: ${program.name}`);
    console.log(`가격: ${ethers.utils.formatEther(program.price)} EDU`);
    console.log(`시작: ${new Date(program.startTime.toNumber() * 1000).toLocaleString()}`);
    console.log(`종료: ${new Date(program.endTime.toNumber() * 1000).toLocaleString()}`);
    console.log(`생성자: ${program.maker}`);
    console.log(`벨리데이터: ${program.validator}`);
    console.log("contractaddr:", process.env.CONTRACT_ADDRESS);
    console.log(`승인 여부: ${program.approve ? '승인됨' : '미승인'}`);
    console.log(`청구 여부: ${program.claimed ? '청구됨' : '미청구'}`);
    console.log(`빌더: ${program.builder === '0x0000000000000000000000000000000000000000' ? '없음' : program.builder}`);

    return program;
  } catch (error) {
    console.error("❌ 프로그램 정보 조회 실패:", error.message);
    throw error;
  }
}

// 명령행 인자 처리 및 테스트 실행
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
        await acceptMilestone();
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
  accept-milestone <programId> <milestoneId> <builder> <reward>      Accept a milestone
  info <programId>                    View program information
`);
    }
  } catch (err) {
    console.error("❌ Error:", err.message);
  }
}

main();
