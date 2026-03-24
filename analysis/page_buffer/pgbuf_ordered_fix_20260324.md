# pgbuf_ordered_fix 동작 원리와 필요성

## 왜 필요한가: 데드락 방지

일반적인 `pgbuf_fix`는 요청한 페이지를 그냥 latch(잠금)한다. 문제는 **두 스레드가 같은 페이지들을 반대 순서로 latch하면 데드락**이 발생한다는 점이다.

예시:
- 스레드 A: 페이지 (0,90) latch → 페이지 (0,100) latch 시도
- 스레드 B: 페이지 (0,100) latch → 페이지 (0,90) latch 시도
- → **순환 대기 = 데드락**

`pgbuf_ordered_fix`는 **모든 스레드가 동일한 순서로 페이지를 latch**하도록 강제하여 이 문제를 해결한다.

## 정렬 기준

`page_buffer.c`의 `pgbuf_compare_hold_vpid_for_sort` 함수가 정렬 순서를 정의한다:

1. **Group ID** (heap header의 VPID) — 같은 heap 파일의 페이지들을 묶음
2. **Rank** — `HEAP_HDR(0)` < `HEAP_NORMAL(1)` < `HEAP_OVERFLOW(2)`
3. **VPID** (volid → pageid) — 같은 rank 내에서 페이지 ID 순

즉, heap header 페이지가 항상 먼저 fix되고, 같은 종류의 페이지는 VPID 오름차순으로 fix된다.

## 핵심 동작 흐름

```
1. 새 페이지 fix 요청
2. 현재 스레드가 이미 다른 페이지를 hold하고 있는지 확인
   ├─ hold한 페이지가 없으면 → unconditional fix (순서 고려 불필요)
   └─ hold한 페이지가 있으면 → 낙관적 경로: conditional fix 시도
3. Conditional fix 결과:
   ├─ 성공 → 순서 위반 없이 바로 완료
   └─ 실패 → 비관적 경로: 데드락 위험이 있으므로 재정렬 수행
      a. 현재 hold한 모든 페이지의 정보를 watcher에서 수집
      b. 요청 페이지를 포함하여 전체를 VPID 순서로 정렬
      c. 요청 페이지보다 VPID가 **뒤**인 페이지만 unfix (앞에 있는 페이지는 이미 올바른 순서이므로 유지)
      d. 정렬된 순서대로 모든 페이지를 다시 unconditional fix
4. 성공 시 watcher->pgptr에 페이지 포인터 설정
```

**핵심 포인트**: 이 모든 과정은 `pgbuf_ordered_fix` 함수 내부에서 일어난다.
conditional fix는 "순서를 무시하는 것"이 아니라, 순서 위반 없이 바로 잡을 수 있는지를
낙관적으로 먼저 시도하는 것이다. 실패하면 비로소 unfix → 정렬 → refix의 비용을 지불한다.

### 실질적인 예시

같은 heap(group)에 속한 페이지 A(0,50), B(0,80), C(0,100)이 있다고 하자.
VPID 순서상 올바른 fix 순서는 A → B → C 이다.

**Case 1: 순서대로 fix — 재정렬 없음**

```
1. pgbuf_ordered_fix(A)  → hold 없음 → unconditional fix → 성공. hold: [A]
2. pgbuf_ordered_fix(B)  → A를 hold 중 → conditional fix 시도
                          → B는 A보다 뒤 → 순서 위반 없음 → 성공. hold: [A, B]
3. pgbuf_ordered_fix(C)  → A,B를 hold 중 → conditional fix 시도
                          → C는 B보다 뒤 → 순서 위반 없음 → 성공. hold: [A, B, C]
```

**Case 2: A→C를 hold한 상태에서 B를 요청 — 재정렬 발생**

```
1. pgbuf_ordered_fix(A)  → 성공. hold: [A]
2. pgbuf_ordered_fix(C)  → 순서 위반 없음 → 성공. hold: [A, C]
3. pgbuf_ordered_fix(B)  → A,C를 hold 중 → conditional fix 시도
                          → 실패 (B는 C보다 앞인데 C가 이미 hold됨)
   재정렬 시작:
   a. hold한 페이지 중 B보다 뒤인 것 수집 → C가 해당 (A는 B보다 앞이므로 유지)
   b. C를 unfix (C의 watcher에 page_was_unfixed = true)
   c. [A(유지), B(새로), C(재fix)]를 VPID 순서로 정렬
   d. 순서대로 unconditional fix: B → C
   결과 hold: [A, B, C] (올바른 순서)
```

