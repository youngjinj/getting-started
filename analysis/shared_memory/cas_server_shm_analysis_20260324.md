# CAS-Server 통신: UDS vs Shared Memory 분석

> 분석일: 2026-03-24
> 대상: cub_cas(broker CAS) ↔ cub_server 간 IPC 통신 계층

## 현재 상태

CUBRID는 CAS↔Server 연결 시 **localhost 여부에 따라 자동으로 전송 방식을 선택**한다.

```
원격 호스트 → TCP (AF_INET)
localhost   → Unix Domain Socket (AF_UNIX)
```

자동 전환 로직: `src/connection/tcp.c` — `css_sockaddr()` (L375-394)

```c
in_addr = inet_addr(host);
if (in_addr == inet_addr("127.0.0.1"))
  {
    // AF_UNIX 사용
    unix_saddr.sun_family = AF_UNIX;
    strncpy (unix_saddr.sun_path, css_get_master_domain_path(), ...);
  }
else
  {
    // AF_INET (TCP) 사용
  }
```

UDS 소켓 경로: `/tmp/cubrid<master_port_id>` (기본: `/tmp/cubrid30000`)

---

## 1. UDS와 Shared Memory 간 이론적 성능 차이

### 1.1 Latency (단일 메시지 roundtrip)

| 방식 | Latency | 커널 경유 | 데이터 복사 횟수 |
|---|---|---|---|
| TCP localhost | ~10-50 us | O (TCP 스택 전체) | user→kernel→user (2회) |
| Unix Domain Socket | ~5-20 us | O (소켓 레이어만) | user→kernel→user (2회) |
| Shared Memory | ~0.5-2 us | X (futex 알림만) | 0회 (직접 접근) |

### 1.2 Throughput (대용량 데이터 전송)

| 방식 | 대역폭 | 병목 |
|---|---|---|
| TCP localhost | ~3-5 GB/s | TCP 프로토콜 스택 + memcpy 2회 |
| UDS | ~5-8 GB/s | memcpy 2회 + syscall overhead |
| Shared Memory | ~10-20 GB/s | 메모리 대역폭만 (memcpy 0~1회) |

### 1.3 데이터 경로 비교

**UDS 경로:**
```
CAS process                    Kernel                     cub_server process
─────────────────────────────────────────────────────────────────────────────
send(fd, buf, len)  →  [user→kernel memcpy]  →  recv(fd, buf, len)
                       소켓 버퍼 관리               [kernel→user memcpy]
                       poll/epoll 알림
```

**Shared Memory 경로:**
```
CAS process              Shared Memory Region              cub_server process
─────────────────────────────────────────────────────────────────────────────
memcpy(shm, buf, len)   ┌─────────────────────┐
         or              │  Ring Buffer         │   → 직접 읽기 (memcpy 0회)
  직접 쓰기 (0 copy)     │  (mmap 공유 영역)    │      or memcpy(buf, shm, len)
                         └─────────────────────┘
futex_wake()  ────────────────────────────────────→  futex_wait() 해제
```

### 1.4 쿼리 유형별 실질적 영향

| 시나리오 | 쿼리 실행 시간 | 통신 비용 (UDS) | UDS→SHM 절감 | 전체 개선율 |
|---|---|---|---|---|
| 단순 OLTP (PK lookup) | ~100 us | ~20 us | ~18 us | **~15%** |
| 중간 복잡도 (join) | ~5 ms | ~30 us | ~25 us | ~0.5% |
| 복잡한 OLAP | ~100 ms | ~50 us | ~45 us | **< 0.05%** |
| 대량 결과 (10MB fetch) | ~10 ms | ~2 ms | ~1.5 ms | **~10%** |
| 대량 결과 (100MB fetch) | ~50 ms | ~15 ms | ~12 ms | **~15%** |

**핵심**: Shared Memory의 이득은 **단순 OLTP 쿼리**와 **대량 결과 전송** 시나리오에서 유의미하다.

---

## 2. CUBRID가 UDS를 사용할 때의 부하

### 2.1 전체 쿼리 처리 흐름

