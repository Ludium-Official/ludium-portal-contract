require('dotenv').config();
const { ethers } = require('ethers');
const fs = require('fs');

// 환경 변수 로드
const {
  RPC_URL,
  PRIVATE_KEY,
  CONTRACT_ADDRESS,
  VALIDATOR_ADDRESS,
  BUILDER_ADDRESS,
  BUILDER_PRIVATE_KEY
} = process.env;

// ABI 파일 로드
const contractABI = JSON.parse(fs.readFileSync('./abi/LdEduProgram.json', 'utf8')).abi;


// 프로바이더와 사이너 설정 (ethers v5 문법)
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// 팩토리 생성
async function deployProgramContract() {
  console.log("🚀 팩토리 컨트랙트 배포 중...");

  const bytecode = JSON.parse(fs.readFileSync('./abi/LdEduProgram.json', 'utf8')).data.bytecode.object;
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
    const price = ethers.utils.parseEther("0.001"); // 0.001 EDU
    const startTime = Math.floor(Date.now() / 1000) + 60; // 1분 후 시작
    const endTime = startTime + 3600; // 1시간 후 종료
    
    console.log(`이름: ${programName}`);
    console.log(`가격: ${ethers.utils.formatEther(price)} EDU`);
    console.log(`시작: ${new Date(startTime * 1000).toLocaleString()}`);
    console.log(`종료: ${new Date(endTime * 1000).toLocaleString()}`);
    console.log(`벨리데이터: ${VALIDATOR_ADDRESS}`);

    const tx = await contract.createEduProgram(
      programName,
      price,
      startTime,
      endTime,
      VALIDATOR_ADDRESS,
      { value: price }
    );

    console.log(`✅ 트랜잭션 전송됨: ${tx.hash}`);
    const receipt = await tx.wait();
    
    // 이벤트에서 프로그램 ID 추출
    const event = receipt.events
      .find(event => event.event === 'ProgramCreated');
    
    if (event) {
      const programId = event.args[0].toString();
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

    const tx = await contract.approveProgram(programId, BUILDER_ADDRESS);
    console.log(`✅ 트랜잭션 전송됨: ${tx.hash}`);
    await tx.wait();
    console.log("🎉 프로그램 승인 완료!");
  } catch (error) {
    console.error("❌ 프로그램 승인 실패:", error.message);
    throw error;
  }
}
// 그랜츠 청구 함수 (주요 수정 부분)
async function claimGrants(programId) {
  try {
    console.log(`\n💰 그랜츠 청구 중... (ID: ${programId})`);
    
    // 빌더 계정 설정 검증
    if (!BUILDER_PRIVATE_KEY) {
      throw new Error("BUILDER_PRIVATE_KEY가 .env 파일에 설정되지 않았습니다.");
    }
    
    // 빌더 지갑 생성
    const builderWallet = new ethers.Wallet(BUILDER_PRIVATE_KEY, provider);
    console.log(`빌더 지갑 주소: ${builderWallet.address}`);
    
    // 컨트랙트 인스턴스 생성 (빌더 지갑으로)
    const builderContract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, builderWallet);

    // 프로그램 정보 확인
    console.log(`📋 프로그램 정보 확인 중...`);
    const program = await builderContract.eduPrograms(programId);
    
    console.log(`프로그램 ID: ${program.id.toString()}`);
    console.log(`프로그램 이름: ${program.name}`);
    console.log(`승인 여부: ${program.approve ? '승인됨' : '미승인'}`);
    console.log(`청구 여부: ${program.claimed ? '이미 청구됨' : '미청구'}`);
    console.log(`프로그램에 등록된 빌더 주소: ${program.builder}`);
    console.log(`현재 시간: ${Math.floor(Date.now() / 1000)}`);
    console.log(`프로그램 시작 시간: ${program.startTime.toString()}`);
    console.log(`프로그램 종료 시간: ${program.endTime.toString()}`);
    
    // 중요: 프로그램에 등록된 빌더 주소와 지갑 주소 비교
    if (builderWallet.address.toLowerCase() !== program.builder.toLowerCase()) {
      throw new Error(`현재 지갑 주소(${builderWallet.address})가 프로그램에 등록된 빌더 주소(${program.builder})와 일치하지 않습니다.`);
    }
    
    // 필수 조건 확인
    if (!program.approve) {
      throw new Error("이 프로그램은 아직 승인되지 않았습니다.");
    }
    if (program.claimed) {
      throw new Error("이 프로그램은 이미 청구되었습니다.");
    }
    
    const currentTime = Math.floor(Date.now() / 1000);
    if (currentTime < program.startTime.toNumber()) {
      throw new Error(`프로그램이 아직 시작되지 않았습니다. (시작 시간: ${new Date(program.startTime.toNumber() * 1000).toLocaleString()})`);
    }
    if (currentTime > program.endTime.toNumber()) {
      throw new Error(`프로그램 청구 기간이 지났습니다. (종료 시간: ${new Date(program.endTime.toNumber() * 1000).toLocaleString()})`);
    }
    
    // 빌더 계정 잔액 확인
    const balance = await provider.getBalance(builderWallet.address);
    console.log(`빌더 계정 잔액: ${ethers.utils.formatEther(balance)} ETH`);
    
    // 단순하게 트랜잭션 보내기 (가스 파라미터 없이)
    console.log(`🚀 트랜잭션 전송 중...`);
    const tx = await builderContract.claimGrants(programId);
    
    console.log(`✅ 트랜잭션 전송됨: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`🎉 그랜츠 청구 완료!`);
    console.log(`블록 번호: ${receipt.blockNumber}`);
    console.log(`가스 사용량: ${receipt.gasUsed.toString()}`);
    
    return receipt;
  } catch (error) {
    console.error(`❌ 그랜츠 청구 실패:`, error.message);
    
    // 상세 오류 정보 출력
    if (error.reason) {
      console.error(`오류 이유: ${error.reason}`);
    }
    if (error.code) {
      console.error(`오류 코드: ${error.code}`);
    }
    if (error.transaction) {
      console.error(`트랜잭션 해시: ${error.transaction.hash}`);
    }
    
    throw error;
  }
}
// 빌더가 Proposal 제출
async function submitProposal(programId) {
  const builderWallet = new ethers.Wallet(BUILDER_PRIVATE_KEY, provider);
  const builderContract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, builderWallet);

  const milestoneNames = ["1단계", "2단계"];
  const milestoneDescriptions = ["기초 개발", "배포 완료"];
  const milestonePrices = [
    ethers.utils.parseEther("0.005"),
    ethers.utils.parseEther("0.005"),
  ];

  const tx = await builderContract.submitProposal(
    programId,
    milestoneNames,
    milestoneDescriptions,
    milestonePrices
  );

  const receipt = await tx.wait();
  const event = receipt.events.find(e => e.event === 'ProposalSubmitted');
  const proposalId = event.args.proposalId.toNumber();

  console.log(`✅ Proposal 제출 완료 - ID: ${proposalId}`);
  return proposalId;
}
// Validator가 Proposal 선택
async function evaluateProposal(programId, proposalId) {
  const tx = await contract.evaluateProposal(programId, proposalId, true);
  await tx.wait();
  console.log(`🔎 Proposal 선택 완료 (programId: ${programId}, proposalId: ${proposalId})`);
}

// Builder가 마일스톤 제출
async function submitMilestone(programId, milestoneId, links) {
  const builderWallet = new ethers.Wallet(BUILDER_PRIVATE_KEY, provider);
  const builderContract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, builderWallet);

  const tx = await builderContract.submitMilestone(programId, milestoneId, links);
  await tx.wait();
  console.log(`📝 마일스톤 제출 완료 (programId: ${programId}, milestoneId: ${milestoneId})`);
}

// Validator가 마일스톤 승인 및 보상 전송
async function approveMilestone(programId, milestoneId) {
  const tx = await contract.approveMilestone(programId, milestoneId);
  await tx.wait();
  console.log(`✅ 마일스톤 승인 완료 (보상 전송 포함)`);
}

// 프로그램 정보 조회
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
  const proposalId = args[2] ? parseInt(args[2]) : undefined;
  const milestoneId = args[3] ? parseInt(args[3]) : undefined;

  try {
    switch (command) {
      case 'create':
        await createProgram();
        break;

    case 'deploy':
      await deployProgramContract();
      break;


      case 'submit-proposal':
        if (programId === undefined) {
          console.error("❌ 프로그램 ID를 지정해주세요: node test.js submit-proposal <programId>");
          process.exit(1);
        }
        await submitProposal(programId);
        break;

      case 'evaluate':
        if (programId === undefined || proposalId === undefined) {
          console.error("❌ 프로그램 ID와 Proposal ID를 지정해주세요: node test.js evaluate <programId> <proposalId>");
          process.exit(1);
        }
        await evaluateProposal(programId, proposalId);
        break;

      case 'submit-milestone':
        if (programId === undefined || milestoneId === undefined) {
          console.error("❌ 프로그램 ID와 마일스톤 ID를 지정해주세요: node test.js submit-milestone <programId> <milestoneId>");
          process.exit(1);
        }
        await submitMilestone(programId, milestoneId, ["https://example.com/milestone"]);
        break;

      case 'approve-milestone':
        if (programId === undefined || milestoneId === undefined) {
          console.error("❌ 프로그램 ID와 마일스톤 ID를 지정해주세요: node test.js approve-milestone <programId> <milestoneId>");
          process.exit(1);
        }
        await approveMilestone(programId, milestoneId);
        break;

      case 'info':
        if (programId === undefined) {
          console.error("❌ 프로그램 ID를 지정해주세요: node test.js info <programId>");
          process.exit(1);
        }
        await getProgramInfo(programId);
        break;

      case 'all':
        const newProgramId = await createProgram();
        const newProposalId = await submitProposal(newProgramId);
        await evaluateProposal(newProgramId, newProposalId);
        await submitMilestone(newProgramId, 0, ["https://github.com/repo"]);
        await approveMilestone(newProgramId, 0);
        await submitMilestone(newProgramId, 1, ["https://demo.app"]);
        await approveMilestone(newProgramId, 1);
        await getProgramInfo(newProgramId);
        break;

      default:
        console.log(`
사용법: node test.js <command> [programId] [proposalId] [milestoneId]

명령어:
  create                            새 교육 프로그램 생성
  submit-proposal <programId>       Proposal 제출
  evaluate <programId> <proposalId> Proposal 선택
  submit-milestone <programId> <milestoneId> 마일스톤 제출
  approve-milestone <programId> <milestoneId> 마일스톤 승인
  info <programId>                  프로그램 정보 조회
  all                               end-to-end 전체 흐름 테스트
        `);
    }
  } catch (error) {
    console.error("❌ 테스트 실패:", error);
    process.exit(1);
  }
}

main().catch(console.error);