**핵심**: 요청한 페이지(B)보다 VPID가 뒤인 페이지(C)만 unfix한다.
앞에 있는 페이지(A)는 이미 올바른 순서이므로 그대로 유지된다.
(`pgbuf_compare_hold_vpid_for_sort`로 비교하여 `diff > 0`이면 유지, `diff < 0`이면 unfix 대상)

**Case 3: C만 hold한 상태에서 A를 요청 — 전부 재정렬**

```
1. pgbuf_ordered_fix(C)  → 성공. hold: [C]
2. pgbuf_ordered_fix(A)  → C를 hold 중 → conditional fix 시도
                          → 실패 (A는 C보다 앞인데 C가 이미 hold됨)
   재정렬 시작:
   a. C를 unfix
   b. [A(새로), C(재fix)]를 VPID 순서로 정렬
   c. 순서대로 unconditional fix: A → C
   결과 hold: [A, C] (올바른 순서)
```

## 핵심 자료구조: PGBUF_WATCHER

`page_buffer.h:233-249`에 정의된 watcher가 ordered fix의 핵심이다:

```c
struct pgbuf_watcher {
  PAGE_PTR pgptr;              // fix된 페이지 포인터
  PGBUF_WATCHER *next, *prev;  // holder별 watcher 연결 리스트
  PGBUF_ORDERED_GROUP group_id; // 소속 heap header의 VPID
  unsigned latch_mode:7;
  unsigned page_was_unfixed:1;  // refix 발생 여부 (호출자가 확인해야 함)
  unsigned initial_rank:4;      // 초기 rank
  unsigned curr_rank:4;         // 현재 rank
};
```

- **group_id**: HFID(heap file ID)의 header page VPID로 설정됨. 같은 heap의 페이지들을 동일 그룹으로 묶어 정렬 기준으로 사용
- **page_was_unfixed**: refix가 발생하면 `true`로 설정됨. 호출자는 이 플래그를 확인해서 페이지 내용이 바뀌었을 수 있음을 인지해야 함

## PGBUF_ORDERED_RANK

```c
typedef enum {
  PGBUF_ORDERED_HEAP_HDR = 0,       // heap header 페이지 (가장 높은 우선순위)
  PGBUF_ORDERED_HEAP_NORMAL,        // 일반 heap 페이지
  PGBUF_ORDERED_HEAP_OVERFLOW,      // overflow 페이지
  PGBUF_ORDERED_RANK_UNDEFINED,     // 미정의
} PGBUF_ORDERED_RANK;
```

rank가 낮을수록(숫자가 작을수록) 먼저 fix된다. heap header는 항상 가장 먼저 fix되어야 한다.

## 사용 패턴

```c
PGBUF_WATCHER hdr_page_watcher;
PGBUF_INIT_WATCHER(&hdr_page_watcher, PGBUF_ORDERED_HEAP_HDR, &hfid);

error_code = pgbuf_ordered_fix(thread_p, &vpid, OLD_PAGE,
                                PGBUF_LATCH_WRITE, &hdr_page_watcher);
// ... 페이지 사용 ...
pgbuf_ordered_unfix(thread_p, &hdr_page_watcher);
```

## 관련 함수

| 함수 | 역할 |
|------|------|
| `pgbuf_ordered_fix` | 순서를 보장하며 페이지 fix |
| `pgbuf_ordered_unfix` | watcher 정리 후 페이지 unfix |
| `pgbuf_ordered_set_dirty_and_free` | dirty 마킹 후 ordered unfix |
| `pgbuf_get_condition_for_ordered_fix` | ordered_fix를 쓸 수 없을 때 latch condition 결정 |
| `pgbuf_compare_hold_vpid_for_sort` | 페이지 정렬 비교 함수 |

## 일반 pgbuf_fix와의 차이

