# FHS `fhs_find_bucket_vpid_with_hash` Use-After-Unfix 버그 분석

**작성일:** 2026-04-07
**관찰 브랜치:** CBRD-26666 (parallel hash join 작업 브랜치)
**작성/조사:** youngjinj
**심각도:** High — 간헐적 서버 크래시. 진단 가드 적용 후에는 `assert_release(false)` 로 잡히고, 가드가 없는 원래 코드에서는 `ER_IO_READ "Bad file descriptor"` 메시지로 노출됨.
**재현성:** 간헐적. parallel hash join 의 `HASH_METH_HASH_FILE` 경로 (메모리 부족으로 디스크 해시 테이블로 spill 된 케이스) 에서 `parallel(16)` 이상 + 큰 데이터셋 조합으로 재현됨.
**상태:** 근본 원인 확정, fix 검증 완료. **이 버그는 CBRD-26666 과 별도의 JIRA 이슈로 등록할 것** (parallel hash join 과 무관한 latent 버그가 노출된 것이므로).

---

## 1. 증상

`demodb` 의 `t1` 테이블 (5천만 행) 에 다음 self-join 을 실행:

```sql
select /*+ parallel(16) use_hash */ count(*) from t1 a, t1 b where a.c1 = b.c1;
```

간헐적으로 다음 에러 발생:

```
ERROR: An I/O error occurred while reading page <garbage> of volume "(null)".... Bad file descriptor
```

`cub_server` 에러 로그의 서버 측 스택 트레이스:

```
ERROR CODE = -13 (ER_IO_READ)
[12] pgbuf_claim_bcb_for_fix    src/storage/page_buffer.c:8246
[11] pgbuf_fix_release          src/storage/page_buffer.c:2189
[10] fhs_fix_old_page           src/query/query_hash_scan.c:1053
[09] fhs_search                 src/query/query_hash_scan.c:1567
[08] hjoin_probe_key             src/query/query_hash_join.c:3794  (HASH_METH_HASH_FILE 분기)
[07] hjoin_probe                 src/query/query_hash_join.c:3246
[06] parallel_query::hash_join::join_task::execute
                                  src/query/parallel/px_hash_join/px_hash_join_task_manager.cpp:738
[05] cubthread::worker_pool::core::worker::execute_current_task
[04] cubthread::worker_pool::core::worker::run
```

`pageid` 값은 매번 의미 없는 큰 수 (예: `876176696`, 이후 `99` 등) 였고, 볼륨 라벨은 항상 `"(null)"` 로 표시되었습니다.

---

## 2. 진단 패치 (root cause 포착용으로 추가)

다음 한 번의 재현으로 모든 정보를 잡기 위해 소스 트리에 세 가지 진단 코드를 추가했습니다. **이 진단 코드들은 실제 fix 와 분리되어 있으며, 향후 유사 버그 조기 탐지를 위해 유지할지 / 완화할지 / 제거할지는 팀 정책에 따라 결정합니다.**

### 2.1 `pgbuf_claim_bcb_for_fix` VPID sanity 가드

`src/storage/page_buffer.c:8246`. `fileio_read` 에 VPID 를 넘기기 직전, `vpid->volid` 가 실제로 마운트된 볼륨에 매핑되는지 검증. 매핑되지 않으면 호출자가 garbage 를 넘긴 것:

```c
int _vfd = fileio_get_volume_descriptor (vpid->volid);
if (unlikely (_vfd == NULL_VOLDES || vpid->volid == NULL_VOLID))
  {
    /* /tmp/cbrd26666/fhs_abort_dump.log 에 banner + trace ring + callstack 기록 */
    /* cub_server 에러 로그에도 er_print_callstack 으로 기록 */
    assert_release (false);
    abort ();
  }
```

`unlikely()` 로 happy path 비용은 분기 예측 1회 수준. `abort()` 는 첫 발생 시점에 코어 덤프를 확실히 잡기 위함.

### 2.2 FHS 동작 TLS 링버퍼

`src/query/query_hash_scan.c`. 64-entry 스레드 로컬 링버퍼를 추가해 `fhs_create / fhs_destroy / fhs_insert / fhs_search / fhs_search_next / fhs_fix_old_page` 호출마다 `(op, fhsid, vfid, vpid, hash_key, line)` 을 기록. 호출당 비용은 TLS write 몇 필드 수준. abort 경로에서 `/tmp/cbrd26666/fhs_abort_dump.log` 로 덤프.

### 2.3 재현용 빌드/설정

```
data_buffer_size=2G
parallelism=32

[standalone]
double_write_buffer_size=0
```

