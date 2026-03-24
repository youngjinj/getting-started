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
      c. 순서에 맞지 않는 페이지들을 unfix (해제)
      d. 정렬된 순서대로 모든 페이지를 다시 fix
4. 성공 시 watcher->pgptr에 페이지 포인터 설정
```

**핵심 포인트**: 이 모든 과정은 `pgbuf_ordered_fix` 함수 내부에서 일어난다.
conditional fix는 "순서를 무시하는 것"이 아니라, 순서 위반 없이 바로 잡을 수 있는지를
낙관적으로 먼저 시도하는 것이다. 실패하면 비로소 unfix → 정렬 → refix의 비용을 지불한다.

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

## 관련 소스 파일

- `src/storage/page_buffer.h` — 선언, 매크로, 자료구조
- `src/storage/page_buffer.c` — 구현 (11959~12779 라인)
- `src/storage/heap_file.c` — 주요 사용처
