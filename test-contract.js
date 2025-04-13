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
    // 이벤트에서 프로그램 ID 추출
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

// 프로그램 승인 테스트
async function approveProgram(programId) {
  try {
    console.log(`\n🔐 프로그램 승인 중... (ID: ${programId})`);
    console.log(`빌더: ${BUILDER_ADDRESS}`);

    const tx = await contract.approveProgram(programId);
    console.log(`✅ 트랜잭션 전송됨: ${tx.hash}`);
    await tx.wait();
    console.log("🎉 프로그램 승인 완료!");
  } catch (error) {
    console.error("❌ 프로그램 승인 실패:", error.message);
    throw error;
  }
}


async function submitApplication(programId) {
  try {
    console.log(`📨 Application 제출 중... (programId: ${programId})`);
    const milestoneNames = ["1단계", "2단계"];
    const milestoneDescriptions = ["기초 개발", "배포 완료"];
    const milestonePrices = [
      ethers.utils.parseEther("0.0001"),
      ethers.utils.parseEther("0.0001"),
    ];

    console.log(`📨 Milestone 제출 중... (programId: ${programId})`);

    const tx = await contract.submitApplication(
      programId,
      milestoneNames,
      milestoneDescriptions,
      milestonePrices
    );
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === 'ProgramApplied');
    const applicationId = event.args.id.toString();
    const milestoneIds = event.args.milestoneIds.map(id => id.toString());
    console.log(`✅ Application 제출 완료 - ID: ${applicationId}`);
    console.log(`📌 생성된 마일스톤 ID들:`, milestoneIds);
    return { applicationId, milestoneIds };
    
  } catch (error) {
    console.error("❌ Application 제출 실패:", error.message);
    throw error;
  }
}

async function selectApplication(applicationId) {
  try {
    console.log(`📥 Application 선택 중... (applicationId: ${applicationId})`);

    const tx = await contract.selectApplication(applicationId, true);
    const receipt = await tx.wait();

    const event = receipt.events.find(e => e.event === "ApplicationSelected");
    if (!event) throw new Error("ApplicationSelected 이벤트를 찾을 수 없습니다.");
    console.log(`✅ Application 선택 완료`);
  } catch (error) {
    console.error("❌ Application 선택 실패:", error.message);
    throw error;
  }
}

async function denyApplication(applicationId) {
  try {
    const tx = await contract.denyApplication(applicationId);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "ApplicationSelected" || e.event === "ApplicationDenied");
    if (!event) throw new Error("Application denial event not found");
    console.log(`❌ Application denied successfully (applicationId: ${applicationId})`);
  } catch (error) {
    console.error("❌ Failed to deny application:", error.message);
    throw error;
  }
}

async function submitMilestone(milestoneId, links) {
  try {
    const tx = await contract.submitMilestone(milestoneId, links);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "MilestoneSubmitted");
    if (!event) throw new Error("MilestoneSubmitted event not found");
    console.log(`📝 Milestone submitted successfully (milestoneId: ${milestoneId})`);
  } catch (error) {
    console.error("❌ Failed to submit milestone:", error.message);
    throw error;
  }
}

async function acceptMilestone(milestoneId) {
  try {
    const tx = await contract.acceptMilestone(milestoneId);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "MilestoneAccepted");
    if (!event) throw new Error("MilestoneAccepted event not found");
    console.log(`✅ Milestone accepted successfully (milestoneId: ${milestoneId})`);
  } catch (error) {
    console.error("❌ Failed to accept milestone:", error.message);
    throw error;
  }
}

async function rejectMilestone(milestoneId) {
  try {
    const tx = await contract.rejectMilestone(milestoneId);
    const receipt = await tx.wait();
    const event = receipt.events.find(e => e.event === "MilestoneRejected");
    if (!event) throw new Error("MilestoneRejected event not found");
    console.log(`❌ Milestone rejected successfully (milestoneId: ${milestoneId})`);
  } catch (error) {
    console.error("❌ Failed to reject milestone:", error.message);
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
  const command = args[0];
  const programId = args[1] ? parseInt(args[1]) : undefined;
  const applicationId = args[2] ? parseInt(args[2]) : undefined;
  const milestoneId = args[3] ? parseInt(args[3]) : undefined;

  try {
    switch (command) {
      case 'deploy':
        await deployProgramContract();
        break;

      case 'create':
        await createProgram();
        break;

      case 'approve':
        await approveProgram(programId);
        break;

      case 'submit-application':
        if (!programId) throw new Error("Program ID 필요");
        await submitApplication(programId);
        break;


      case 'select-application':
        if (applicationId === undefined) throw new Error("Application ID 필요");
        await selectApplication(applicationId);
        break;

      case 'deny-application':
        if (!applicationId) throw new Error("Program ID 필요");
        await denyApplication(applicationId);
        break;

      case 'submit-milestone':
        if (!milestoneId) throw new Error("applicationId, Milestone ID 필요");
        await submitMilestone(milestoneId, ["https://link.to/milestone"]);
        break;

      case 'accept-milestone':
        if (!milestoneId) throw new Error("Program ID, Milestone ID 필요");
        await acceptMilestone(milestoneId);
        break;

      case 'reject-milestone':
        if (!milestoneId) throw new Error("Program ID, Milestone ID 필요");
        await rejectMilestone(milestoneId);
        break;

      case 'info':
        if (!programId) throw new Error("Program ID 필요");
        await getProgramInfo(programId);
        break;

      case 'all':
        const pid = await createProgram();
        const appId = await submitApplication(pid);
        await selectApplication(appId);
        await denyApplication(appId);
        await submitMilestone(0, ["https://link1"]);
        await acceptMilestone(0);
        await submitMilestone(1, ["https://link2"]);
        await acceptMilestone(1);
        await rejectMilestone(1);
        await getProgramInfo();
        break;

      default:
        console.log(`
사용법: node test.js <command> [programId] [applicationId] [milestoneId]

명령어:
  deploy                                컨트랙트 배포
  create                                프로그램 생성
  approve <programId>                   프로그램 승인
  submit-application <programId>        지원서 제출
  select <applicationId>                지원서 선택
  submit-milestone <milestoneId>        마일스톤 제출
  accept-milestone <milestoneId>        마일스톤 승인
  reject-milestone <milestoneId>        마일스톤 거절
  info <programId>                      프로그램 정보 조회
  all                                   전체 흐름 테스트
`);
    }
  } catch (err) {
    console.error("❌ 오류:", err.message);
  }
}

main();

