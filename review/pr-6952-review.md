# PR-6952 해시 집계 중복 표현식 평가 제거 리뷰

**날짜:** 2026-04-14  
**브랜치:** pr-6952 (베이스: upstream/develop)  
**JIRA:** [CBRD-26641](http://jira.cubrid.org/browse/CBRD-26641) — Remove redundant expression evaluation in hash aggregation  
**규모:** 2개 파일 변경 (+69, -8)

---

## 목차

1. [기능 개요](#1-기능-개요)
2. [기존 동작과 변경 내용](#2-기존-동작과-변경-내용)
3. [코드 상세 분석](#3-코드-상세-분석)
4. [리뷰 포인트](#4-리뷰-포인트)
5. [종합 평가](#5-종합-평가)

---

## 1. 기능 개요

이 PR은 **해시 기반 GROUP BY 집계(hash aggregation)** 처리 시 발생하는 **중복 표현식 평가를 제거**하는 성능 최적화입니다.

### 문제 상황

해시 집계 처리 흐름에서, `qexec_generate_tuple_descriptor()`가 `xasl->outptr_list`에 대해 모든 컬럼/표현식을 이미 한 번 평가하여 그 결과를 `tpl_descr.f_valp`에 저장합니다. 그런데 이후 단계에서:

1. **해시 키 생성** (`qexec_build_agg_hkey()`): `g_hk_scan_regu_list`에 대해 `fetch_peek_dbval()`을 다시 호출
2. **집계 함수 평가** (`fetch_val_list()`): `g_scan_regu_list`에 대해 `fetch_peek_dbval()`을 다시 호출

이 두 곳에서 **이미 평가된 동일한 표현식을 중복 계산**하는 비효율이 발생합니다.

### 해결 방법

`outptr_list`의 각 `REGU_VARIABLE`의 `vfetch_to`를 `g_val_list`의 `DB_VALUE`에 연결(link)하여, `f_valp`에 저장된 결과를 `pr_share_value()`로 직접 전달합니다. 이를 통해 `fetch_peek_dbval()` 재호출 없이 이미 계산된 값을 재사용합니다.

### 성능 개선 효과

JIRA 티켓의 벤치마크 (1,000만 행, GROUP BY 2개 키 + 4개 집계 표현식):

| 항목 | 개선 전 | 개선 후 | 개선율 |
|------|---------|---------|--------|
| GROUPBY 시간 (ms) | 17,973 | 6,261 | **~65% 감소** |
| SELECT 전체 시간 (ms) | 36,013 | 24,345 | **~32% 감소** |

표현식이 복잡할수록(산술 연산, 함수 호출 등) 개선 효과가 커집니다.

---

## 2. 기존 동작과 변경 내용

### 2.1 기존 해시 집계 흐름

```
qexec_execute_mainblock()
  └─ 각 튜플에 대해:
       1. qexec_generate_tuple_descriptor()
          └─ outptr_list 의 모든 표현식 평가 → f_valp[i]에 결과 저장
       2. qexec_hash_gby_agg_tuple()
          ├─ qexec_build_agg_hkey()
          │   └─ g_hk_scan_regu_list 의 각 노드에 대해 fetch_peek_dbval() ← [중복!]
          └─ (기존 그룹 발견 시)
              ├─ fetch_val_list(g_scan_regu_list, ..., tplrec->tpl, true) ← [중복!]
              └─ qdata_evaluate_aggregate_list()
```

**문제:** 단계 2에서 `fetch_peek_dbval()`이 단계 1에서 이미 평가한 동일한 표현식(예: `c1 * c2`, `c3 * (1 - c5)`)을 다시 실행합니다.

### 2.2 변경 후 흐름

```
qexec_execute_mainblock()
  └─ 각 튜플에 대해:
       1. qexec_generate_tuple_descriptor()
          └─ outptr_list 의 모든 표현식 평가 → f_valp[i]에 결과 저장
       2. qexec_hash_gby_agg_tuple()
          ├─ [NEW] outptr_list의 vfetch_to에 f_valp 값을 pr_share_value()로 복사
          ├─ qexec_build_agg_hkey()
          │   └─ tpl == NULL이면 vfetch_to에서 직접 값을 가져옴 (fetch_peek_dbval 생략)
          └─ (기존 그룹 발견 시)
              ├─ [NEW] HIDDEN_COLUMN만 fetch_peek_dbval() 수행, 나머지는 생략
              └─ qdata_evaluate_aggregate_list()
```

### 2.3 변경 파일 요약

| 파일 | 변경 내용 |
|------|-----------|
| `src/parser/xasl_generation.c` | XASL 생성 시 `outptr_list`와 `regu_constant_list`의 `vfetch_to`를 `g_val_list`에 연결 |
| `src/query/query_executor.c` | 해시 집계 실행 시 `f_valp` 값을 재사용하도록 변경 |

---

## 3. 코드 상세 분석

### 3.1 XASL 생성 단계: vfetch_to 연결 (`xasl_generation.c`)

#### 변경 1: `pt_to_buildlist_proc()` (16321~16333행)

```c
if (buildlist->g_hash_eligible)
  {
    int i = 0;
    REGU_VARIABLE_LIST reg_var_p_out;
    for (reg_var_p_out = xasl->outptr_list->valptrp; reg_var_p_out; reg_var_p_out = reg_var_p_out->next)
      {
        if (attr_offsets && reg_var_p_out)
          {
            reg_var_p_out->value.vfetch_to = pt_index_value (buildlist->g_val_list, attr_offsets[i]);
          }
        i++;
      }
  }
```

**동작:** 해시 집계 가능(`g_hash_eligible`)한 경우, `outptr_list`의 각 `REGU_VARIABLE`의 `vfetch_to`를 `g_val_list`의 해당 `DB_VALUE`로 연결합니다. `attr_offsets`는 `pt_make_identity_offsets()`로 생성된 항등 매핑입니다.

**핵심:** 이 연결을 통해, 실행 시 `outptr_list`의 `vfetch_to`에 값을 쓰면 `g_val_list`에도 반영됩니다. `g_hk_scan_regu_list`와 `g_scan_regu_list`도 같은 `g_val_list`를 참조하므로, 간접적으로 모든 리스트가 동일한 값을 공유하게 됩니다.

#### 변경 2: `pt_aggregate_info_update_value_and_reguvar_lists()` (27353~27361행)

```c
for (REGU_VARIABLE_LIST ptr = regu_constant_list; ptr != NULL; ptr = ptr->next, regu_constant_list_size++)
  {
    ptr->value.vfetch_to = pt_index_value (value_list, regu_constant_list_size);
  }

pt_merge_regu_var_lists (&info->out_list->valptrp, regu_constant_list);
```

**동작:** 집계 함수의 인자로 사용되는 상수 표현식(`regu_constant_list`)에 대해서도 `vfetch_to`를 연결합니다.

**변경 포인트:** 기존에는 `pt_merge_regu_var_lists()`를 먼저 호출한 후 `regu_constant_list_size`만 카운트했으나, 변경 후에는 머지 **전에** `vfetch_to` 연결을 수행합니다. 이는 머지 후에는 `regu_constant_list`가 `out_list->valptrp`의 일부가 되어 순회 기준이 바뀌기 때문입니다.

### 3.2 실행 단계: 값 재사용 (`query_executor.c`)

#### 변경 3: `qexec_hash_gby_agg_tuple()` — f_valp → vfetch_to 전달 (4562~4570행)

```c
REGU_VARIABLE_LIST regu_var_p = xasl->outptr_list->valptrp;
for (int i = 0; i < xasl->outptr_list->valptr_cnt && regu_var_p; i++, regu_var_p = regu_var_p->next)
  {
    if (REGU_VARIABLE_IS_FLAGED (&regu_var_p->value, REGU_VARIABLE_HIDDEN_COLUMN))
      {
        continue;
      }
    pr_share_value (tpldesc->f_valp[i], regu_var_p->value.vfetch_to);
  }
```

**동작:** `qexec_generate_tuple_descriptor()`에서 이미 평가된 `f_valp[i]` 값을 `outptr_list`의 `vfetch_to`에 `pr_share_value()`로 공유합니다.

**HIDDEN_COLUMN 스킵 이유:** `REGU_VARIABLE_HIDDEN_COLUMN` 플래그가 설정된 컬럼은 `f_valp`에 포함되지 않습니다 (리스트 파일에 기록되지 않는 컬럼). HIDDEN_COLUMN을 `continue`로 스킵하지만, `i++`는 for 루프 증분에서 계속 실행됩니다. 이로 인해 `f_valp` compact 배열과 인덱스가 어긋날 가능성이 있으나, 실제로는 문제가 되지 않습니다. 자세한 분석은 [리뷰 포인트 R1](#r1-info-hidden_column-스킵-시-f_valp-인덱스-정합성--문제-없음)을 참고하세요.

#### 변경 4: `qexec_hash_gby_agg_tuple()` — fetch_val_list 대체 (4656~4679행)

```c
for (regu_var_p = proc->g_scan_regu_list; regu_var_p != NULL; regu_var_p = regu_var_p->next)
  {
    if (regu_var_p->value.vfetch_to && pr_is_set_type (DB_VALUE_DOMAIN_TYPE (regu_var_p->value.vfetch_to)))
      {
        pr_clear_value (regu_var_p->value.vfetch_to);
      }

    if (DB_NEED_CLEAR (regu_var_p->value.vfetch_to))
      {
        pr_clear_value (regu_var_p->value.vfetch_to);
      }

    if (REGU_VARIABLE_IS_FLAGED (&regu_var_p->value, REGU_VARIABLE_HIDDEN_COLUMN))
      {
        rc = fetch_peek_dbval (thread_p, &regu_var_p->value, &xasl_state->vd, NULL, NULL, tplrec->tpl, &tmp);
        if (rc != NO_ERROR)
          {
            pr_clear_value (regu_var_p->value.vfetch_to);
            return ER_FAILED;
          }

        pr_share_value (tmp, regu_var_p->value.vfetch_to);
      }
  }
```

**동작:** 기존의 `fetch_val_list(thread_p, proc->g_scan_regu_list, ..., tplrec->tpl, true)` 호출을 대체합니다.

- **HIDDEN_COLUMN이 아닌 컬럼:** `vfetch_to`에 이미 변경 3에서 값이 전달되어 있으므로, 추가 fetch 없이 이미 연결된 값을 사용합니다. 단, `set` 타입이거나 `DB_NEED_CLEAR`인 경우 기존 값을 정리합니다.
- **HIDDEN_COLUMN:** `f_valp`에 포함되지 않아 변경 3에서 값이 전달되지 않았으므로, `fetch_peek_dbval()`로 직접 가져옵니다.

**기존 `fetch_val_list()`와의 비교:** 기존 함수(`fetch.c:4755`)의 `peek == true` 경로와 거의 동일한 패턴입니다. 차이점은 HIDDEN_COLUMN만 선택적으로 fetch한다는 것입니다.

#### 변경 5: `qexec_build_agg_hkey()` — vfetch_to 직접 사용 (27290~27304행)

```c
if (tpl == NULL && !DB_IS_NULL (regu_list->value.vfetch_to))
  {
    /* tpl is NULL when called during the processing phase */
    key->values[key->val_count] = regu_list->value.vfetch_to;
  }
else
  {
    rc = fetch_peek_dbval (thread_p, &regu_list->value, &xasl_state->vd, NULL, NULL, tpl,
                           &key->values[key->val_count]);
    if (rc != NO_ERROR)
      {
        return rc;
      }
  }
```

**동작:** 해시 키 생성 시:

- `tpl == NULL`이고 `vfetch_to`가 NULL이 아닌 경우: 이미 `vfetch_to`에 값이 있으므로 직접 사용
- 그 외: 기존대로 `fetch_peek_dbval()` 호출

**`tpl == NULL` 조건의 의미:** `qexec_hash_gby_agg_tuple()`에서 `qexec_build_agg_hkey()`를 호출할 때 `tpl`에 `NULL`을 전달합니다 (4573행). 이는 초기 스캔 단계(processing phase)를 의미하며, 이 시점에서는 `vfetch_to`에 값이 이미 전달된 상태입니다. 반면, 정렬 기반 집계(sort-based fallback) 시에는 `tpl`이 non-NULL이므로 기존 경로를 탑니다.

---

## 4. 리뷰 포인트

### R1. [Info] HIDDEN_COLUMN 스킵 시 f_valp 인덱스 정합성 — 문제 없음

**위치:** `query_executor.c:4562~4570`

```c
for (int i = 0; i < xasl->outptr_list->valptr_cnt && regu_var_p; i++, regu_var_p = regu_var_p->next)
  {
    if (REGU_VARIABLE_IS_FLAGED (&regu_var_p->value, REGU_VARIABLE_HIDDEN_COLUMN))
      {
        continue;
      }
    pr_share_value (tpldesc->f_valp[i], regu_var_p->value.vfetch_to);
  }
```

`HIDDEN_COLUMN`을 `continue`로 스킵하지만, for 루프의 증분식 `i++`는 그대로 실행됩니다. `f_valp`는 `qdata_generate_tuple_desc_for_valptr_list()` (`query_opfunc.c:639`)에서 HIDDEN_COLUMN을 건너뛴 compact 배열로 생성됩니다:

```c
// query_opfunc.c:639~676
for (i = 0; i < valptr_list_p->valptr_cnt; i++, reg_var_p = reg_var_p->next)
  {
    if (unlikely (flags & REGU_VARIABLE_HIDDEN_COLUMN))
      {
        continue;         // f_cnt 증가하지 않음
      }
    tuple_desc_p->f_valp[tuple_desc_p->f_cnt] = ...;
    tuple_desc_p->f_cnt += 1;   // HIDDEN 아닌 것만 카운트
  }
```

따라서 만약 HIDDEN_COLUMN이 `outptr_list` 중간에 존재한다면, `i`와 `f_valp` 인덱스가 어긋나는 문제가 발생할 수 있습니다. **그러나 해시 집계에서는 이 상황이 발생하지 않습니다.**

**근거:**

1. **`outptr_list` 구성:** `group_out_list`(GROUP BY 키, non-HIDDEN)로 초기 생성 후, `regu_constant_list`(집계 인자, non-HIDDEN)가 `pt_merge_regu_var_lists()`로 **끝에 append**

2. **HIDDEN을 생성하는 유일한 경로:** `cume_dist`, `percent_rank` 등 특수 집계 함수 (`xasl_generation.c:27192`)

3. **해시 집계 적격성 검사** (`pt_is_hash_agg_eligible()`, 3880~3887행)에서 이 함수들이 포함되면 **해시 집계 비적격** (`eligible = 0`)으로 판정:

```c
if (tree->info.function.function_type == PT_GROUP_CONCAT
    || tree->info.function.function_type == PT_MEDIAN
    || tree->info.function.function_type == PT_CUME_DIST
    || tree->info.function.function_type == PT_PERCENT_RANK
    || tree->info.function.all_or_distinct == PT_DISTINCT
    || tree->info.function.function_type == PT_PERCENTILE_CONT
    || tree->info.function.function_type == PT_PERCENTILE_DISC)
  {
    *eligible = 0;
    *continue_walk = PT_STOP_WALK;
  }
```

**결론:** 해시 집계가 활성화된 쿼리에서 `outptr_list`에 HIDDEN_COLUMN이 포함되는 경우는 없습니다. PR 코드의 HIDDEN_COLUMN 체크는 순수 방어 코드이며, `i`와 `f_valp` 인덱스가 어긋나는 상황은 발생하지 않습니다.

> **참고:** 향후 해시 집계 적격 함수가 확장되어 HIDDEN_COLUMN이 `outptr_list` 중간에 포함되는 경우가 생기면, 별도 인덱스(`f_idx`)를 사용하도록 수정이 필요합니다.

### R2. [Low] attr_offsets NULL 체크 위치

**위치:** `xasl_generation.c:16327`

```c
if (attr_offsets && reg_var_p_out)
```

`reg_var_p_out`은 이미 for 루프의 조건에서 NULL이 아님이 보장됩니다. 따라서 `reg_var_p_out` 체크는 불필요합니다. `attr_offsets` 체크만으로 충분합니다. 또한 `attr_offsets`가 NULL이면 루프 전체가 무의미하므로, 루프 밖에서 체크하는 것이 더 명확합니다:

```c
if (buildlist->g_hash_eligible && attr_offsets)
  {
    int i = 0;
    REGU_VARIABLE_LIST reg_var_p_out;
    for (reg_var_p_out = xasl->outptr_list->valptrp; reg_var_p_out; reg_var_p_out = reg_var_p_out->next)
      {
        reg_var_p_out->value.vfetch_to = pt_index_value (buildlist->g_val_list, attr_offsets[i]);
        i++;
      }
  }
```

### R3. [Info] g_scan_regu_list 루프에서 non-HIDDEN 컬럼의 pr_clear_value — 문제 없음

**위치:** `query_executor.c:4656~4679`

```c
for (regu_var_p = proc->g_scan_regu_list; regu_var_p != NULL; regu_var_p = regu_var_p->next)
  {
    // set 타입이면 clear
    if (regu_var_p->value.vfetch_to && pr_is_set_type (...))
      pr_clear_value (regu_var_p->value.vfetch_to);

    // DB_NEED_CLEAR이면 clear
    if (DB_NEED_CLEAR (regu_var_p->value.vfetch_to))
      pr_clear_value (regu_var_p->value.vfetch_to);

    // HIDDEN_COLUMN만 fetch
    if (REGU_VARIABLE_IS_FLAGED (&regu_var_p->value, REGU_VARIABLE_HIDDEN_COLUMN))
      { ... fetch_peek_dbval + pr_share_value ... }
  }
```

non-HIDDEN 컬럼에 대해 `pr_clear_value()`가 호출될 수 있으나, 실제로 값 파괴는 발생하지 않습니다:

- **`pr_is_set_type` 체크:** set 타입이 `outptr_list`에 포함되면 `qdata_generate_tuple_desc_for_valptr_list()`가 `QPROC_TPLDESCR_RETRY_SET_TYPE`을 반환하여, 해시 집계 경로(`qexec_hash_gby_agg_tuple`) 자체가 호출되지 않습니다 (`query_opfunc.c:659~662`). 따라서 이 체크에 걸리는 일이 없습니다.
- **`DB_NEED_CLEAR` 체크:** 변경 3에서 `pr_share_value()`가 `need_clear = false`로 설정하므로, 이 체크를 통과합니다.

**결론:** 두 방어 코드 모두 해시 집계에서는 실질적으로 트리거되지 않으며, 값 파괴 없이 안전합니다.

### R4. [Low] DB_IS_NULL 체크로 인한 NULL 키 최적화 미적용

**위치:** `query_executor.c:27290`

```c
if (tpl == NULL && !DB_IS_NULL (regu_list->value.vfetch_to))
```

`tpl == NULL`이고 `vfetch_to`가 DB_NULL인 경우(GROUP BY 키가 NULL인 행), else 브랜치로 가서 `fetch_peek_dbval()`을 호출합니다.

**기능 오류 여부:** `g_hk_scan_regu_list`는 `TYPE_CONSTANT` 타입의 regu variable로 생성되며, `fetch_peek_dbval()`은 `TYPE_CONSTANT`에 대해 `tpl`을 사용하지 않고 `regu->value.dbvalptr`에서 직접 값을 반환합니다. 따라서 `tpl = NULL`이어도 **정상 동작합니다. 버그가 아닙니다.**

**성능 관점:** GROUP BY 키가 NULL인 행이 있을 때마다 `fetch_peek_dbval()`이 호출되어, 이미 `vfetch_to`에 공유된 NULL 값을 불필요하게 다시 가져옵니다. `!DB_IS_NULL` 대신 `vfetch_to != NULL` (포인터 체크)로 변경하면 NULL 키도 최적화 경로를 탈 수 있으나, 기능에는 영향 없으므로 선택적 개선사항입니다.

### R5. [Info] pt_merge_regu_var_lists 호출 순서 변경

**위치:** `xasl_generation.c:27349~27361`

기존:
```c
pt_merge_regu_var_lists (&info->out_list->valptrp, regu_constant_list);
// 그 후 size 카운트만 수행
```

변경 후:
```c
// 먼저 vfetch_to 연결
for (ptr = regu_constant_list; ptr != NULL; ptr = ptr->next, regu_constant_list_size++)
  {
    ptr->value.vfetch_to = pt_index_value (value_list, regu_constant_list_size);
  }
// 그 후 머지
pt_merge_regu_var_lists (&info->out_list->valptrp, regu_constant_list);
```

이 순서 변경은 논리적으로 올바릅니다. `pt_index_value()`는 `value_list`에서 0부터 인덱싱하므로, 머지 전에 호출해야 독립적인 `regu_constant_list`의 인덱스와 정합합니다. 머지 후에는 리스트가 합쳐져서 인덱스 기준이 달라집니다.

---

## 5. 종합 평가

### 아키텍처 평가

이 PR은 해시 집계의 핵심 최적화를 수행합니다. 접근 방식은 적절합니다:

1. **XASL 생성 시점**에 `vfetch_to` 포인터를 연결하여 값 공유 경로를 설정
2. **실행 시점**에 이미 평가된 `f_valp` 결과를 `vfetch_to`를 통해 전달하여 중복 `fetch_peek_dbval()` 제거

이는 기존 `fetch_val_list()`의 동작을 깨뜨리지 않으면서, 해시 집계 경로에서만 선택적으로 최적화를 적용하는 안전한 접근입니다.

### 리스크 분석

| 항목 | 리스크 | 설명 |
|------|--------|------|
| HIDDEN_COLUMN 인덱스 (R1) | **None** | 해시 집계에서 HIDDEN_COLUMN이 `outptr_list`에 포함 불가. 방어 코드일 뿐 실제 트리거 안됨 |
| 코드 스타일 (R2) | **Low** | 불필요한 NULL 체크, 가독성 개선 가능 |
| set 타입 값 처리 (R3) | **None** | set 타입은 `RETRY_SET_TYPE`으로 분기, 해시 집계 경로 미진입 |
| NULL 키 성능 (R4) | **Low** | NULL 키에서 불필요한 `fetch_peek_dbval` 재호출. 기능 오류 아님, 성능만 약간 손해 |
| 머지 순서 변경 (R5) | **None** | 논리적으로 올바른 변경 |

**버그 없음:** 모든 리뷰 포인트를 검증한 결과 기능 결함은 발견되지 않았습니다.

### 테스트 관점

JIRA에서 제시된 벤치마크 외에 다음 케이스에 대한 테스트 확인이 권장됩니다:

- [ ] GROUP BY 키에 NULL 값이 포함된 경우
- [ ] GROUP BY 키나 집계 인자에 복합 표현식(산술, 함수 호출)이 포함된 경우
- [ ] SELECT 리스트에 집계 대상이 아닌 컬럼이 포함된 경우
- [ ] 해시 집계에서 정렬 기반 집계로 폴백(fallback)하는 경우 (메모리 초과 시)
- [ ] 해시 집계가 비활성화된 경우 (`g_hash_eligible == false`) — 기존 경로 정상 동작 확인

### 선택적 개선 제안

| 항목 | 제안 | 이유 |
|------|------|------|
| R1 방어 코드 | `f_idx` 별도 인덱스 분리 | 향후 해시 집계 적격 함수 확장 시 잠재 리스크 방지 |
| R2 NULL 체크 | `attr_offsets` 체크를 루프 밖으로 이동 | 가독성 개선 |
| R4 NULL 키 | `!DB_IS_NULL(vfetch_to)` → `vfetch_to != NULL` | NULL 키에서도 최적화 경로 적용 |

### 결론

**65% 성능 개선**(GROUPBY 시간 17,973ms → 6,261ms)이라는 벤치마크 결과가 인상적이며, 변경 범위가 2개 파일 77줄로 작고 **버그가 없는 것으로 확인**되었습니다. 머지 가능합니다.