```
CAS (client process)                          cub_server (server process)
──────────────────────────────────────────────────────────────────────────

1. SQL 파싱
   csql_grammar.y → PT_NODE 트리

2. 최적화
   optimizer → XASL_NODE 트리
   (포인터로 연결된 C 구조체)

3. ★ XASL 직렬화 ★
   xasl_to_stream.c
   - 포인터 → offset 변환
   - 구조체 → flat byte array
   - 비용: 수십~수백 us (복잡한 쿼리)

4. send(uds_fd, xasl_stream, len)             5. recv(uds_fd, xasl_stream, len)
   ─── UDS 전송 (~5-20 us) ──────────────→
                                              6. ★ XASL 역직렬화 ★
                                                 stream_to_xasl.c
                                                 - offset → 포인터 재구성
                                                 - malloc + memcpy로 구조체 복원
                                                 - 비용: 수십~수백 us

                                              7. 쿼리 실행 (scan, join, sort)
                                                 query_executor.c

                                              8. ★ 결과 직렬화 ★
                                                 - DB_VALUE → tuple record 패킹
                                                 - row 단위 byte stream 생성

10. recv(uds_fd, result, len)                 9. send(uds_fd, result, len)
    ←── UDS 전송 ────────────────────────────

11. ★ 결과 역직렬화 ★
    - byte stream → DB_VALUE 언패킹
```

### 2.2 직렬화 상세 (XASL)

**직렬화** (`src/query/xasl_to_stream.c`):

```c
// XASL_NODE 하나를 stream으로 변환할 때
OR_PUT_INT (ptr, xasl->type);             // 4바이트 정수 기록
OR_PUT_INT (ptr, xasl->flag);             // 4바이트 정수 기록
// ... 수십 개 필드를 하나씩 byte stream에 기록

// 포인터 필드는 offset으로 변환
if (xasl->spec_list != NULL)
  {
    offset = xts_save_access_spec_type (xasl->spec_list);
    OR_PUT_INT (ptr, offset);
  }
// 중첩 구조체는 재귀적으로 직렬화
```

**역직렬화** (`src/query/stream_to_xasl.c`):

```c
// byte stream에서 XASL_NODE 복원
xasl = (XASL_NODE *) stx_alloc_struct (sizeof (XASL_NODE));
xasl->type = OR_GET_INT (ptr);
xasl->flag = OR_GET_INT (ptr);

// offset에서 포인터로 복원 (malloc + memcpy)
offset = OR_GET_INT (ptr);
if (offset > 0)
  {
    xasl->spec_list = stx_restore_access_spec_type (&ptr);
  }
```

### 2.3 비용 비중 분석

```
단순 OLTP 쿼리 전체 시간 (~120 us 가정):
┌──────────────────────────────────────────────────────────┐
│ XASL 직렬화   │ UDS 전송 │ XASL 역직렬화 │ 쿼리 실행     │
│   ~15 us      │  ~10 us  │   ~15 us      │   ~60 us      │
│   (12.5%)     │  (8.3%)  │   (12.5%)     │   (50%)       │
│               │          │               │               │
│ 결과 직렬화   │ UDS 전송 │ 결과 역직렬화 │               │
│   ~5 us       │  ~10 us  │   ~5 us       │               │
│   (4.2%)      │  (8.3%)  │   (4.2%)      │               │
└──────────────────────────────────────────────────────────┘

직렬화/역직렬화 합계: ~40 us (33%)   ← UDS 전송(~20 us, 17%)보다 큼
```

**직렬화/역직렬화가 UDS 전송 자체보다 더 큰 오버헤드**이다.
따라서 전송 계층만 SHM으로 교체해도, 직렬화 비용은 그대로 남는다.

### 2.4 데이터 송수신 경로 (소켓 레이어)

현재 데이터 송수신은 소켓 종류에 무관한 generic POSIX API 사용:

| 함수 | 파일 | 역할 |
|---|---|---|
| `css_net_send()` | `connection_support.cpp:1058` | iovec 기반 송신 |
| `css_net_recv()` | `connection_support.cpp:526` | poll + recv 기반 수신 |
| `css_readn()` | `connection_support.cpp:357` | 바이트 스트림 읽기 |
| `css_writen()` | `connection_support.cpp:651` | 바이트 스트림 쓰기 |

이 레이어는 fd만 받으므로 TCP/UDS/기타 소켓 모두 동작한다.

---

