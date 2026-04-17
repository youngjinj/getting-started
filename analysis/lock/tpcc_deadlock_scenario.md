# TPC-C Deadlock 시나리오: S_LOCK vs FOR KEY SHARE

## 전제

- warehouse 100개, terminal 200개
- FK: `DISTRICT(D_W_ID) REFERENCES WAREHOUSE(W_ID)`
- Payment TX와 New-Order TX가 **같은 warehouse(w=5), district(d=3)** 에 동시 접근
- 소스: `jTPCCTerminal.java` (BenchmarkSQL 4.1)

## BenchmarkSQL 실제 SQL 순서

### New-Order Transaction (line 821~)

```
Step  SQL                                                          Lock 대상
────  ──────────────────────────────────────────────────────────    ─────────────────────
 N1   SELECT c_discount, c_last, c_credit, w_tax                   (읽기만, lock 없음)
      FROM customer, warehouse
      WHERE w_id = 5 AND c_d_id = 3 AND c_id = ?

 N2   SELECT d_next_o_id, d_tax FROM district                      district(w=5,d=3)
      WHERE d_id = 3 AND d_w_id = 5 FOR UPDATE                    → U_LOCK 획득

 N3   UPDATE district SET d_next_o_id = d_next_o_id + 1            district(w=5,d=3)
      WHERE d_id = 3 AND d_w_id = 5                                → X_LOCK 승격
                                                                    → FK: warehouse(w=5)에
                                                                      S_LOCK 요청 ★

 N4   INSERT INTO orders (o_id, o_d_id, o_w_id, ...)               orders row
      VALUES (?, 3, 5, ...)                                         → X_LOCK

 N5   INSERT INTO new_order (no_o_id, no_d_id, no_w_id)            new_order row
      VALUES (?, 3, 5)                                              → X_LOCK

 N6   (loop) SELECT i_price FROM item WHERE i_id = ?               (읽기만)

 N7   (loop) SELECT s_quantity, ... FROM stock                      stock(s_i_id=?, w=5)
      WHERE s_i_id = ? AND s_w_id = 5 FOR UPDATE                   → U_LOCK

 N8   (loop) UPDATE stock SET s_quantity = ?                        stock row
      WHERE s_i_id = ? AND s_w_id = 5                               → X_LOCK

 N9   (loop) INSERT INTO order_line (...)                           order_line row
      VALUES (?, 3, 5, ...)                                         → X_LOCK

      COMMIT
```

### Payment Transaction (line 1263~)

```
Step  SQL                                                          Lock 대상
────  ──────────────────────────────────────────────────────────    ─────────────────────
 P1   UPDATE warehouse SET w_ytd = w_ytd + ?                       warehouse(w=5)
      WHERE w_id = 5                                                → X_LOCK 획득 ★

 P2   SELECT w_street_1, ... FROM warehouse WHERE w_id = 5         (읽기만, lock 없음)

 P3   UPDATE district SET d_ytd = d_ytd + ?                        district(w=5,d=3)
      WHERE d_w_id = 5 AND d_id = 3                                → X_LOCK 요청 ★
                                                                    → FK: warehouse(w=5)에
                                                                      S_LOCK (이미 자신이 보유)

 P4   SELECT d_street_1, ... FROM district                         (읽기만)
      WHERE d_w_id = 5 AND d_id = 3

 P5   SELECT / UPDATE customer ...                                 customer row

 P6   INSERT INTO history (...)                                    history row

      COMMIT
```

## Deadlock 시나리오 (S_LOCK 방식 - CUBRID)

