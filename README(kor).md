# 📚 LdEduProgram Smart Contract

LdEduProgram 스마트 컨트랙트는 교육 프로그램을 관리하고, 제작자와 개발자 간의 보상을 투명하게 분배하는 역할을 합니다.

## 🚀 Features

- Solidity`(^0.8.20)`

## 📋 Prerequisites

- Node.js (v16 or higher)
- Npm or Yarn
- ethers.js v5
- env


## 📖 Instructions

### ⚙️ Installation

```bash
git clone <https://github.com/Ludium-Official/ludium-portal-contract.git>
cd ludium-portal-contract
npm install
```

### ⚙️ 스마트 컨트랙트 컴파일
```
* remix
* foundry
* hardhat
* vanila javascript


hardhat
nvm use 20 
npx hardhat clean
npx hardhat compile

생성된 abi파일을 abi폴더에 복제해야함
artifacts/contracts/LdEduProgram.sol/LdEduProgram.json

```

### ⚙️ 스마트 컨트랙트 배포
```
node test-contract.js deploy
```

## 📂 Directory Structure

```
ludium-portal-contract/
├── abi/
│   └── LdEduProgram.json            # ABI 
├── artifacts/                       #  컴파일 결과
├── contracts/
│   └── LdEduProgram.sol             # 스마트 컨트랙트
├── .gitignore
├── package.json
├── package-lock.json
├── README.md                        # 프로젝트 설명
└── test-contract.js                 # 테스트 실행
```

## 📌 기능
| 기능 | 설명 |
|------|------|
| `createEduProgram` | 교육 프로그램을 생성 |
| `acceptMilestone` | 벨리데이터가 마일스톤을 승인 |
| `updateProgram` | 스폰서가 프로그램을 수정 - 상금, 날짜, validator |
| `reclaimFunds` | 프로그램 만료 후 상금 반환 |

---



### 주요 이벤트
| 이벤트 | 설명 |
|------|------|
| ProgramCreated |   프로그램이 생성될 때 발생
|MilestoneAccepted |   벨리데이터가 마일스톤 승인할 때 발생
|ProgramEdited |   프로그램 수정할 때 발생 
|FundsReclaimed |   스폰서에게 보상 돌아갈 때 발생


### Test
```
# 프로그램 생성
node test-contract.js create

# 마일스톤 승인
node test-contract.js accept-milestone {programId}

# 상금 회수 요청
node test-contract.js reclaim {programId}

# 프로그램 수정
node test-contract.js update-program {programId}

# 프로그램 정보 조회
node test-contract.js info {programId}

# 도움말
node test-contract.js
```

### .env
```
RPC_URL = 
CHAIN_ID= 
PRIVATE_KEY=
CONTRACT_ADDRESS=
VALIDATOR_ADDRESS=
BUILDER_ADDRESS=
WEPIN_APP_ID=
WEPIN_APP_KEY=
```

### 테스트 실행 결과
``` 
📝 reating a program...
Name: Ludium Program Test
Price: 0.01 EDU
Start: 2025. 3. 17. 오후 11:54:21
End: 2025. 3. 18. 오전 12:54:21
Validator: 0x6e759B3B147FaF2E422cDAda8FA11A17DD544f36
✅ Transaction: 0x14103440198213c5638749b6510df9213812f6eb5fce977f2b0f2c0c97b566c7
🎉 Program created! ID: 0
```
```
✅ Milestone accepted successfully
```
```
💸 Attempting to reclaim funds... (ID: ${programId})
✅ Funds reclaimed!
```
```
🛠️ Updating program...
✅ Program updated!
```
```
🔍 Fetching program info... (ID: ${programId})

📋 Program Info:
ID: 0
name: Ludium Program Test
price: 0.01 EDU
startDate: 2025. 3. 17. 오후 11:54:21
endDate: 2025. 3. 18. 오전 12:54:21
sponsor: 0x6e759B3B147FaF2E422cDAda8FA11A17DD544f36
validator: 0x6e759B3B147FaF2E422cDAda8FA11A17DD544f36
claimed : 미청구
```