## 3. Shared Memory 방식 적용을 위한 변경사항

### 3.1 하이브리드 설계 (권장)

기존 TCP/UDS 자동전환 로직을 확장하여 3단계 전환:

```
원격 호스트  → TCP (AF_INET) + 직렬화/역직렬화   — 기존 유지
localhost   → Shared Memory + 직렬화 제거        — 신규 (최고 성능)
localhost   → UDS (AF_UNIX) + 직렬화/역직렬화    — SHM 실패 시 fallback
```

`css_sockaddr()` 수준에서 SHM 채널 우선 시도, 실패 시 UDS fallback.

**핵심 원칙**: 로컬 SHM 경로에서는 직렬화/역직렬화를 하지 않는다.
XASL_NODE, DB_VALUE 등 구조체를 SHM에 직접 구축하여 두 프로세스가 공유한다.
직렬화를 유지하면서 전송 계층만 SHM으로 바꾸는 것은 UDS 대비 이점이 거의 없다.

### 3.2 SHM + 직렬화 제거 (목표 설계)

**개요**: XASL_NODE, DB_VALUE 등을 shared memory에 직접 할당하여 직렬화 자체를 우회

```
CAS                    Shared Memory                 cub_server
────────────────────────────────────────────────────────────────
XASL_NODE를
SHM에 직접 구축 → ┌─────────────────┐
(포인터 대신        │ XASL_NODE       │ → offset→포인터 변환만으로
 offset 사용)      │ (offset 기반)   │   직접 접근 (역직렬화 불필요)
                   └─────────────────┘
```

**필요한 변경:**

1. **포인터 → offset 전면 전환**
   ```c
   // 현재 (포인터 기반)
   struct xasl_node {
     XASL_NODE *next;              // 포인터 → 다른 프로세스에서 무효
     PRED_EXPR *if_pred;           // 포인터
     ACCESS_SPEC_TYPE *spec_list;  // 포인터
     // ... 수십 개의 포인터 필드
   };

   // SHM용 (offset 기반)
   struct xasl_node_shm {
     int32_t next_offset;          // SHM 내 offset
     int32_t if_pred_offset;       // offset
     int32_t spec_list_offset;     // offset
   };
   ```

2. **전용 SHM 메모리 할당기**
   - bump allocator 또는 slab allocator
   - 프로세스 간 공유 가능한 할당/해제
   - 기존 `db_private_alloc`, `malloc` 대체

3. **직렬화/역직렬화 우회**
   - `xasl_to_stream.c` (~5,000줄) 우회
   - `stream_to_xasl.c` (~5,000줄) 우회
   - 단, 원격 연결(TCP) 시에는 기존 경로 유지 필요

**영향 범위:**
- XASL_NODE 사용처: 수백 개 파일
- DB_VALUE 직렬화: 쿼리 결과 전체 경로
- 메모리 관리 패턴 전체 변경

**기대 효과:**
- 직렬화 비용 완전 제거 (~40 us/쿼리 절약)
- memcpy 최소화
- **예상 개선: OLTP 쿼리 ~30-40% 향상**

**리스크:**
- 변경 규모가 매우 큼 (수만 줄)
- 프로세스 crash 시 SHM leak/corruption 처리
- 디버깅 난이도 증가 (포인터 대신 offset)
- TCP 경로와의 이중 유지보수

### 3.3 예상 성능 개선

| 시나리오 | 현재 (UDS + 직렬화) | SHM + 직렬화 제거 | 개선율 |
|---|---|---|---|
| 단순 OLTP (PK lookup) | ~120 us | ~65 us | **~45%** |
| 중간 복잡도 (join) | ~5 ms | ~4.95 ms | ~1% |
| 복잡한 OLAP | ~100 ms | ~100 ms | < 0.1% |
| 대량 결과 (10MB fetch) | ~12 ms | ~5 ms | **~58%** |
| 대량 결과 (100MB fetch) | ~65 ms | ~20 ms | **~70%** |

직렬화 비용(~40 us) + UDS 전송 비용(~20 us) 모두 제거되므로,
**OLTP와 대량 결과 전송에서 유의미한 개선**이 가능하다.

### 3.5 프로세스 Crash 시 SHM Cleanup

두 접근법 모두 아래 문제를 해결해야 한다:

- **CAS crash**: Server가 SHM 연결 해제, 자원 회수
- **Server crash**: CAS가 감지 후 SHM detach, UDS fallback
- **감지 방법**: `server_pid`/`client_pid` 필드 + `kill(pid, 0)` 주기 확인 또는 eventfd
- **자원 회수**: `shm_unlink()` 또는 `shmctl(IPC_RMID)` — 마지막 detach 시 OS가 회수

---

## 4. 메모리 할당 전략: 왜 모든 할당이 SHM으로 가야 하는가

### 4.1 선별적 SHM 할당이 불가능한 이유

XASL_NODE는 수십 개의 포인터를 통해 하위 구조체를 재귀적으로 참조한다.
하나라도 로컬 힙에 있으면 상대 프로세스에서 접근 불가:

```c
// XASL_NODE의 포인터 체인 (일부)
XASL_NODE
  → PRED_EXPR *if_pred
    → EVAL_TERM.et_comp.lhs          // REGU_VARIABLE *
      → REGU_VARIABLE.value.dbval    // DB_VALUE
        → DB_VALUE.data.ch.medium.buf  // char * (문자열 데이터)
  → ACCESS_SPEC_TYPE *spec_list
    → INDX_INFO *indexptr
      → KEY_INFO.key_ranges          // KEY_RANGE *
  → VAL_LIST *val_list
    → VAL_LIST.valp → VAL_LIST.valp → ...  // linked list
  // ... 수십 개의 하위 포인터 트리
```

XASL 생성 과정에서 "이것은 공유 필요, 이것은 아님"을 구분하는 것은
구조체 전체를 분석하는 것보다 비용이 더 크다.
**따라서 XASL 생성 과정의 모든 할당을 SHM으로 보내는 것이 현실적이다.**

### 4.2 쿼리 단위 bump allocator

현재 `parser_alloc`이 parser context 종료 시 일괄 해제하는 것과 동일한 패턴:

```
쿼리 시작 → SHM bump allocator 초기화 (base pointer 설정)
           ↓
         XASL 생성 과정의 모든 alloc → shm_alloc(shm, size)
         (parser_alloc, malloc 대체)
           ↓
         Server가 SHM에서 직접 XASL 접근/실행
           ↓
         결과도 SHM에 기록
           ↓
쿼리 종료 → SHM 영역 일괄 reset (개별 free 불필요)
```

bump allocator는 `free`가 없으므로 단순하고 빠르다.
쿼리 종료 시 base pointer만 리셋하면 전체 메모리가 재사용 가능:

```c
struct shm_bump_allocator
{
  char *base;           /* SHM 영역 시작 주소 */
  size_t capacity;      /* 전체 크기 */
  size_t offset;        /* 현재 할당 위치 */
};

void *shm_alloc (shm_bump_allocator *alloc, size_t size)
{
  size = ALIGN8 (size);  /* 8바이트 정렬 */
  if (alloc->offset + size > alloc->capacity) return NULL;  /* OOM */
  void *ptr = alloc->base + alloc->offset;
  alloc->offset += size;
  return ptr;
}

void shm_reset (shm_bump_allocator *alloc)
{
  alloc->offset = 0;  /* 일괄 해제 */
}
```

### 4.3 현재 unpack 메모리와의 관계

현재 CUBRID에서 `stream_to_xasl` (역직렬화) 시 각 스레드가 자체 unpack 영역에
메모리를 할당하여 XASL 트리를 복원한다:

```
현재 (스레드별 unpack 메모리):

CAS thread                              Server thread
───────────────────────────────────────────────────────
parser_alloc → XASL 생성
  ↓
xasl_to_stream (직렬화)
  ↓
  ═══ UDS 전송 ════════════════════→
                                     stx_alloc_struct → unpack area에 할당
                                     (스레드별 독립 메모리)
                                       ↓
                                     XASL 트리 복원 (역직렬화)
                                       ↓
                                     쿼리 실행
                                       ↓
                                     unpack area 해제
```

SHM 방식은 이 unpack 메모리를 **프로세스 간 공유 영역으로 통합**하는 개념:

