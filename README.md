# REMIX ETH + 스테이블코인 결제 테스트 완전 가이드

## 🎯 테스트 목표

- ETH로 그랜트 프로그램 생성 및 보상 지급
- USDC로 그랜트 프로그램 생성 및 보상 지급
- 두 결제 방식이 모두 정상 작동하는지 확인

## 📋 준비사항

### 계정 역할

- **Account 0**: Owner (컨트랙트 배포자)
- **Account 1**: Maker (그랜트 생성자)
- **Account 2**: Validator (검증자)
- **Account 3**: Builder (수혜자)

---

## 🔧 1단계: 환경 설정

### 1-1. REMIX 접속 및 파일 생성

1. https://remix.ethereum.org 접속
2. `contracts/LdEduProgram.sol` 파일 생성
3. `contracts/USDC.sol` 파일 생성
4. 위에서 제공한 수정된 코드 복사

### 1-2. 컴파일러 설정

1. **Solidity Compiler** 탭 클릭
2. **Compiler**: `0.8.20` 선택
3. **Auto compile** 체크
4. 두 파일 모두 컴파일 (녹색 체크 확인)

---

## 🚀 2단계: 컨트랙트 배포

### 2-1. 배포 환경 설정

```
Deploy & Run Transactions 탭 클릭
Environment: Remix VM (Shanghai)
Account: Account 0 (0xAb8...c4c13d)
Gas Limit: 3000000
```

### 2-2. USDC 토큰 배포

```
Contract 선택: USDC
Constructor Parameters:
initialOwner: 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2

🔴 Deploy 버튼 클릭
```

### 2-3. LdEduProgram 배포

```
Contract 선택: LdEduProgram
Constructor Parameters:
initialOwner: 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2

🔴 Deploy 버튼 클릭
```

**✅ 결과**: 배포된 컨트랙트들이 하단에 표시됨

---

## ⚙️ 3단계: 초기 설정

### 3-1. USDC 화이트리스트 추가

```
Account: Account 0 (Owner)
LdEduProgram 컨트랙트에서:

함수: setTokenWhitelist
token: 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4 (USDC 주소 복사)
status: true

🔴 transact 버튼 클릭
```

### 3-2. 각 계정에 USDC 배포

```
🔄 Account를 Account 1로 변경
USDC 컨트랙트에서:
함수: faucet
🔴 transact 클릭

🔄 Account를 Account 2로 변경
함수: faucet
🔴 transact 클릭

🔄 Account를 Account 3으로 변경
함수: faucet
🔴 transact 클릭
```

### 3-3. USDC 잔액 확인

```
USDC 컨트랙트에서:
함수: balanceOf
account: [각 계정 주소]

예상 결과: 1000000000 (1000 USDC)
```

---

## 🧪 4단계: ETH 결제 테스트

### 4-1. ETH 프로그램 생성

```
🔄 Account를 Account 1로 변경 (Maker)

LdEduProgram.createEduProgram
Parameters:
_name: Learn Solidity Fundamentals
_price: 100000000000000000
_keywords: ["solidity","blockchain","smart-contracts"]
_startTime: 1735200000
_endTime: 1735804800
_validator: 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
_summary: Complete guide to Solidity programming
_description: Learn Solidity from basics to advanced concepts
_links: ["https://docs.soliditylang.org"]
_token: 0x0000000000000000000000000000000000000000

💰 VALUE: 100000000000000000 (0.1 ETH)

🔴 transact 클릭
```

### 4-2. ETH 프로그램 생성 확인

```
LdEduProgram.eduPrograms
programId: 0

확인사항:
- name: "Learn Solidity Fundamentals"
- price: 100000000000000000
- maker: Account 1 주소
- token: 0x0000000000000000000000000000000000000000
```

### 4-3. ETH 마일스톤 지급

```
🔄 Account를 Account 2로 변경 (Validator)

LdEduProgram.acceptMilestone
Parameters:
programId: 0
milestoneId: milestone-1
builder: 0x583031D1113aD414F02576BD6afaBfb302140225
reward: 50000000000000000

🔴 transact 클릭
```

### 4-4. ETH 결제 결과 확인

```
✅ Account 3의 ETH 잔액 확인 (0.05 ETH 증가)
✅ 컨트랙트 ETH 잔액 확인:
LdEduProgram.getContractBalance
token: 0x0000000000000000000000000000000000000000
결과: 50000000000000000 (0.05 ETH 남음)
```

---

## 💳 5단계: USDC 결제 테스트