재현 전용 설정으로 fix 와 무관. 작은 data buffer 는 page buffer 의 victimization 빈도를 높여 이번 버그의 race window 를 직접적으로 넓힙니다.

---

## 3. 재현 방법론

서버: 진단 패치(Section 2)를 적용한 CUBRID 11.5 `RelWithDebInfo` 빌드.

세 개의 동시 루프, 각각 다음 쿼리를 반복 실행:

```sql
select /*+ parallel(16) use_hash */ count(*) from t1 a, t1 b where a.c1 = b.c1;
```

각 루프는 매 iteration 마다 `csql` 종료 코드, 서버 에러 로그 크기, dump 파일 크기를 점검하고 첫 크래시에서 종료.

단일 루프 110 iteration 까지는 재현되지 않았으나, 추가 루프 2개를 가세시키자 **3개 루프 모두 ~12초 이내에 동시에 크래시** — 루프 1의 iter 115, 루프 2와 3의 iter 1.

---

## 4. 재현 이벤트

```
[115 19:17:11 rc=1 err=0 dump=6103]
ERROR: Your transaction has been aborted by the system due to server failure or mode change.
```

dump 파일 `/tmp/cbrd26666/fhs_abort_dump.log` 의 핵심 부분:

```
==== FATAL pgbuf_claim_bcb_for_fix bad VPID ====
  volid=25401 pageid=99 vfd=-1 tran=1

==== FHS trace ring (ts=2026-04-07 19:17:35 tid=848237 head=22) ====
  ...
  [61] search       fhsid=0x7f3c20db6b70 vfid=(6|383296) vpid=(-1|-1) hkey=0x0b140ff1 line=1687
  [62] fix_old      fhsid=(nil)         vfid=(6|384320) vpid=(6|384321) hkey=0x00000000 line=1172
  [63] fix_old      fhsid=(nil)         vfid=(6|383296) vpid=(25401|99) hkey=0x00000000 line=1172
==== end FHS trace ring ====
```

스택 트레이스 (진단 패치로 라인 번호가 일부 시프트됐지만 사용자가 처음 보고한 원본 스택과 동일한 구조):

```
pgbuf_claim_bcb_for_fix bad vpid (volid=25401 pageid=99)
  ← pgbuf_claim_bcb_for_fix    page_buffer.c:8285  (assert_release 발동)
  ← pgbuf_fix_release          page_buffer.c:2189
  ← fhs_fix_old_page           query_hash_scan.c:1174
  ← fhs_search                 query_hash_scan.c:1700
  ← hjoin_probe_key            query_hash_join.c:3794
  ← hjoin_probe                query_hash_join.c:3246
  ← parallel_query::hash_join::join_task::execute
                               px_hash_join_task_manager.cpp:738
```

dump 로 확정된 사실:

| 사실 | 증거 |
|---|---|
| 단일 FHSID 컨텍스트 | 링버퍼 63 entry 전부 `fhsid=0x7f3c20db6b70` 동일 |
| 동일 bucket file / dir file | `bucket_file=(6\|383296)`, `dir_file=(6\|384320)` 고정 |
| 단일 directory root page | 모든 search 에서 `VPID(6\|384321)` 한 페이지를 fix |
| 정상 bucket VPID 의 volid 는 항상 6 | 다른 entry 들 모두 `vpid=(6, 380000~430000)` |
| 망가진 VPID 는 volid 25401 | slot [63] 에만 등장 |
| 망가진 VPID 의 pageid 는 99 | 작은 정수 — 완전 random garbage 가 아님 |
| 직전까지 12회 search 정상 | 같은 FHSID 로 정상 동작 |

---

## 5. 근본 원인

`fhs_find_bucket_vpid_with_hash` (`src/query/query_hash_scan.c:1886` upstream / 진단 패치 적용 시 2024 부근) 의 use-after-unfix 버그:

```c
static int
fhs_find_bucket_vpid_with_hash (THREAD_ENTRY * thread_p, FHSID * fhsid_p,
                                void *key_p, ...,
                                VPID * out_vpid_p, ...)
{
  ...
  dir_page_p = fhs_fix_nth_page (thread_p, &fhsid_p->ehid.vfid,
                                 dir_offset, bucket_latch);
  if (dir_page_p == NULL)
    {
      return ER_FAILED;
    }
  dir_record_p = (FHS_DIR_RECORD *) ((char *) dir_page_p + location);
  pgbuf_unfix_and_init (thread_p, dir_page_p);    /* (a) 먼저 unfix  */

  *out_vpid_p = dir_record_p->bucket_vpid;        /* (b) unfix 이후 read */

  return NO_ERROR;
}
```