```
SHM 방식 (공유 메모리 통합):

CAS process                             Server process
───────────────────────────────────────────────────────
         ┌─────────────────────────┐
         │  SHM 영역 (mmap 공유)    │
         │                         │
shm_alloc → XASL 직접 생성         │  → base+offset으로 직접 접근
         │  (직렬화 불필요)         │    (역직렬화 불필요)
         │                         │    (unpack 할당 불필요)
         │  결과도 여기에 기록 ←────│──  쿼리 실행 결과
         │                         │
         └─────────────────────────┘
쿼리 종료 → shm_reset()
```

**핵심 차이**: 기존에는 "CAS 할당 → 직렬화 → 전송 → 역직렬화 → Server 할당"으로
**같은 데이터가 2번 할당**되었다. SHM에서는 **1번만 할당**하고 양쪽이 공유한다.

### 4.4 할당기 교체 지점

| 현재 할당기 | 사용처 | SHM 전환 시 |
|---|---|---|
| `parser_alloc()` | CAS: XASL 생성 | → `shm_alloc()` |
| `stx_alloc_struct()` | Server: XASL 역직렬화 | → **제거** (SHM 직접 접근) |
| `db_private_alloc()` | Server: 쿼리 실행 중 임시 할당 | → 유지 (실행 중 로컬 할당) |
| `db_private_alloc()` | Server: 결과 생성 | → `shm_alloc()` (결과 공유 시) |

`db_private_alloc` 자체를 SHM으로 바꿀 필요는 없다.
쿼리 실행 중 임시 데이터(hash table, sort buffer 등)는 서버 로컬이면 충분하다.
**공유가 필요한 것은 "경계를 넘는 데이터" (XASL, 결과)뿐이고,
그 데이터의 모든 하위 할당이 SHM 안에 있어야 한다.**

---

## 5. PostgreSQL Shared Memory와의 비교

### 5.1 PostgreSQL의 Shared Memory 구성

PostgreSQL의 shared memory는 **여러 기능이 합쳐진 단일 대형 공유 영역**이다:

```
PostgreSQL Shared Memory (shared_memory_size, 보통 수백 MB ~ 수 GB)
┌─────────────────────────────────────────────────────────┐
│  shared_buffers (페이지 버퍼 캐시)         ~80-90%      │
│  ┌─────────────────────────────────────────────┐        │
│  │ 디스크 페이지 캐시 (8KB 단위)                │        │
│  │ 모든 backend이 동일한 버퍼풀을 공유          │        │
│  │ LRU/Clock-sweep 교체 알고리즘              │        │
│  └─────────────────────────────────────────────┘        │
│                                                         │
│  WAL buffers (WAL 로그 버퍼)               ~1-2%       │
│  Lock table (행 잠금, 데드락 감지)          ~1-2%       │
│  Proc array (트랜잭션 상태, MVCC 스냅샷)    ~1%        │
│  CLOG/Commit log (커밋 상태 비트맵)         ~1%        │
│  기타 (통계, 알림 큐 등)                    ~1%        │
└─────────────────────────────────────────────────────────┘
```

### 5.2 PG와 CUBRID의 구조적 차이

```
PostgreSQL:
  Client → Backend process (파싱 + 최적화 + 실행 ALL IN ONE)
           ↓
           Shared Memory (버퍼풀, 잠금, WAL)
           ↓
           Disk

CUBRID:
  Client → CAS process (파싱 + 최적화) →→→ cub_server (실행)
              ↓ [직렬화/UDS 전송]              ↓
                                          Buffer Pool (서버 내부)
                                              ↓
                                            Disk
```

**PG는 직렬화 문제가 없다** — 파싱/최적화/실행이 같은 프로세스 안에서 일어나므로
XASL 같은 쿼리 플랜을 프로세스 간에 전달할 필요가 없다.

### 5.3 PG의 SHM vs 우리가 논의하는 SHM

| 구분 | PostgreSQL SHM | CUBRID SHM (제안) |
|---|---|---|
| **주 목적** | 페이지 버퍼 캐시 공유 | XASL/결과 직렬화 제거 |
| **공유 대상** | 디스크 페이지, 잠금, WAL, 트랜잭션 상태 | 쿼리 플랜(XASL), 쿼리 결과(DB_VALUE) |
| **공유 주체** | Backend ↔ Backend (동일 역할 프로세스 간) | CAS ↔ Server (역할이 다른 프로세스 간) |
| **생명주기** | 서버 시작~종료 (영구적) | 쿼리 시작~종료 (일시적) |
| **크기** | 수 GB (shared_buffers) | 수 MB (쿼리당) |
| **해결하는 문제** | 디스크 I/O 감소 | 프로세스 간 데이터 전송 비용 제거 |