```
시간   Payment TX (w=5, d=3)                New-Order TX (w=5, d=3)
─────  ──────────────────────────────────   ──────────────────────────────────

t1     [P1] UPDATE warehouse w_ytd
       → X_LOCK(warehouse w=5) 획득 ✓

t2                                          [N1] SELECT customer, warehouse
                                            → lock 없음 (MVCC 읽기) ✓

t3                                          [N2] SELECT district ... FOR UPDATE
                                            → U_LOCK(district w=5,d=3) 획득 ✓

t4                                          [N3] UPDATE district d_next_o_id
                                            → X_LOCK(district w=5,d=3) 승격 ✓
                                            → FK 검사: D_W_ID=5 → WAREHOUSE(W_ID=5)
                                              S_LOCK(warehouse w=5) 요청
                                              ⛔ 대기! (Payment의 X_LOCK과 비호환)

t5     [P2] SELECT warehouse
       → lock 없음 (MVCC 읽기) ✓

t6     [P3] UPDATE district d_ytd
       → X_LOCK(district w=5,d=3) 요청
       ⛔ 대기! (New-Order의 X_LOCK과 비호환)


       ┌─────────────────────────────────────────────────────────┐
       │                                                         │
       │  Payment ──(t6 대기)──→ district ←──(t3 보유)── New-Order│
       │                                                         │
       │  Payment ←──(t1 보유)── warehouse ──(t4 대기)──→ New-Order│
       │                                                         │
       │                  ★ DEADLOCK CYCLE ★                     │
       │                                                         │
       └─────────────────────────────────────────────────────────┘

t7     Deadlock 감지 (1초 주기)
       → New-Order가 victim → abort (ERROR_CODE = -72)
       → Payment 진행 → COMMIT
```

### Lock 충돌 지점

```
warehouse(w=5):
  Payment  보유: X_LOCK  (P1에서 획득)
  New-Order 요청: S_LOCK  (N3의 FK 검사)
  X vs S = 비호환 → New-Order 대기

district(w=5,d=3):
  New-Order 보유: X_LOCK  (N2→N3에서 획득)
  Payment  요청: X_LOCK  (P3에서 요청)
  X vs X = 비호환 → Payment 대기

→ 교차 대기 → deadlock
```

## 동일 시나리오 (FOR KEY SHARE 방식 - PG)

```
시간   Payment TX (w=5, d=3)                New-Order TX (w=5, d=3)
─────  ──────────────────────────────────   ──────────────────────────────────

t1     [P1] UPDATE warehouse w_ytd
       → FOR NO KEY UPDATE(warehouse w=5) ✓
         (w_ytd는 PK가 아니므로 NO KEY)

t2                                          [N1] SELECT customer, warehouse
                                            → lock 없음 (MVCC 읽기) ✓

t3                                          [N2] SELECT district ... FOR UPDATE
                                            → FOR UPDATE(district w=5,d=3) ✓

t4                                          [N3] UPDATE district d_next_o_id
                                            → FOR NO KEY UPDATE(district) ✓
                                            → FK 검사: D_W_ID=5 → WAREHOUSE(W_ID=5)
                                              FOR KEY SHARE(warehouse w=5) 요청
                                              ✅ 즉시 획득! (NO KEY UPDATE와 호환)

t5                                          [N4~N9] INSERT orders, new_order,
                                            order_line, UPDATE stock ...
                                            COMMIT → district lock 해제

t6     [P3] UPDATE district d_ytd
       → FOR NO KEY UPDATE(district) ✓
         (N5에서 lock 해제됨)
       COMMIT
```

### Lock 호환 지점

```
warehouse(w=5):
  Payment  보유: FOR NO KEY UPDATE  (P1, w_ytd 변경 = key 아님)
  New-Order 요청: FOR KEY SHARE     (N3의 FK 검사 = key 존재 확인만)
  NO KEY UPDATE vs KEY SHARE = 호환 → 즉시 획득 → deadlock 없음
```

## PG Row-Level Lock 호환성 표

```
                     FOR KEY    FOR      FOR NO KEY    FOR
요청 \\ 보유          SHARE     SHARE     UPDATE       UPDATE
─────────────────    ─────     ─────     ──────────    ──────
FOR KEY SHARE          O         O          O            X
FOR SHARE              O         O          X            X
FOR NO KEY UPDATE      O         X          X            X
FOR UPDATE             X         X          X            X
```

핵심: `FOR KEY SHARE` × `FOR NO KEY UPDATE` = **호환 (O)**

## CUBRID Lock 호환성 표 (관련 부분)

```
              S_LOCK    X_LOCK
  S_LOCK       O          X
  X_LOCK       X          X
```

핵심: `S_LOCK` × `X_LOCK` = **비호환 (X)**

## PG 소스 근거

### 1. FK 검사 시 FOR KEY SHARE 사용

FK 트리거 함수에서 부모 row 존재 확인 시:

```sql
-- ri_triggers.c가 내부적으로 생성하는 쿼리
SELECT 1 FROM warehouse WHERE w_id = $1 FOR KEY SHARE OF warehouse
```

`RI_PLAN_CHECK_LOOKUPPK` 플랜에서 `FOR KEY SHARE` lock strength를 지정한다.
관련 소스: `src/backend/utils/adt/ri_triggers.c` 내 `ri_PlanCheck_pk` 함수.

### 2. 일반 UPDATE는 FOR NO KEY UPDATE

key 컬럼을 변경하지 않는 UPDATE는 `LockTupleNoKeyExclusive` (= FOR NO KEY UPDATE)를 획득한다.
`UPDATE warehouse SET w_ytd = w_ytd + ?`는 PK인 `w_id`를 변경하지 않으므로 FOR NO KEY UPDATE.

관련 소스: `src/backend/access/heap/heapam_handler.c` 내 tuple lock 결정 로직.
key 컬럼 변경 여부는 `HeapDetermineColumnsInfo()`에서 판단한다.

### 3. Lock 호환성 정의

```c
// src/include/access/heapam.h
static const bool tupleLockCompatible[4][4] = {
    //                KeyShare  Share  NoKeyExcl  Excl
    /* KeyShare */    { true,   true,  true,      false },
    /* Share */       { true,   true,  false,     false },
    /* NoKeyExcl */   { true,   false, false,     false },
    /* Excl */        { false,  false, false,     false },
};
```

## CUBRID 소스 근거

### 1. FK 검사 시 S_LOCK

```c
// locator_sr.c:4145 — 부모 테이블 조회
ret = xbtree_find_unique(thread_p, &local_btid, S_SELECT_WITH_LOCK,
                         key_dbvalue, &part_oid, &unique_oid, true);
```

### 2. S_SELECT_WITH_LOCK → S_LOCK 확정

```c
// btree.c:24769
find_unique_helper.lock_mode =
    (scan_op_type == S_SELECT_WITH_LOCK) ? S_LOCK : X_LOCK;
```

### 3. 실제 lock 획득

```c
// btree.c:24315
lock_object(oid, class_oid, S_LOCK, LK_UNCOND_LOCK);
// → warehouse row에 S_LOCK
```

## 실제 서버 로그 증거

### event 로그 (`tpcc_wh100_*.event`)

```
03/27/26 17:56:25.556 - DEADLOCK
hold:
  client: DBA@perf10|broker1_cub_cas_5(1179549)
  lock: X_LOCK (oid=0|4545|29, table=dba.warehouse)          ← Payment P1
  sql: update warehouse set w_ytd = cast(w_ytd + ? ...) where w_id = ?

wait:
  client: DBA@perf10|broker1_cub_cas_72(1179675) (Deadlock Victim)
  lock: S_LOCK (oid=0|4545|29, table=dba.warehouse)          ← New-Order N3 FK
  sql: update district set d_next_o_id = ... where d_w_id = ? and d_id = ?
```

→ Payment가 warehouse에 X_LOCK 보유, New-Order가 같은 warehouse에 S_LOCK 요청 (FK 검사)
→ 동시에 New-Order가 district 보유, Payment가 같은 district 요청
→ **deadlock cycle 확인됨**

## CUBRID 코드 호출 체인

```
UPDATE district SET d_next_o_id = d_next_o_id + 1 WHERE d_w_id = ? AND d_id = ?
  │
  ├─ locator_sr.c:5396   locator_update_force()
  │    │
  │    └─ locator_sr.c:6010   FK 체크 진입
  │         if (!not_check_fk && !locator_Dont_check_foreign_key)
  │         │
  │         └─ locator_sr.c:4023   locator_check_foreign_key()
  │              │
  │              └─ locator_sr.c:4145   부모 row 조회
  │                   xbtree_find_unique(..., S_SELECT_WITH_LOCK, ...)
  │                   │
  │                   └─ btree.c:24769   lock 모드 결정
  │                        find_unique_helper.lock_mode =
  │                          (S_SELECT_WITH_LOCK) ? S_LOCK : X_LOCK
  │                        → S_LOCK 확정
  │                        │
  │                        └─ btree.c:24315   실제 lock 획득
  │                             lock_object(oid, class_oid, S_LOCK, LK_UNCOND_LOCK)
  │                             → warehouse row에 S_LOCK
```