`dir_record_p` 는 directory 페이지 버퍼 내부를 가리키는 raw 포인터입니다. (a) 에서 `pgbuf_unfix_and_init` 가 호출되면 BCB 가 더 이상 이 스레드의 핀에 의해 보호되지 않으므로 buffer manager 가 해당 BCB 를 victimize 할 수 있습니다. 다른 worker (또는 flush daemon) 가 그 BCB 를 선택해 directory 페이지를 evict 하고 다른 페이지를 같은 메모리에 로드한 *후* 이 스레드가 (b) 에 도달하면, dereference 는 새로 로드된 페이지의 바이트를 읽게 됩니다.

읽힌 바이트가 마침 `VPID` 구조처럼 보였던 이유는 — directory 페이지 레이아웃에서 정확히 그 offset 에 `VPID` 가 저장되도록 설계되어 있었기 때문입니다. 하지만 그 바이트들은 **완전히 다른 페이지**에 속한 데이터입니다. 그래서 관찰된 garbage VPID 는 random 이 아니라 — **같은 BCB 에 새로 로드된 페이지의 실제 VPID 값**입니다.

race window 자체는 마이크로초 수준이므로, 다음 세 조건이 모두 강해야 재현됩니다:

- worker 수가 많을수록 → BCB 경합 심해짐
- data buffer 가 작을수록 → victimization 빈도 ↑
- working set 이 클수록 → `HASH_METH_HASH_FILE` 로 spill 빈도 ↑ (이 함수는 spill 경로에서만 호출됨)

이번 reproducer 는 위 세 조건을 모두 만족시킵니다.

### 왜 downstream 에서 크래시까지 가는가

garbage VPID 가 `fhs_search` 로 반환되고 → `fhs_fix_old_page` → `pgbuf_fix` → `pgbuf_claim_bcb_for_fix` → `fileio_get_volume_descriptor(vpid->volid)` 호출. `volid=25401` 은 마운트된 볼륨이 아니므로 `NULL_VOLDES (-1)` 반환. 이후 `fileio_read(thread_p, -1, ...)` 가 `pread(-1, ...)` 를 호출하고 `errno=EBADF` 로 실패. 에러 메시지에서 볼륨 라벨이 `"(null)"` 로 찍히는 이유는 `fileio_get_volume_label_by_fd(-1, PEEK)` 가 fd=-1 에 대해 라벨을 resolve 할 수 없기 때문입니다.

---

## 6. Fix

두 줄 변경 — bucket VPID 를 **페이지가 fix 된 동안** 읽고, 그 다음에 unfix.

```diff
-  dir_record_p = (FHS_DIR_RECORD *) ((char *) dir_page_p + location);
-  pgbuf_unfix_and_init (thread_p, dir_page_p);
-
-  *out_vpid_p = dir_record_p->bucket_vpid;
+  dir_record_p = (FHS_DIR_RECORD *) ((char *) dir_page_p + location);
+  *out_vpid_p = dir_record_p->bucket_vpid;
+  pgbuf_unfix_and_init (thread_p, dir_page_p);
```

코멘트 포함된 전체 패치는 [`fix-fhs-find-bucket-vpid-use-after-unfix.patch`](./fix-fhs-find-bucket-vpid-use-after-unfix.patch) 참조.

### 이 fix 가 완전한 이유

- 버그는 이 함수 한 곳의 use-after-unfix 만의 문제. 호출자 (`fhs_search`, `pgbuf_fix` 등) 는 정상적이며 입력으로 받은 valid VPID 를 그대로 사용함.
- `query_hash_scan.c` 의 다른 directory 페이지 접근 (`fhs_connect_bucket`, `fhs_expand_directory`) 은 write 가 끝날 때까지 latch 를 정상적으로 유지함. 코드 검사로 확인.
- 이 fix 는 함수의 의미를 전혀 바꾸지 않음 — 단지 read 와 unfix 의 순서만 교체.

---

## 7. 검증

| | Before fix | After fix |
|---|---|---|
| 병렬도 | parallel(16), 3개 동시 csql 세션 | (동일) |
| 첫 재현까지 시간 | 3번째 루프 가세 후 ~25분 | 재현되지 않음 |
| 완료 iteration | loop1=115 + loop2=1 + loop3=1 (모두 크래시) | loop1=36 + loop2=36 + loop3=36 = 108 |
| Wall clock | 19:17 크래시 | 20:16 ~ 21:44 (90분) 깨끗 |
| sanity 가드의 `assert_release(false)` | 발동 | 미발동 |
| 서버 로그의 `ER_IO_READ` | 발생 | 0건 |
| `cub_server` PID | 크래시 → 재시작 | 동일 PID 유지 (861748) |