| | `pgbuf_fix` | `pgbuf_ordered_fix` |
|---|---|---|
| 데드락 방지 | 없음 | VPID 순서 보장 |
| 기존 hold 페이지 처리 | 무관 | 필요시 unfix 후 재정렬 |
| 추적 | 없음 | Watcher로 추적 |
| 사용 대상 | 일반 페이지 | 주로 Heap 페이지 |
| 비용 | 낮음 | refix 시 추가 비용 |

## 주의사항

- refix가 발생하면 `watcher->page_was_unfixed`가 `true`로 설정되므로, 호출자는 반드시 이 플래그를 확인하여 페이지 내용 변경 가능성을 처리해야 한다.
- refix 중 이전에 fix된 페이지를 다시 fix하지 못하면, 요청한 페이지도 unfix하고 에러를 반환한다. 이 경우 호출자는 모든 watcher의 pgptr을 확인해야 한다.
- 주로 Heap 페이지(heap header, normal, overflow)에서 사용되며, 같은 heap 그룹 내의 페이지 순서를 보장하는 것이 핵심이다.

## Latch 대기 방식: Unconditional vs Conditional

| 모드 | 동작 |
|------|------|
| **Unconditional** | latch를 기다리되, `pgbuf_latch_timeout` (기본 300초)까지만 대기. timeout 시 에러 |
| **Conditional** | 전혀 기다리지 않음. 즉시 잡히면 성공, 아니면 바로 실패 반환 |

### Latch Timeout 발생 시 (`pgbuf_timed_sleep` 내부)

1. `thread_suspend_timeout_wakeup_and_unlock_entry`로 `pgbuf_latch_timeout`(기본 300초)만큼 대기
2. timeout 발생 시 (`ER_CSS_PTHREAD_COND_TIMEDOUT`):
   - 트랜잭션이 **비활성**(rollback 중 등)이면 → `goto try_again` (재시도)
   - 트랜잭션이 **활성**이면 → 데드락 victim으로 간주, `ER_PAGE_LATCH_TIMEDOUT` 에러 후 트랜잭션 abort

`pgbuf_ordered_fix`가 VPID 순서를 보장해서 데드락을 예방하는 것이고,
이 timeout은 만약의 데드락에 대한 최후의 안전장치이다.

### `pgbuf_ordered_fix` 내부에서의 사용

- 다른 페이지를 hold하고 있지 않으면 → **unconditional** (순서 고려 불필요)
- 다른 페이지를 hold하고 있으면 → **conditional** 먼저 시도
  - 성공 → 순서 위반 없이 완료
  - 실패 → hold한 페이지들을 unfix하고 VPID 순서대로 unconditional refix

## Read→Write Latch 승격 (Promote)과 Ordered Fix

`pgbuf_ordered_fix`는 read→write latch 승격을 고려하지 않는다.
Latch 승격은 별도의 함수 `pgbuf_promote_read_latch()`가 담당하며, ordered fix 메커니즘과는 독립적이다.

### `pgbuf_promote_read_latch` 동작

이미 read latch를 잡고 있는 페이지를 write latch로 승격하려는 경우:

1. **내가 유일한 reader인 경우** → 즉시 in-place 승격 (latch_mode를 WRITE로 변경)
2. **다른 reader도 있는 경우** → 조건에 따라 분기:
   - `PGBUF_PROMOTE_ONLY_READER` 조건: 유일한 reader일 때만 승격 허용 → 실패 (`ER_PAGE_LATCH_PROMOTE_FAIL`)
   - `PGBUF_PROMOTE_SHARED_READER` 조건: read latch를 해제하고 write 대기 큐의 **맨 앞**에 등록 후 대기
3. **이미 다른 promoter가 대기 중인 경우** → 무조건 실패 (promoter는 동시에 1개만 허용)

### 승격 실패 시 데드래치 위험

두 스레드가 같은 페이지에 read latch를 잡고 있다가 동시에 write로 승격하려 하면
서로가 상대방의 read latch 해제를 기다리는 데드래치가 발생할 수 있다.
이를 방지하기 위해 promoter는 동시에 1개만 허용하고, 이미 promoter가 있으면 즉시 실패를 반환한다.

즉, **ordered fix는 "서로 다른 페이지 간의 latch 순서"를 보장**하고,
**promote는 "같은 페이지 내에서 read→write 전환"을 처리**하며, 두 메커니즘은 독립적이다.