### 핵심 코드

**1. FK 체크 호출** — `locator_sr.c:6010`
```c
if (!not_check_fk && !locator_Dont_check_foreign_key)
{
    error_code = locator_check_foreign_key(thread_p, hfid, class_oid,
                                           oid, recdes, ...);
}
```

**2. 부모 테이블 조회 시 S_SELECT_WITH_LOCK** — `locator_sr.c:4145`
```c
ret = xbtree_find_unique(thread_p, &local_btid, S_SELECT_WITH_LOCK,
                         key_dbvalue, &part_oid, &unique_oid, true);
```

**3. S_LOCK 확정** — `btree.c:24769`
```c
find_unique_helper.lock_mode =
    (scan_op_type == S_SELECT_WITH_LOCK) ? S_LOCK : X_LOCK;
```

## CUBRID MVCC UPDATE 흐름 — 레코드 먼저, lock은 나중

### 전통적 2PL vs MVCC

```
전통적 2PL:   lock → read → modify          (읽기에도 lock 필요)
MVCC(CUBRID): read(snapshot) → lock → modify (읽기는 lock 불필요)
```

MVCC에서는 snapshot이 consistent read를 보장하므로 스캔 단계에서 row lock 없이
후보 행을 수집한다. lock은 실제로 수정할 때 비로소 획득한다.

### UPDATE 실행 흐름

```
UPDATE district SET d_next_o_id = d_next_o_id + 1 WHERE d_w_id = ? AND d_id = ?
  │
  ├─ [스캔 단계] scan_manager.c
  │    MVCC snapshot으로 WHERE 조건 만족하는 OID 수집
  │    → row lock 없음 (snapshot이 visibility 보장)
  │
  └─ [수정 단계] locator_update_force() — need_locking=true
       │
       ├─ locator_decide_update_lock()
       │    PK 유무 + 변경 컬럼이 키인지 판단
       │    → 비키 UPDATE: WX_LOCK
       │    → 키 변경 or PK 없음: X_LOCK
       │
       └─ locator_lock_and_get_object_with_evaluation()
            lock 획득 + 최신 버전 fetch + WHERE 재평가(reevaluation)
```

### 왜 reevaluation이 필요한가

```
t1  스캔: OID=100 발견, WHERE 조건 일치 (snapshot 기준) — lock 없이 반환
t2  다른 TX가 OID=100 수정 후 COMMIT
t3  update_force: OID=100에 WX_LOCK 획득
    → reevaluation: 최신 버전으로 WHERE 재확인
      → 여전히 일치? → 수정 진행
      → 조건 불만족?  → skip (V_FALSE)
```

스캔 시점과 lock 획득 시점 사이에 다른 TX가 row를 바꿀 수 있기 때문에,
lock 획득 후 반드시 최신 버전으로 조건을 재평가한다.

### need_locking == false 경우

스캔 기반이 아닌 **직접 OID 지정 UPDATE** (클라이언트가 `SELECT FOR UPDATE` 등으로
이미 lock을 보유한 경우). 코드에서 assert로 보장한다:

```c
/* locator_sr.c:7582 */
assert ((lock_get_object_lock (oid, &class_oid) >= X_LOCK)
        || (lock_get_object_lock (&class_oid, oid_Root_class_oid) >= X_LOCK));
```

lock이 이미 있으므로 reevaluation도 불필요하다 (`mvcc_reev_data = NULL`).

### mvcc_select_lock_needed — SELECT FOR UPDATE 전용 플래그

`scan_id->mvcc_select_lock_needed`는 일반 UPDATE 흐름과 무관하다.

```
mvcc_select_lock_needed = true  조건:
  1. SELECT ... FOR UPDATE  (ACCESS_SPEC_FLAG_FOR_UPDATE 세트)
  2. click counter (INCR/DECR 연산, force_select_lock=true)

→ scan 단계에서 X_LOCK을 먼저 획득
→ locator_update_force 호출 시 instances_locked=true → need_locking=false
```