### 5.4 CUBRID에서 PG 방식을 적용한다면

PG 방식의 "버퍼풀 SHM 공유"를 CUBRID에 적용하면,
CAS가 서버의 페이지 버퍼에 직접 접근하는 것을 의미한다.
이는 우리가 논의하는 XASL 직렬화 제거와는 **별개의 최적화**이다:

```
완전한 SHM 구조 (PG 스타일 + XASL 직렬화 제거를 결합한 경우):

┌─────────────────────────────────────────────────────────┐
│  SHM 영역 1: 페이지 버퍼 캐시 (PG의 shared_buffers)     │
│  - cub_server와 CAS가 동일 버퍼풀 공유                  │
│  - CAS가 직접 페이지 읽기 가능 (서버 경유 불필요)        │
│  - 현재 CUBRID에는 없는 구조                            │
│                                                         │
│  SHM 영역 2: 쿼리 통신 영역 (우리가 논의하는 것)         │
│  - XASL 쿼리 플랜 공유                                  │
│  - 쿼리 결과 공유                                       │
│  - 쿼리 단위 bump allocator                             │
│                                                         │
│  SHM 영역 3: 잠금/트랜잭션 상태                          │
│  - Lock table, MVCC 스냅샷                              │
│  - 현재 서버 내부에만 존재                               │
└─────────────────────────────────────────────────────────┘
```

**결론: PG의 SHM은 "페이지 버퍼 공유"가 핵심이고,
우리가 논의하는 SHM은 "직렬화 제거"가 핵심이다.
두 가지는 상호 보완적이지만 별개의 최적화이다.**

---

## 6. 장기 프로젝트 서브태스크 목록

직렬화 제거 + SHM 기반 CAS↔Server 통신으로 전환하기 위한 단계별 태스크.

### Phase 1: SHM 인프라 구축

- [ ] **T1-1. SHM 메모리 할당기 설계 및 구현**
  - bump allocator (쿼리 단위 할당/일괄 해제)
  - `shm_open()` + `mmap()` 기반 공유 영역 생성
  - 프로세스 간 attach/detach API
  - 파일: 신규 `src/connection/shm_allocator.c/h`

- [ ] **T1-2. SHM 채널 관리자 구현**
  - CAS↔Server 간 SHM 영역 생성/연결/해제 lifecycle
  - `css_sockaddr()` 확장: localhost 시 SHM 우선 시도
  - futex 기반 알림 메커니즘 (데이터 준비 완료 signal)
  - 파일: 신규 `src/connection/shm_channel.c/h`, 수정 `src/connection/tcp.c`

- [ ] **T1-3. 프로세스 crash recovery**
  - CAS/Server crash 감지 (pid 확인, heartbeat)
  - SHM 자원 자동 회수 (`shm_unlink`)
  - SHM 실패 시 UDS fallback 경로
  - 파일: `src/connection/shm_channel.c/h`, `src/connection/connection_cl.c`

### Phase 2: offset 기반 구조체 접근 레이어

- [ ] **T2-1. SHM offset 포인터 래퍼 설계**
  - `shm_ptr<T>` 템플릿: offset ↔ 포인터 자동 변환
  - SHM base address + offset → 실제 포인터 계산
  - 기존 포인터 코드와의 호환 레이어 (점진적 전환 가능하도록)
  - 파일: 신규 `src/connection/shm_ptr.hpp`

- [ ] **T2-2. XASL_NODE 구조체 SHM 대응**
  - XASL_NODE의 포인터 필드 목록 정리 (수십 개)
  - `shm_ptr<T>` 적용 또는 별도 SHM용 구조체 정의
  - 영향 범위 파악: `src/xasl/`, `src/query/xasl.h`
  - 파일: `src/query/xasl.h`, `src/xasl/*.h`