이전과 동일한 병렬도 / 데이터 / workload 조건에서 3개 동시 루프로 108 iteration 동안 단 한 번도 발생하지 않음 — fix 확정.

---

## 8. 버그의 출처 (history)

`fhs_find_bucket_vpid_with_hash` 는 parallel hash join 기능보다 먼저 존재하던 함수입니다 (디스크에 spill 된 hash table 인 `HASH_METH_HASH_FILE` 모드의 extendible hashing 코드 경로에 위치). 따라서 use-after-unfix 는 줄곧 존재했지만, 단일 스레드 실행에서는 `pgbuf_unfix_and_init` 호출과 dereference 사이의 시간이 매우 짧아서 victimization 이 발생할 가능성이 사실상 없었습니다.

이 버그를 노출시킨 것은 parallel hash join (CBRD-26666) 입니다. 이유:

1. 여러 worker 스레드가 같은 쿼리 안에서 동시에 `pgbuf_fix` / `pgbuf_unfix` 를 두드리면서 BCB 의 churn rate 가 급격히 상승.
2. spill 된 hash join 의 probe phase 가 probe 된 key 마다 `fhs_find_bucket_vpid_with_hash` 를 호출 → 쿼리 한 번에 수백만 번 호출됨.
3. 충분한 probe 횟수 + 충분한 buffer pool pressure 조합에서 작은 race window 가 결국 hit 됨.

**이 버그는 parallel hash join 변경 때문에 생긴 것이 아닙니다.** 이미 존재하던 latent 버그가 parallel hash join 덕분에 실전에서 reach 가능해진 것입니다. 따라서 별도 티켓으로 등록하고, 동일한 형태의 `fhs_find_bucket_vpid_with_hash` 를 가진 maintenance branch 들에도 backport 해야 합니다.

---

## 9. 더 신뢰성 높은 재현 시나리오

현재 reproducer (3개 동시 csql, parallel(16), 5천만 행 self-join) 는 회귀 테스트 용도로 충분히 신뢰성이 있지만 worst case 에 ~25분 걸립니다. 향후 회귀 / 정적 분석을 위해 race window 를 넓히거나 결정적으로 만드는 방법들:

### 9.1 sleep 주입으로 window 강제 확장 (수 초 내 결정적 재현)

use-after-unfix 를 결정적으로 재현하는 가장 빠른 방법은 race window 를 인위적으로 넓히는 것. 버그 코드에 한 줄 추가:

```c
  pgbuf_unfix_and_init (thread_p, dir_page_p);
  usleep (50);     /* TEMPORARY: use-after-unfix race window 확장 */
  *out_vpid_p = dir_record_p->bucket_vpid;
```

이 한 줄로 단일 csql 세션의 reproducer 쿼리만으로도 수 초 내 재현됩니다. **회귀 테스트 작성용으로 강력 권장** — race 가 거의 결정적인 크래시로 변환되므로 fix 검증을 단 1회 실행으로 끝낼 수 있습니다.

### 9.2 page buffer 크기 축소

`data_buffer_size` 를 줄일수록 victimization 빈도 ↑ → window ↑. 2G → 128M 로 줄이면 보통 재현 시간이 절반 이하. 64M + `parallel(32)` 조합은 분 단위 안에 hit.

### 9.3 BCB 경합 극대화

race 가 성립하려면 *다른 스레드* 가 같은 BCB 를 가져가야 합니다. 무관한 `pgbuf_fix` 호출률을 올리면 도움:

- 다른 큰 테이블을 동시에 scan 하는 별도 csql 세션 (`select count(*) from t2;`)
- 동시에 `cubrid backupdb` 또는 큰 index scan 실행
- `data_buffer_size` 를 더 줄여서 작은 workload 만으로도 thrashing 유도

### 9.4 ThreadSanitizer (TSan)

CUBRID 를 `-fsanitize=thread` 로 빌드해서 reproducer 를 한 번만 실행하면 됨. TSan 은 use-after-unfix 를 reader (이 함수) 와 writer (BCB 에 새 페이지 내용을 쓰는 page buffer victimizer) 사이의 data race 로 보고합니다 — **버그가 실제로 크래시로 manifest 될 필요 없이** race condition 자체가 진단입니다.

주의:
- TSan 은 clean rebuild 와 ~5x slowdown 필요
- CUBRID 의 lock-free / atomic 코드에서 false positive 가 나올 수 있어 suppression 파일 필요할 수 있음
- TSan 이 race detection 의 gold standard 이지만 현재 프로젝트 CI 에는 포함되어 있지 않음