## B-tree Split과 승격에 의한 데드래치

B-tree split은 parent, child, new_child **세 페이지 모두 WRITE latch**가 필요하다.
(`btree_split_node` 시작 부분에 세 페이지 모두 WRITE assert가 있음)

### B-tree 구조와 순회

```
               [Root]              ← non-leaf (depth 0)
              /      \
        [NL-A]        [NL-B]       ← non-leaf (depth 1)
        /    \        /    \
    [Leaf-1] [Leaf-2] [Leaf-3] [Leaf-4]  ← leaf (depth 2)
```

INSERT 시 순회 경로 (예: Leaf-2에 삽입):
```
Root → NL-A → Leaf-2
```

### 승격에 의한 데드래치 시나리오

승격 자체는 데드래치를 유발할 수 있다. **2개 스레드만으로도 발생한다.**

만약 `PROMOTE_ONLY_READER` 없이 `PROMOTE_SHARED_READER`로 승격을 시도한다고 가정하자:

```
               [Root]
              /      \
        [NL-A]        [NL-B]
        /    \
    [Leaf-1] [Leaf-2]

T1: Root(R) → NL-A(R) → Leaf-2(W) 까지 진행, split 필요 → NL-A 승격 시도
T2: Root(R) → NL-A(R) 까지 진행 → Leaf-2(R) latch 시도
```

이 시점에서:
```
T1이 보유: NL-A(R), Leaf-2(W)  → NL-A를 W로 승격 대기 (T2가 NL-A에 READ 보유 중)
T2가 보유: NL-A(R)             → Leaf-2를 R로 latch 대기 (T1이 Leaf-2에 WRITE 보유 중)

T1은 T2가 NL-A(R)을 놓기를 기다림
T2는 T1이 Leaf-2(W)를 놓기를 기다림
→ 순환 대기 = 데드래치
```

**3개 스레드의 경우 — 승격끼리의 순환 대기**

2-thread 시나리오는 "승격 대기 vs latch 대기"의 순환이었다.
3-thread에서는 "승격 대기 vs 승격 대기"까지 포함한 더 복잡한 순환이 발생할 수 있다:

```
               [Root]
              /      \
        [NL-A]        [NL-B]
        /    \        /    \
    [Leaf-1] [Leaf-2] [Leaf-3] [Leaf-4]

T1: Root(R) → NL-A(R) → Leaf-2(W) 까지 진행, split 필요 → NL-A 승격 시도
T2: Root(R) → NL-A(R) → Leaf-1(W) 까지 진행, split 필요 → NL-A 승격 시도
T3: Root(R) → NL-A(R) 까지 진행 → Leaf-2(R) latch 시도
```

이 시점에서:
```
T1이 보유: NL-A(R), Leaf-2(W)  → NL-A 승격 대기 (T2, T3가 NL-A에 READ 보유 중)
T2가 보유: NL-A(R), Leaf-1(W)  → NL-A 승격 대기 (T1, T3가 NL-A에 READ 보유 중)
T3가 보유: NL-A(R)             → Leaf-2 latch 대기 (T1이 Leaf-2에 WRITE 보유 중)

T1은 T2, T3가 NL-A(R)을 놓기를 기다림
T2는 T1, T3가 NL-A(R)을 놓기를 기다림
T3는 T1이 Leaf-2(W)를 놓기를 기다림
→ 3자 순환 대기 = 데드래치
```

T1과 T2는 서로가 NL-A의 READ를 놓기를 기다리지만,
둘 다 승격 대기 중이므로 자발적으로 READ를 놓지 않는다.
T3는 T1이 Leaf-2(W)를 놓기를 기다리지만, T1은 승격 대기에 막혀 있다.
결국 어느 스레드도 진행할 수 없다.

(btree.c 27600-27602 라인 주석에 이 3-thread 시나리오가 명시되어 있음)

**2-thread vs 3-thread 데드래치의 핵심 차이**