- [ ] **T2-3. DB_VALUE SHM 직접 기록**
  - DB_VALUE를 SHM 영역에 직접 구축하는 API
  - 가변 길이 타입 (VARCHAR, BLOB) 처리
  - 파일: `src/compat/dbtype_def.h`, `src/object/object_primitive.c`

### Phase 3: XASL 직렬화 우회 (CAS → Server)

- [ ] **T3-1. XASL 생성을 SHM에 직접 수행**
  - `xasl_generation.c`에서 XASL 노드를 SHM allocator로 할당
  - 포인터 대신 offset 기반 연결
  - SHM 경로 / 기존 경로 분기 (`is_shm_connection` 플래그)
  - 파일: `src/parser/xasl_generation.c`

- [ ] **T3-2. `xasl_to_stream` 우회 경로**
  - SHM 연결 시 직렬화 skip → SHM 영역 base offset만 전달
  - TCP 연결 시 기존 `xasl_to_stream` 유지
  - 파일: `src/query/xasl_to_stream.c`, `src/communication/network_cl.c`

- [ ] **T3-3. `stream_to_xasl` 우회 경로**
  - SHM 연결 시 역직렬화 skip → offset에서 서버 측 포인터로 변환만
  - TCP 연결 시 기존 `stream_to_xasl` 유지
  - 파일: `src/query/stream_to_xasl.c`, `src/communication/network_sr.c`

### Phase 4: 결과 직렬화 우회 (Server → CAS)

- [ ] **T4-1. 쿼리 결과를 SHM에 직접 기록**
  - `QFILE_LIST_ID` 결과 페이지를 SHM 영역에 구축
  - 또는 결과 row를 DB_VALUE 배열로 SHM에 직접 기록
  - 파일: `src/query/list_file.c`, `src/query/query_executor.c`

- [ ] **T4-2. CAS 측 결과 읽기 우회**
  - SHM에서 결과를 직접 읽어 클라이언트 프로토콜로 변환
  - 기존 `net_recv` → `shm_read` 분기
  - 파일: `src/broker/cas_execute.c`, `src/communication/network_cl.c`

### Phase 5: 통합 및 안정화

- [ ] **T5-1. 연결 프로토콜 협상**
  - CAS↔Server 초기 handshake에서 SHM 지원 여부 교환
  - SHM 불가 시 자동 UDS fallback
  - 파일: `src/connection/connection_cl.c`, `src/connection/connection_sr.c`

- [ ] **T5-2. 설정 파라미터 추가**
  - `cubrid.conf`: SHM 활성화 여부, SHM 영역 크기
  - `cubrid_broker.conf`: CAS별 SHM 사용 설정
  - 파일: `src/base/system_parameter.c/h`

- [ ] **T5-3. 성능 벤치마크**
  - OLTP (sysbench point select) 비교: UDS vs SHM
  - 대량 결과 fetch 비교
  - 동시 접속 스케일 테스트
  - crash recovery 시나리오 테스트

- [ ] **T5-4. 기존 테스트 호환성**
  - 전 SQL regression 테스트 통과 확인
  - SHM on/off 양쪽 모두 테스트
  - HA 환경 (원격 연결) 테스트 — TCP 경로 정상 동작 확인

### 태스크 의존관계

```
Phase 1 (SHM 인프라)
  T1-1 ──→ T1-2 ──→ T1-3
              │
              ▼
Phase 2 (offset 레이어)
  T2-1 ──→ T2-2 ──→ T2-3
              │         │
              ▼         ▼
Phase 3 (XASL 우회)    Phase 4 (결과 우회)
  T3-1→T3-2→T3-3       T4-1→T4-2
              │              │
              ▼              ▼
Phase 5 (통합)
  T5-1 → T5-2 → T5-3 → T5-4
```

**우선순위**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
Phase 3(XASL)과 Phase 4(결과)는 Phase 2 완료 후 병렬 진행 가능.

---

## 결론

- **로컬 SHM 경로에서는 직렬화를 제거해야 의미 있는 성능 이득이 있다**
- 직렬화를 유지한 채 전송만 SHM으로 바꾸면 UDS 대비 이점이 거의 없음
- OLTP 워크로드와 대량 결과 전송에서 ~45-70% 개선 기대
- 변경 규모가 크므로 위 5개 Phase로 단계적 접근 필요