### 9.5 AddressSanitizer (ASan) — 부적합

ASan 은 이 버그를 직접 보고하지 못합니다. unfix 후의 read 는 기술적으로 *유효한 (live) BCB 메모리* 를 읽는 것이라 — heap overflow 도 아니고 malloc 레벨의 use-after-free 도 아닙니다. 문제의 "use" 는 *논리적으로 stale 한 상태* (이 BCB 가 페이지 X 를 들고 있어야 하는데 페이지 Y 를 들고 있음) 를 사용하는 것이지, 해제된 메모리를 사용하는 것이 아닙니다. 따라서 ASan 은 **이 케이스에 적합한 도구가 아닙니다**. 새 JIRA 티켓에서 헛수고 방지를 위해 명시할 것.

### 9.6 단일 프로세스 합성 reproducer (단위 테스트용)

전체 CUBRID 서버 없이 결정적으로 재현하는 단위 테스트:

1. 작은 directory (1 페이지) 를 가진 작은 FHSID 생성
2. 여러 bucket 이 채워질 만큼 key insert
3. 두 스레드 spawn:
   - Thread A: `fhs_find_bucket_vpid_with_hash` 를 tight loop 로 호출
   - Thread B: directory 페이지와 같은 BCB hash bucket 에 속하는 페이지들을 fix / dirty / unfix tight loop 로 호출 → victim 압력 강제
4. (9.1) 처럼 unfix 와 dereference 사이에 `usleep(10)` 주입
5. 반환된 VPID 가 예상값과 일치하는지 assert

(9.1) 의 진단 shim 을 제거한 후 이 종류의 단위 테스트를 `unit_tests/query_hash_scan/` 에 추가할 수 있습니다.

### 9.7 새 JIRA 티켓 권장 reproducer

새 JIRA 티켓을 위한 가장 단순하고 확실한 reproducer:

> **Setup**
> - `fhs_find_bucket_vpid_with_hash` 의 `pgbuf_unfix_and_init` 와 dereference 사이에 `usleep(50)` 주입한 빌드
> - `data_buffer_size=128M`, `parallelism=16`
>
> **실행**
> ```sql
> select /*+ parallel(16) use_hash */ count(*) from t1 a, t1 b where a.c1 = b.c1;
> ```
>
> **예상 동작 (버그 빌드):** 수 초 내 크래시
> **fix 적용 후:** 정상 종료

수 시간짜리 stress run 을 수 초짜리 결정적 테스트로 변환합니다.

---

## 10. 디렉터리 파일

- [`CBRD-26666_fhs_use_after_unfix.md`](./CBRD-26666_fhs_use_after_unfix.md) — 본 보고서
- [`fix-fhs-find-bucket-vpid-use-after-unfix.patch`](./fix-fhs-find-bucket-vpid-use-after-unfix.patch) — 최소 fix unified diff

---

## 11. 새 JIRA 티켓에서 결정해야 할 사항

1. **`pgbuf_claim_bcb_for_fix` 의 진단 가드 (Section 2.1) 를 유지할 것인가?**
   비용은 저렴하지만 production 에서 `assert_release(false) + abort()` 는 너무 공격적. 권장: **가드는 유지하되 행동을 `er_set + return NULL` 로 완화**해서 호출자가 일반 page fix 실패로 처리하게 함. production 에서 강제 abort 는 거의 도움 안 되지만, 가드 자체는 향후 비슷한 류의 상위 레이어 VPID 오염을 잡는 데 가치 있음.

2. **FHS trace 링버퍼 (Section 2.2) 를 유지할 것인가?**
   FHS 호출당 TLS write 몇 필드 비용. 장점: 다음 사고 발생 시 코드 변경 없이 self-diagnose 가능. 단점: 코드량 증가, 디버깅 전용. 권장: **유지하되 *파일 dump 부분* 만 시스템 파라미터로 토글 가능하게 변경**해서 production 에서 `/tmp` 에 쓰지 않게.

3. **같은 모듈에 다른 use-after-unfix 사이트가 있는가?**
   `git grep -A2 pgbuf_unfix_and_init src/query/query_hash_scan.c` 로 audit 하는 것을 새 티켓의 일부로 포함할 것. 가장 의심스러운 곳 (`fhs_connect_bucket`, `fhs_expand_directory`) 은 점검했지만 전수 점검이 필요.

4. **Backport 범위.**
   `fhs_find_bucket_vpid_with_hash` 는 parallel hash join 기능이 없는 maintenance branch 에도 동일한 형태로 존재. 그쪽에서도 고병렬 workload 가 hash table 을 spill 시키면 기술적으로 도달 가능. 무조건 backport 권장.