| | 2-thread | 3-thread |
|---|---|---|
| 순환 구조 | 승격 대기 ↔ latch 대기 | 승격 대기 ↔ 승격 대기 |
| 원인 | parent 승격과 child latch가 교차 | 같은 parent에서 동시 승격 시도 |
| 예시 | T1: NL-A 승격 대기, T2: Leaf-2 latch 대기 | T1, T2: 둘 다 NL-A 승격 대기, T3: Leaf latch 대기 |
| `ONLY_READER` 방지 | T1이 NL-A 승격 즉시 실패 (T2가 reader) | T1, T2 모두 즉시 실패 (서로가 reader) |

두 경우 모두 `PROMOTE_ONLY_READER`가 방지한다. 다른 reader가 1명이라도 있으면
승격을 기다리지 않고 즉시 실패하므로, 순환 대기 자체가 형성되지 않는다.

### PGBUF_PROMOTE_ONLY_READER의 동작 원리

#### 무엇인가

`PGBUF_PROMOTE_CONDITION` enum 값으로, `pgbuf_promote_read_latch()` 호출 시
**인자(argument)**로 전달하는 조건이다. 페이지나 BCB에 저장되는 것이 아니다.

```c
typedef enum {
  PGBUF_PROMOTE_ONLY_READER,    // 내가 유일한 reader일 때만 승격
  PGBUF_PROMOTE_SHARED_READER   // 다른 reader가 있어도 대기하며 승격
} PGBUF_PROMOTE_CONDITION;

// 호출 예시
pgbuf_promote_read_latch(thread_p, &page, PGBUF_PROMOTE_ONLY_READER);
```

#### "나만 읽고 있는지"를 어떻게 판단하는가

각 페이지의 BCB(Buffer Control Block)에는 **atomic_latch**가 있고,
여기에 전체 fix count(`fcnt`)가 기록되어 있다:

```c
// BCB 안의 atomic_latch 구조
union pgbuf_atomic_latch_impl {
  uint64_t raw;                    // CAS 연산용
  struct {
    PGBUF_LATCH_MODE latch_mode;   // 현재 latch 모드 (READ/WRITE)
    uint16_t waiter_exists;        // 대기자 존재 여부
    int32_t fcnt;                  // ★ 이 페이지의 전체 fix count (모든 스레드 합산)
  } impl;
};
```

한편 각 스레드는 자기가 fix한 페이지마다 **holder**를 가지며,
holder에는 **자기의 fix count**가 기록되어 있다:

```c
struct pgbuf_holder {
  int fix_count;      // ★ 이 스레드가 이 페이지를 fix한 횟수
  PGBUF_BCB *bufptr;  // 해당 BCB 포인터
  // ...
};
```

판단 로직 (`page_buffer.c` 2686):

```c
if (holder->fix_count == impl.impl.fcnt)
  {
    // 내 fix count == 전체 fix count
    // → 나만 이 페이지를 잡고 있다 → 즉시 in-place 승격
    impl_new.impl.latch_mode = PGBUF_LATCH_WRITE;
  }
else
  {
    // 내 fix count < 전체 fix count
    // → 다른 스레드도 이 페이지를 잡고 있다
    if (condition == PGBUF_PROMOTE_ONLY_READER)
      {
        // ONLY_READER 조건: 즉시 실패 반환
        return ER_PAGE_LATCH_PROMOTE_FAIL;
      }
    else /* PGBUF_PROMOTE_SHARED_READER */
      {
        // SHARED_READER 조건: 내 read를 놓고 write 대기 큐 맨 앞에 등록
        impl_new.impl.fcnt -= fix_count;   // 전체 fcnt에서 내 몫 빼기
        need_block = true;                  // 대기 큐 진입
      }
  }
```

요약:
```
전체 fcnt (BCB.atomic_latch.fcnt) == 내 fix_count (holder.fix_count)
   → 나만 읽는 중 → 승격 가능

전체 fcnt > 내 fix_count
   → 다른 reader 존재
   → ONLY_READER이면 즉시 실패
   → SHARED_READER이면 대기
```

### CUBRID의 B-tree Split 방지 전략

**1단계: READ latch로 낙관적 순회 (성능 최적화)**

```
Root(R) → NL-A(R) → Leaf-2(W)
```

non-leaf 노드를 READ latch로 내려간다. split이 필요 없는 대부분의 경우
WRITE를 잡지 않으므로 동시성이 높다.
(leaf 노드는 거의 항상 변경되므로 처음부터 WRITE로 잡는다)