일반 UPDATE(`UPDATE district SET ...`)는 `mvcc_select_lock_needed=false`이다.
스캔은 lock 없이 진행되고, `locator_update_force`에서 `need_locking=true`로
`locator_decide_update_lock()`이 호출되어 WX_LOCK 또는 X_LOCK이 결정된다.

```
mvcc_select_lock_needed=true (SELECT FOR UPDATE / click counter):
  scan ─→ X_LOCK(row) ─→ locator_update_force(need_locking=false)
             ↑ scan이 lock 보유                ↑ 재획득 불필요

mvcc_select_lock_needed=false (일반 UPDATE):
  scan ─→ OID 수집(no lock) ─→ locator_update_force(need_locking=true)
                                  → locator_decide_update_lock()
                                  → WX_LOCK or X_LOCK 결정 후 획득
```

WX_LOCK 최적화(FK deadlock fix)는 `mvcc_select_lock_needed=false` 경로,
즉 일반 UPDATE에서만 동작한다.

---

## Isolation Level과 WS_LOCK / WX_LOCK

### lock과 isolation level의 역할 분리

```
RC / RR / SERIALIZABLE 공통:
  읽기 일관성  → MVCC snapshot 담당
  쓰기 충돌 방지 → 2PL lock 담당

WS_LOCK / WX_LOCK은 "쓰기 충돌 방지" 역할 → isolation level과 무관하게 유효
```

`lock_object`로 획득한 WS_LOCK은 트랜잭션 커밋까지 유지된다(2PL).
RR로 올라간다고 해서 S_LOCK으로 업그레이드해야 할 이유가 없다.

### RR에서 WS_LOCK이 보장하는 것

```
New-Order TX (RR, FK check):
  WS_LOCK(warehouse) 획득 → commit까지 유지

  WS_LOCK이 차단:
    ✅ X_LOCK(warehouse) — 부모 키 삭제/변경 방지
    ✅ WX_LOCK(warehouse) — 비키 컬럼 수정은 FK에 영향 없으므로 허용

  RR 반복 읽기 보장:
    → MVCC snapshot이 담당 (WS_LOCK 역할 아님)
```

WS_LOCK을 S_LOCK으로 올리면 Payment의 X_LOCK(warehouse)과 비호환 → deadlock 재발.

### PostgreSQL과 비교

| 항목 | CUBRID (WS/WX) | PostgreSQL |
|---|---|---|
| FK check lock | WS_LOCK | FOR KEY SHARE |
| 비키 UPDATE lock | WX_LOCK | FOR NO KEY UPDATE |
| 두 lock 호환 | ✅ YES | ✅ YES |
| RC에서 lock 유지 | commit까지 | commit까지 |
| RR에서 lock 유지 | commit까지 | commit까지 |
| RR 읽기 일관성 | MVCC snapshot | MVCC snapshot |
| SERIALIZABLE | MVCC (≒ RR) | SSI + predicate lock |

PG도 RR에서 FOR KEY SHARE를 S_LOCK으로 올리지 않는다.
반복 읽기는 snapshot의 몫, FK 보호는 key share lock의 몫으로 역할이 분리되어 있다.
CUBRID WS_LOCK과 PG FOR KEY SHARE는 설계 의도가 동일하다.

---

## U_LOCK과 WS_LOCK의 관계

### 기존 데드락의 실제 lock 패턴

기존 데드락은 **U_LOCK → S_LOCK** 패턴이 아니라 **X_LOCK → S_LOCK** 패턴이다.

```
TX (Payment):  X_LOCK(warehouse)  보유  ← P1 UPDATE warehouse
TX (New-Order): S_LOCK(warehouse)  요청  ← N3 FK 검사
                                    ⛔ X vs S = 비호환
```

U_LOCK은 `SELECT ... FOR UPDATE` 커서 스캔 단계에서만 사용된다.
FK 검사가 실행되는 시점(`locator_update_force` → `locator_check_foreign_key`)에는
이미 X_LOCK으로 업그레이드된 상태이므로 U_LOCK은 데드락에 직접 관여하지 않는다.

```
New-Order TX 흐름:
  N2  SELECT district FOR UPDATE  → U_LOCK(district)   ← U_LOCK 사용
  N3  UPDATE district             → X_LOCK(district)   ← U → X 업그레이드
        └─ FK 검사 진입           → S_LOCK(warehouse) 요청  ← 이 시점에 U 없음
```

