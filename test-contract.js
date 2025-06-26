require("dotenv").config();
const {
  JsonRpcProvider,
  Contract,
  ContractFactory,
  Wallet,
  ZeroAddress,
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
} = require("ethers");
const fs = require("fs");

// Load environment variables
const {
  RPC_URL,
  PRIVATE_KEY,
  VALIDATOR_PRIVATE_KEY,
  BUILDER_PRIVATE_KEY,
  CHAIN_ID,
  LDEDUPROGRAM_ADDRESS,
  USDC_ADDRESS,
} = process.env;

// ABI 파일들
const ldEduProgramABI = JSON.parse(
  fs.readFileSync("./abi/LdEduProgram.json", "utf8")
).abi;
const usdcABI = JSON.parse(fs.readFileSync("./abi/TestUSDC.json", "utf8")).abi;

class LdEduProgramTester {
  constructor() {
    // 프로바이더 설정
    this.provider = new JsonRpcProvider(RPC_URL);

    // 지갑들 설정
    this.ownerWallet = new Wallet(PRIVATE_KEY, this.provider);
    this.validatorWallet = new Wallet(VALIDATOR_PRIVATE_KEY, this.provider);
    this.builderWallet = new Wallet(BUILDER_PRIVATE_KEY, this.provider);

    // 컨트랙트 인스턴스들
    this.ldEduProgram = null;
    this.usdc = null;

    console.log("🔧 테스터 초기화 완료");
    console.log(`👤 Owner: ${this.ownerWallet.address}`);
    console.log(`👤 Validator: ${this.validatorWallet.address}`);
    console.log(`👤 Builder: ${this.builderWallet.address}`);
  }

  async deployContracts() {
    try {
      console.log("\n🚀 컨트랙트 배포 시작...");

      // LdEduProgram 배포
      const ldEduProgramJson = JSON.parse(
        fs.readFileSync("./abi/LdEduProgram.json", "utf8")
      );

      // bytecode 존재 확인
      if (!ldEduProgramJson.bytecode) {
        throw new Error("LdEduProgram bytecode not found in ABI file");
      }

      const LdEduProgramFactory = new ContractFactory(
        ldEduProgramJson.abi,
        ldEduProgramJson.bytecode,
        this.ownerWallet
      );
      this.ldEduProgram = await LdEduProgramFactory.deploy(
        this.ownerWallet.address
      );

      // TestUSDC 배포
      const usdcJson = JSON.parse(
        fs.readFileSync("./abi/TestUSDC.json", "utf8")
      );

      // bytecode 존재 확인
      if (!usdcJson.bytecode) {
        throw new Error("TestUSDC bytecode not found in ABI file");
      }

      const USDCFactory = new ContractFactory(
        usdcJson.abi,
        usdcJson.bytecode,
        this.ownerWallet
      );
      this.usdc = await USDCFactory.deploy(this.ownerWallet.address);

      const ldEduProgramAddress = await this.ldEduProgram.getAddress();
      const usdcAddress = await this.usdc.getAddress();

      console.log("✅ 배포 완료!");
      console.log(`📍 LdEduProgram: ${ldEduProgramAddress}`);
      console.log(`📍 TestUSDC: ${usdcAddress}`);

      // 배포 정보를 환경 변수 형태로 출력
      console.log("\n📝 .env 파일에 다음 주소들을 추가하세요:");
      console.log(`LDEDUPROGRAM_ADDRESS=${ldEduProgramAddress}`);
      console.log(`USDC_ADDRESS=${usdcAddress}`);

      return { ldEduProgramAddress, usdcAddress };
    } catch (error) {
      console.error("❌ 배포 실패:", error.message);
      throw error;
    }
  }

  // 기존 컨트랙트 연결
  async connectToContracts() {
    try {
      console.log("\n🔗 기존 컨트랙트 연결 중...");

      this.ldEduProgram = new Contract(
        LDEDUPROGRAM_ADDRESS,
        ldEduProgramABI,
        this.ownerWallet
      );
      this.usdc = new Contract(USDC_ADDRESS, usdcABI, this.ownerWallet);

      console.log("✅ 컨트랙트 연결 완료");
      console.log(`📍 LdEduProgram: ${LDEDUPROGRAM_ADDRESS}`);
      console.log(`📍 TestUSDC: ${USDC_ADDRESS}`);
    } catch (error) {
      console.error("❌ 컨트랙트 연결 실패:", error.message);
      throw error;
    }
  }

