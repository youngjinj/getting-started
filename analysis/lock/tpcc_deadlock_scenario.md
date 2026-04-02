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

| | CUBRID (S_LOCK) | PG (FOR KEY SHARE) |
|---|---|---|
| FK 검사 lock | S_LOCK | FOR KEY SHARE |
| UPDATE lock (non-key) | X_LOCK | FOR NO KEY UPDATE |
| FK lock vs UPDATE lock | S vs X = **비호환** | KEY SHARE vs NO KEY UPDATE = **호환** |
| TPC-C 200 terminals | deadlock **9,079건** | deadlock **0건** |
| 근본 원인 | lock 세분화 부족 (2단계) | 4단계 lock으로 불필요한 충돌 회피 |

PG의 FOR KEY SHARE는 PostgreSQL 9.3 (2013)에서 도입되었다.
도입 목적이 정확히 이 문제 — FK 검사와 일반 UPDATE 간 불필요한 lock 충돌 제거.

## 개선 방안

1. **PG 방식 도입**: FK 검사 시 S_LOCK 대신 KEY SHARE 수준의 가벼운 lock 사용
   - `btree.c:24769`에서 FK 전용 lock 모드 추가 필요
2. **FK 제거**: 벤치마크 한정으로 FK를 제거하면 deadlock 해소 (공정성 이슈)
3. **lock_timeout 설정**: 무한 대기(-1) 대신 짧은 timeout 후 재시도 (근본 해결 아님)