### 5-1. USDC 승인 (Approve)

```
🔄 Account를 Account 1로 변경 (Maker)

USDC.approve
Parameters:
spender: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 (LdEduProgram 주소)
amount: 100000000

🔴 transact 클릭
```

### 5-2. USDC 프로그램 생성

```
Account: Account 1 (Maker)

LdEduProgram.createEduProgram
Parameters:
_name: DeFi Development Course
_price: 100000000
_keywords: ["defi","yield-farming","liquidity"]
_startTime: 1735200000
_endTime: 1735804800
_validator: 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
_summary: Learn DeFi protocol development
_description: Build DeFi protocols using modern tools
_links: ["https://defi.org"]
_token: 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4

💰 VALUE: 0 (ETH 전송하지 않음!)

🔴 transact 클릭
```

### 5-3. USDC 프로그램 생성 확인

```
LdEduProgram.eduPrograms
programId: 1

확인사항:
- name: "DeFi Development Course"
- price: 100000000
- token: USDC 컨트랙트 주소
```

### 5-4. USDC 마일스톤 지급

```
🔄 Account를 Account 2로 변경 (Validator)

LdEduProgram.acceptMilestone
Parameters:
programId: 1
milestoneId: milestone-1
builder: 0x583031D1113aD414F02576BD6afaBfb302140225
reward: 50000000

🔴 transact 클릭
```

### 5-5. USDC 결제 결과 확인

```
✅ Account 3의 USDC 잔액 확인:
USDC.balanceOf
account: 0x583031D1113aD414F02576BD6afaBfb302140225
결과: 1050000000 (1050 USDC = 기존 1000 + 50)

✅ 컨트랙트 USDC 잔액 확인:
LdEduProgram.getContractBalance
token: 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
결과: 50000000 (50 USDC 남음)
```

---

## 🔍 6단계: 최종 검증

### 6-1. 프로그램 상세 정보 확인

```
LdEduProgram.getProgramDetails
programId: 0
결과: ETH 프로그램 정보

LdEduProgram.getProgramDetails
programId: 1
결과: USDC 프로그램 정보
```

### 6-2. 전체 잔액 현황

```
📊 Account 3 (Builder) 최종 잔액:
- ETH: 원래 잔액 + 0.05 ETH
- USDC: 1050 USDC (1000 + 50)

📊 컨트랙트 잔액:
- ETH: 0.05 ETH (프로그램 0 남은 금액)
- USDC: 50 USDC (프로그램 1 남은 금액)
```

### 6-3. 이벤트 로그 확인

```
Console에서 확인할 이벤트들:
✅ ProgramCreated (2번 - ETH, USDC)
✅ MilestoneAccepted (2번 - ETH, USDC)
✅ TokenWhitelisted (1번 - USDC)
```

---

## 🎯 성공 기준 체크리스트

### ETH 결제 테스트

- [ ] ETH 프로그램 생성 성공 (0.1 ETH 전송)
- [ ] ETH 마일스톤 지급 성공 (0.05 ETH → Account 3)
- [ ] 컨트랙트에 0.05 ETH 남음 확인

### USDC 결제 테스트

- [ ] USDC approve 성공
- [ ] USDC 프로그램 생성 성공 (100 USDC 전송)
- [ ] USDC 마일스톤 지급 성공 (50 USDC → Account 3)
- [ ] 컨트랙트에 50 USDC 남음 확인

### 전체 시스템

- [ ] 두 결제 방식 모두 정상 작동
- [ ] 이벤트 로그 정상 출력
- [ ] 잔액 조회 함수 정상 작동

---

## 🐛 자주 발생하는 오류 해결

### ❌ "Token not whitelisted"

**해결**: USDC를 화이트리스트에 추가했는지 확인

```
LdEduProgram.whitelistedTokens
token: [USDC 주소]
결과: true 확인
```

### ❌ "Should not send ETH when paying with token"

**해결**: USDC 프로그램 생성 시 VALUE를 반드시 0으로 설정

### ❌ "The ETH sent does not match the program price"

**해결**: ETH 프로그램 생성 시 VALUE를 price와 정확히 일치시키기

### ❌ "Not validator"

**해결**: Account 2 (Validator)로 acceptMilestone 실행

### ❌ "Insufficient allowance"

**해결**: USDC 프로그램 생성 전에 반드시 approve 실행

이 가이드를 따라하면 REMIX에서 완벽한 ETH + 스테이블코인 이중 결제 시스템을 테스트할 수 있습니다! 🎉
