# 📚 LdEduProgram 스마트 컨트랙트

LdEduProgram 스마트 컨트랙트는 교육 프로그램을 관리하고, 제작자와 개발자 간의 보상을 투명하게 분배하는 역할을 합니다.

## 📌 기능 개요
| 기능 | 설명 |
|------|------|
| `createEduProgram` | 교육 프로그램을 생성 |
| `approveProgram` | 벨리데이터가 프로그램을 승인 |
| `claimGrants` | 빌더가 승인된 프로그램 보상 청구 |
| `reclaimFunds` | 만료된 프로그램의 예치금을 제작자가 회수 |
| `updateValidator` | 벨리데이터를 변경 |
| `setFee / getFee` | 수수료 설정 및 조회 |

---

## 📖 사용법

### 1 **스마트 컨트랙트 배포**
* remix
* foundry
* hardhat
* vanila javascript


### 2 **스마트 컨트랙트 배포**
```
struct EduProgram {
    uint256 id;
    string name;
    uint256 price;
    uint256 startTime;
    uint256 endTime;
    address maker;
    address validator;
    bool approve;
    bool claimed;
    address builder;
}

```


### 주요 이벤트
| 이벤트 | 설명 |
|------|------|
|ProgramCreated	|   프로그램이 생성될 때 발생
|ProgramApproved|	벨리데이터가 승인할 때 발생
|ProgramClaimed	|   빌더가 보상을 받을 때 발생



### Test
```
# 프로그램 생성
node test-contract.js create

# 프로그램 승인 (ID 지정)
node test-contract.js approve 0

# 그랜츠 청구 (ID 지정)
node test-contract.js claim 0

# 프로그램 정보 조회 (ID 지정)
node test-contract.js info 0

# 새 프로그램 생성부터 전체 프로세스 테스트
node test-contract.js all

# 기존 프로그램으로 전체 프로세스 테스트 (ID 지정)
node test-contract.js all 0

# 도움말 표시
node test-contract.js
```

### .env
```
RPC_URL = RPC URL = Edu Chain Testnet
CHAIN_ID=656476
PRIVATE_KEY=Owner의 Private Key  
CONTRACT_ADDRESS=컨트랙트 주소

VALIDATOR_ADDRESS=벨리데이터 주소
BUILDER_ADDRESS=빌더 주소
BUILDER_PRIVATE_KEY=빌더 Private Key

```


### Result 
```
robert@aragon:~/work/ludium/ludium-portal-contract$ node test-contract.js create
📝 프로그램 생성 중...
이름: 교육 프로그램 테스트
가격: 0.01 EDU
시작: 2025. 3. 17. 오후 11:54:21
종료: 2025. 3. 18. 오전 12:54:21
벨리데이터: 0x6e759B3B147FaF2E422cDAda8FA11A17DD544f36
✅ 트랜잭션 전송됨: 0x14103440198213c5638749b6510df9213812f6eb5fce977f2b0f2c0c97b566c7
🎉 프로그램 생성 완료! 프로그램 ID: 0
robert@aragon:~/work/ludium/ludium-portal-contract$ node test-contract.js info 0

🔍 프로그램 정보 조회 중... (ID: 0)

📋 프로그램 정보:
ID: 0
이름: 교육 프로그램 테스트
가격: 0.01 EDU
시작: 2025. 3. 17. 오후 11:54:21
종료: 2025. 3. 18. 오전 12:54:21
생성자: 0x6e759B3B147FaF2E422cDAda8FA11A17DD544f36
벨리데이터: 0x6e759B3B147FaF2E422cDAda8FA11A17DD544f36
승인 여부: 미승인
청구 여부: 미청구
빌더: 없음
```