  // USDC 화이트리스트 설정
  async setupUSDCWhitelist(usdcAddress) {
    try {
      console.log("\n⚙️ USDC 화이트리스트 설정 중...");

      const tx = await this.ldEduProgram.setTokenWhitelist(usdcAddress, true, {
        gasLimit: 1000000,
        maxFeePerGas: parseUnits("50", "gwei"),
        maxPriorityFeePerGas: parseUnits("40", "gwei"),
      });
      await tx.wait();
      console.log("✅ USDC 화이트리스트 추가 완료");
    } catch (error) {
      console.error("❌ 화이트리스트 설정 실패:", error.message);
      throw error;
    }
  }

  // 계정들에 USDC 배포
  async distributeUSDC() {
    try {
      console.log("\n💰 USDC 배포 중...");

      const accounts = [
        this.validatorWallet.address,
        this.builderWallet.address,
      ];
      const amount = parseUnits("10000", 6); // 10,000 USDC

      for (const account of accounts) {
        const tx = await this.usdc.mint(account, amount);
        await tx.wait();
        console.log(`✅ ${account}에게 10,000 USDC 전송`);
      }
    } catch (error) {
      console.error("❌ USDC 배포 실패:", error.message);
      throw error;
    }
  }

  // ETH 프로그램 생성 테스트
  async testCreateETHProgram() {
    try {
      console.log("\n🧪 ETH 프로그램 생성 테스트...");

      const programData = {
        name: "Learn Solidity Fundamentals",
        price: parseEther("0.1"),
        startTime: Math.floor(Date.now() / 1000) + 300, // 5분 후
        endTime: Math.floor(Date.now() / 1000) + 604800, // 1주일 후
        validator: this.validatorWallet.address,
        token: ZeroAddress, // ETH
      };

      console.log(`📋 프로그램 정보:`);
      console.log(`   이름: ${programData.name}`);
      console.log(`   가격: ${formatEther(programData.price)} ETH`);
      console.log(`   검증자: ${programData.validator}`);

      const tx = await this.ldEduProgram.createEduProgram(
        programData.name,
        programData.price,
        programData.startTime,
        programData.endTime,
        programData.validator,
        programData.token,
        { value: programData.price }
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find((log) => {
        try {
          const parsed = this.ldEduProgram.interface.parseLog(log);
          return parsed.name === "ProgramCreated";
        } catch {
          return false;
        }
      });

      if (event) {
        const parsedEvent = this.ldEduProgram.interface.parseLog(event);
        const programId = parsedEvent.args[0].toString();
        console.log(`🎉 ETH 프로그램 생성 완료! 프로그램 ID: ${programId}`);
        return programId;
      }
    } catch (error) {
      console.error("❌ ETH 프로그램 생성 실패:", error.message);
      throw error;
    }
  }

  // USDC 프로그램 생성 테스트
  async testCreateUSDCProgram() {
    try {
      console.log("\n🧪 USDC 프로그램 생성 테스트...");

      const programData = {
        name: "DeFi Development Course",
        price: parseUnits("1000", 6), // 1000 USDC
        startTime: Math.floor(Date.now() / 1000) + 300,
        endTime: Math.floor(Date.now() / 1000) + 604800,
        validator: this.validatorWallet.address,
        token: await this.usdc.getAddress(),
      };

      // USDC 승인
      console.log("📝 USDC 승인 중...");
      const approveUSDC = this.usdc.connect(this.ownerWallet);
      const approveTx = await approveUSDC.approve(
        await this.ldEduProgram.getAddress(),
        programData.price
      );
      await approveTx.wait();
      console.log("✅ USDC 승인 완료");

      console.log(`📋 프로그램 정보:`);
      console.log(`   이름: ${programData.name}`);
      console.log(`   가격: ${formatUnits(programData.price, 6)} USDC`);
      console.log(`   검증자: ${programData.validator}`);

      const tx = await this.ldEduProgram.createEduProgram(
        programData.name,
        programData.price,
        programData.startTime,
        programData.endTime,
        programData.validator,
        programData.token
      );

      const receipt = await tx.wait();
      const event = receipt.logs.find((log) => {
        try {
          const parsed = this.ldEduProgram.interface.parseLog(log);
          return parsed.name === "ProgramCreated";
        } catch {
          return false;
        }
      });

      if (event) {
        const parsedEvent = this.ldEduProgram.interface.parseLog(event);
        const programId = parsedEvent.args[0].toString();
        console.log(`🎉 USDC 프로그램 생성 완료! 프로그램 ID: ${programId}`);
        return programId;
      }
    } catch (error) {
      console.error("❌ USDC 프로그램 생성 실패:", error.message);
      throw error;
    }
  }

  // ETH 마일스톤 지급 테스트
  async testETHMilestone(programId) {
    try {
      console.log(
        `\n🧪 ETH 마일스톤 지급 테스트 (프로그램 ID: ${programId})...`
      );

      const reward = parseEther("0.05");

      // Builder의 초기 잔액 확인
      const builderBalanceBefore = await this.provider.getBalance(
        this.builderWallet.address
      );
      console.log(
        `💰 Builder 초기 잔액: ${formatEther(builderBalanceBefore)} ETH`
      );

      // Validator로 마일스톤 지급
      const validatorContract = this.ldEduProgram.connect(this.validatorWallet);
      const tx = await validatorContract.acceptMilestone(
        programId,
        this.builderWallet.address,
        reward
      );
      await tx.wait();

      // Builder의 잔액 확인
      const builderBalanceAfter = await this.provider.getBalance(
        this.builderWallet.address
      );
      console.log(
        `💰 Builder 최종 잔액: ${formatEther(builderBalanceAfter)} ETH`
      );
      console.log(`✅ ETH 마일스톤 지급 완료! (${formatEther(reward)} ETH)`);

      return true;
    } catch (error) {
      console.error("❌ ETH 마일스톤 지급 실패:", error.message);
      throw error;
    }
  }

  // USDC 마일스톤 지급 테스트
  async testUSDCMilestone(programId) {
    try {
      console.log(
        `\n🧪 USDC 마일스톤 지급 테스트 (프로그램 ID: ${programId})...`
      );

      const reward = parseUnits("500", 6);
      const milestoneId = "milestone-1";

      // Builder의 초기 USDC 잔액 확인
      const builderBalanceBefore = await this.usdc.balanceOf(
        this.builderWallet.address
      );
      console.log(
        `💰 Builder 초기 USDC 잔액: ${formatUnits(
          builderBalanceBefore,
          6
        )} USDC`
      );

      // Validator로 마일스톤 지급
      const validatorContract = this.ldEduProgram.connect(this.validatorWallet);
      const tx = await validatorContract.acceptMilestone(
        programId,
        milestoneId,
        this.builderWallet.address,
        reward
      );
      await tx.wait();

      // Builder의 USDC 잔액 확인
      const builderBalanceAfter = await this.usdc.balanceOf(
        this.builderWallet.address
      );
      console.log(
        `💰 Builder 최종 USDC 잔액: ${formatUnits(builderBalanceAfter, 6)} USDC`
      );
      console.log(
        `✅ USDC 마일스톤 지급 완료! (${formatUnits(reward, 6)} USDC)`
      );

      return true;
    } catch (error) {
      console.error("❌ USDC 마일스톤 지급 실패:", error.message);
      throw error;
    }
  }

  // 프로그램 정보 조회
  async getProgramInfo(programId) {
    try {
      console.log(`\n🔍 프로그램 정보 조회 (ID: ${programId})...`);

      const program = await this.ldEduProgram.eduPrograms(programId);
      const isETH = program.token === ZeroAddress;

      console.log("\n📋 프로그램 정보:");
      console.log(`   ID: ${program.id.toString()}`);
      console.log(`   이름: ${program.name}`);
      console.log(
        `   가격: ${
          isETH
            ? formatEther(program.price) + " ETH"
            : formatUnits(program.price, 6) + " USDC"
        }`
      );
      console.log(
        `   시작: ${new Date(
          Number(program.startTime) * 1000
        ).toLocaleString()}`
      );
      console.log(
        `   종료: ${new Date(Number(program.endTime) * 1000).toLocaleString()}`
      );
      console.log(`   생성자: ${program.maker}`);
      console.log(`   검증자: ${program.validator}`);
      console.log(`   토큰: ${isETH ? "ETH" : "USDC"}`);
      console.log(`   청구 여부: ${program.claimed ? "청구됨" : "미청구"}`);

      return program;
    } catch (error) {
      console.error("❌ 프로그램 정보 조회 실패:", error.message);
      throw error;
    }
  }

  // 컨트랙트 잔액 확인
  async checkContractBalances() {
    try {
      console.log("\n💳 컨트랙트 잔액 확인...");

      const ethBalance = await this.ldEduProgram.getContractBalance(
        ZeroAddress
      );
      const usdcBalance = await this.ldEduProgram.getContractBalance(
        await this.usdc.getAddress()
      );

      console.log(`💰 컨트랙트 ETH 잔액: ${formatEther(ethBalance)} ETH`);
      console.log(`💰 컨트랙트 USDC 잔액: ${formatUnits(usdcBalance, 6)} USDC`);

      return { ethBalance, usdcBalance };
    } catch (error) {
      console.error("❌ 잔액 확인 실패:", error.message);
      throw error;
    }
  }

  // 전체 테스트 실행
  async runFullTest() {
    try {
      console.log("🚀 전체 테스트 시작!\n");

      // 1. 컨트랙트 배포 (또는 연결)
      if (LDEDUPROGRAM_ADDRESS && USDC_ADDRESS) {
        await this.connectToContracts();
      } else {
        await this.deployContracts();
      }

      // 2. USDC 배포
      await this.distributeUSDC();

      // 3. ETH 프로그램 테스트
      const ethProgramId = await this.testCreateETHProgram();
      await this.testETHMilestone(ethProgramId);

      // 4. USDC 프로그램 테스트
      const usdcProgramId = await this.testCreateUSDCProgram();
      await this.testUSDCMilestone(usdcProgramId);

      // 5. 프로그램 정보 확인
      await this.getProgramInfo(ethProgramId);
      await this.getProgramInfo(usdcProgramId);

      // 6. 컨트랙트 잔액 확인
      await this.checkContractBalances();

      console.log("\n🎉 전체 테스트 완료!");
    } catch (error) {
      console.error("❌ 전체 테스트 실패:", error.message);
      throw error;
    }
  }
}

// 명령행 처리
async function main() {
  const args = process.argv.slice(2);
  const [command, ...params] = args;

  const tester = new LdEduProgramTester();

  try {
    switch (command) {
      case "deploy":
        await tester.deployContracts();
        break;

      case "connect":
        await tester.connectToContracts();
        break;

      case "whitelist":
        if (!params[0]) throw new Error("USDC address required");
        await tester.connectToContracts();
        await tester.setupUSDCWhitelist(params[0]);
        break;

      case "distribute-usdc":
        await tester.connectToContracts();
        await tester.distributeUSDC();
        break;

      case "create-eth":
        await tester.connectToContracts();
        await tester.testCreateETHProgram();
        break;

      case "create-usdc":
        await tester.connectToContracts();
        await tester.testCreateUSDCProgram();
        break;

      case "eth-milestone":
        if (!params[0]) throw new Error("Program ID required");
        await tester.connectToContracts();
        await tester.testETHMilestone(params[0]);
        break;

      case "usdc-milestone":
        if (!params[0]) throw new Error("Program ID required");
        await tester.connectToContracts();
        await tester.testUSDCMilestone(params[0]);
        break;

      case "info":
        if (!params[0]) throw new Error("Program ID required");
        await tester.connectToContracts();
        await tester.getProgramInfo(params[0]);
        break;

      case "balances":
        await tester.connectToContracts();
        await tester.checkContractBalances();
        break;

      case "full-test":
        await tester.runFullTest();
        break;

      default:
        console.log(`
🧪 LdEduProgram 테스트 도구

사용법: node test-contract.js <command> [parameters]

명령어:
  deploy                  컨트랙트 배포만 실행
  connect                 기존 컨트랙트 연결
  whitelist <address>     USDC 화이트리스트 설정
  distribute-usdc         계정들에 USDC 배포
  create-eth              ETH 프로그램 생성
  create-usdc             USDC 프로그램 생성
  eth-milestone <id>      ETH 마일스톤 지급
  usdc-milestone <id>     USDC 마일스톤 지급
  info <id>               프로그램 정보 조회
  balances                컨트랙트 잔액 확인
  full-test               전체 테스트 실행

예시:
  node test-contract.js deploy
  node test-contract.js whitelist 0x1234...
  node test-contract.js info 0
`);
    }
  } catch (error) {
    console.error("❌ 실행 오류:", error.message);
    process.exit(1);
  }
}

main();