### WS+U=NO / U+WS=YES 비대칭의 설계 근거

WS_LOCK과 U_LOCK의 비대칭은 기존 S+U 비대칭과 동일한 논리로 설계된 것이다.

```
기존:   S + U = YES  (읽기 중에 update 예약 허용)
        U + S = NO   (update 예약 중에 새 읽기 차단)

신규:   U + WS = YES (update 예약 중에 기존 FK 검사는 공존 허용)
        WS + U = NO  (FK 검사 중에 새 update 예약 차단)
```

U_LOCK이 FK 검사(WS_LOCK)를 보유 중인 행에 나중에 요청되는 경우:

```
TX1: FK check → WS_LOCK(parent.row1) 보유
TX2: SELECT parent FOR UPDATE → U_LOCK(parent.row1) 요청
     → WS+U=NO 규칙으로 차단

TX2가 U를 X로 업그레이드하면 X+WS=NO이므로 여전히 차단.
TX1의 FK 검사가 끝나면 WS 해제 → TX2 진행.
```

이 규칙이 실제로 작동하는 방향은 주로 **"WS 보유 중 U 요청 차단"** 이다.
"U 보유 중 WS 요청"은 같은 TX 내부에서 발생할 수 있으나 (`lock_conv[WS][U] = U`),
다른 TX 간에서는 FK 검사 대상 행에 SELECT FOR UPDATE를 하는 드문 패턴에서만 나타난다.

---

## CUBRID 서버 로그 에러 코드

```
CODE = -1021: A deadlock cycle is detected.
CODE = -72 (ER_LK_UNILATERALLY_ABORTED): Transaction aborted as deadlock victim.
CODE = -1124: Query execution error (ERROR_CODE = -72)
```

## statdump와의 관계

| 지표 | 값 (200 terminals) | 설명 |
|------|-------------------|------|
| 서버 로그 deadlock cycle | 9,079 | 실제 deadlock 발생 수 |
| 리포트 New-Order failed | 7,692 | 측정 구간 내 실패 수 |
| Num_tran_rollbacks | 78 | deadlock abort를 포함하지 않음 |
| Num_object_locks_waits | 1,008 | lock 대기 진입만, timeout/deadlock 무관 |

**statdump에는 deadlock abort 전용 카운터가 없다.** 서버 로그 또는 리포트의 failed 수를 참조해야 한다.

## 결론

| | CUBRID (수정 전) | CUBRID (수정 후, CBRD-26664) | PG |
|---|---|---|---|
| FK 검사 lock | S_LOCK | WS_LOCK | FOR KEY SHARE |
| UPDATE lock (non-key) | X_LOCK | WX_LOCK | FOR NO KEY UPDATE |
| FK lock vs UPDATE lock | S vs X = **비호환** | WS vs WX = **호환** | KEY SHARE vs NO KEY UPDATE = **호환** |
| TPC-C 200 terminals | deadlock **9,079건** | deadlock **0건** (예상) | deadlock **0건** |
| 근본 원인/해결 | lock 세분화 부족 (2단계) | WS/WX 2단계 추가 (4단계) | 4단계 lock 기본 제공 |

PG의 FOR KEY SHARE는 PostgreSQL 9.3 (2013)에서 도입되었다.
도입 목적이 정확히 이 문제 — FK 검사와 일반 UPDATE 간 불필요한 lock 충돌 제거.
CBRD-26664는 동일한 설계를 CUBRID에 적용한다.

## 구현 요약 (CBRD-26664)

- `lock_table.h`: `WS_LOCK = 12`, `WX_LOCK = 13` 추가
- `lock_table.c`: 호환성/변환 행렬에 WS/WX 행·열 추가 (WS+WX = 호환)
- `storage_common.h`: `S_SELECT_WITH_KEY_SHARE_LOCK = 2` 추가 (직렬화 안전을 위해 명시적 값)
- `btree.c`: FK 검사 시 `S_SELECT_WITH_KEY_SHARE_LOCK` → `WS_LOCK` 결정
- `locator_sr.c`: `locator_decide_update_lock()` — 비키 UPDATE → `WX_LOCK`
- `lock_manager.c`: `WS_LOCK` 이하 lock에 대한 분기 조건 반영