**2단계: Split 필요 시 승격 시도**

Leaf-2에서 split이 필요하면, parent인 NL-A를 WRITE로 승격해야 한다.
현재 노드(parent)와 child 노드에서 전략이 다르다:

```
               [Root]
              /      \
        [NL-A] ←── parent 승격: ONLY_READER (실패 시 즉시 포기)
        /    \
    [Leaf-1] [Leaf-2] ←── child 승격: SHARED_READER (대기 가능)
```

| 대상 | 승격 조건 | 이유 |
|------|-----------|------|
| **현재 노드 (parent: NL-A)** | `PGBUF_PROMOTE_ONLY_READER` | 내가 **유일한 reader**일 때만 승격 허용. 다른 reader가 있으면 즉시 실패 |
| **자식 노드 (child: Leaf-2)** | `PGBUF_PROMOTE_SHARED_READER` | 다른 reader가 있어도 대기 큐 맨 앞에서 승격 대기 가능 |
| **루트 노드** | `PGBUF_PROMOTE_SHARED_READER` | 루트는 parent가 없으므로 순환 대기 위험 낮음 |

parent에 `PROMOTE_ONLY_READER`를 쓰는 것이 핵심이다.
다른 reader가 있으면 **기다리지 않고 바로 실패**하므로, 데드래치 시나리오에서
T1이 NL-A 승격을 시도할 때 T3가 NL-A에 READ를 가지고 있으면 즉시 포기한다.
따라서 순환 대기가 형성되지 않는다.

child에 `PROMOTE_SHARED_READER`를 쓸 수 있는 이유는, parent latch를 이미 보유한
상태에서 child를 잡으므로 top-down 순서가 보장되어 순환이 발생하지 않기 때문이다.

코드 (`btree.c` 27900-27912):
```c
/* Promote mode is always ONLY_READER */
error_code = pgbuf_promote_read_latch (thread_p, crt_page, PGBUF_PROMOTE_ONLY_READER);
if (error_code == ER_PAGE_LATCH_PROMOTE_FAIL)
  {
    /* Could not promote. Restart insert from root by using write latch directly. */
    insert_helper->nonleaf_latch_mode = PGBUF_LATCH_WRITE;
    *restart = true;
    pgbuf_unfix_and_init (thread_p, child_page);
    pgbuf_unfix_and_init (thread_p, *crt_page);
    return NO_ERROR;
  }
```

**3단계: 승격 실패 시 — 처음부터 WRITE로 재순회**

승격이 실패하면 hold한 모든 페이지를 unfix하고, `nonleaf_latch_mode = PGBUF_LATCH_WRITE`로
설정한 뒤 루트부터 다시 순회한다. 이번에는 non-leaf 노드도 처음부터 WRITE latch로
잡으므로 승격이 필요 없고, 데드래치 위험도 없다.

```
1차 시도 (낙관적):
  Root(R) → NL-A(R) → Leaf-2(W)
  → split 필요 → NL-A 승격 시도(ONLY_READER) → 다른 reader 있음 → 실패
  → 모두 unfix, restart=true

2차 시도 (비관적):
  Root(W) → NL-A(W) → Leaf-2(W)
  → split 수행 → 성공 (승격 불필요)
```

### 정리

| 메커니즘 | 적용 대상 | 데드래치 방지 방법 |
|---------|-----------|-------------------|
| `pgbuf_ordered_fix` | Heap 페이지 (서로 다른 페이지 간) | VPID 순서로 재정렬 |
| `pgbuf_promote_read_latch` | 같은 페이지 내 read→write | promoter 1개 제한 + ONLY_READER |
| B-tree split | non-leaf 노드 승격 | ONLY_READER + 실패 시 WRITE 재순회 |

## 관련 소스 파일

- `src/storage/page_buffer.h` — 선언, 매크로, 자료구조
- `src/storage/page_buffer.c` — 구현 (ordered_fix: 11959~12779, promote: 2614~2812)
- `src/storage/heap_file.c` — ordered_fix 주요 사용처
- `src/storage/btree.c` — B-tree split 시 promote 사용 (27593~27954)
