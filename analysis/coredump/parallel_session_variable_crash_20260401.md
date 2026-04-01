# Parallel Query + Session Variable Crash 분석

## 재현 쿼리

```sql
DROP TABLE IF EXISTS z2;
CREATE TABLE z2 (a INT, b INT);
INSERT INTO z2 VALUES (1, 1);

SELECT DISTINCT @v3:=max(b) OVER (PARTITION BY a+a ORDER BY b+b) FROM z2;
```

- `DISTINCT`에 의해 high water mark 기반 parallel query 실행이 트리거됨

## Call Stack

```
[27] abort
[26] __libc_message ← glibc heap corruption 감지
[25] unknown (libc) ← malloc/free 내부 무결성 체크
[24] unknown (libc)
[23] unknown (libcubrid) ← session_add_variable 내부 malloc/free 호출
[22] session_define_variable
[21] unknown (libcubrid) ← fetch_peek_dbval 내부 T_DEFINE_VARIABLE 분기
[20] fetch_peek_dbval
[19] qdata_generate_tuple_desc_for_valptr_list
[18] qexec_insert_tuple_into_list
[17] unknown (qexec 내부)
[16] unknown (qexec 내부)
[15] qexec_execute_mainblock
[14] parallel_query_execute::execute_job_internal  ← 병렬 worker
[13] parallel_query_execute::query_executor::run_jobs
[12] qexec_execute_mainblock
[11] qexec_execute_query
...
```

## 크래시 메커니즘

glibc의 heap metadata corruption 감지로 인한 `abort()`.

`session_add_variable()` (session.c:1119) 내부에서 `malloc()` 또는 `free()` 호출 시,
이미 손상된 heap metadata가 감지되어 abort가 발생함.

## 근본 원인

### 1. session_define_variable에 mutex 보호 부재

`SESSION_STATE`에는 `mutex`가 존재하지만 (session.c:118),
`session_define_variable()` (session.c:2040)은 **mutex를 잡지 않고** `session_add_variable()`을 호출함.

병렬 worker thread들이 동시에 같은 `SESSION_STATE`의 `session_variables` 링크드 리스트를 조작하면:
- **Double-free**: 동일 변수 update 시 기존 값을 두 thread가 동시에 free
- **Use-after-free**: 한쪽이 free한 노드를 다른 쪽이 참조
- **List corruption**: 동시 삽입으로 노드 유실 및 heap metadata 손상

### 2. Parallel Query Checker의 검사 누락 (진짜 원인)

`px_query_checker.cpp`의 `check_regu_var()` (line 164-167)에
`T_DEFINE_VARIABLE` / `T_EVALUATE_VARIABLE` 체크가 이미 존재함:

```cpp
// px_query_checker.cpp:164-167
if (regu_var->value.arithptr->opcode == T_DEFINE_VARIABLE
    || regu_var->value.arithptr->opcode == T_EVALUATE_VARIABLE)
  {
    m_is_parallel_executable = false;
  }
```

그러나 `check_xasl_node()` (line 292-320)에서 **BUILDLIST_PROC의 analytic function 관련 필드를 검사하지 않음**:

검사하는 필드:
- `outptr_list->valptrp`
- `spec_list` (where_key, where_pred, where_range)
- `during_join_pred`, `after_join_pred`, `if_pred`, `instnum_pred`
- `limit_offset`, `limit_row_count`, `ordbynum_pred`, `orderby_limit`

**검사하지 않는 필드** (BUILDLIST_PROC의 analytic 관련):
- `proc.buildlist.a_outptr_list` ← `@v3:=` 할당이 포함된 위치
- `proc.buildlist.g_outptr_list`
- `proc.buildlist.a_regu_list`
- `proc.buildlist.g_regu_list`

`@v3:=max(b) OVER(...)` 구문에서 `T_DEFINE_VARIABLE`는 analytic function의 output list
(`a_outptr_list`)에 존재하므로, checker가 이를 발견하지 못하고
`m_is_parallel_executable = true`로 남겨두어 병렬 실행이 허용됨.

## 수정 방향

`check_xasl_node()`에서 `BUILDLIST_PROC`일 때 analytic 관련 필드들도 검사하도록 추가:

```cpp
// px_query_checker.cpp - check_xasl_node() 내부에 추가
if (xasl->type == BUILDLIST_PROC)
  {
    if (xasl->proc.buildlist.a_outptr_list)
      {
        check_regu_var_list (xasl->proc.buildlist.a_outptr_list->valptrp);
      }
    if (xasl->proc.buildlist.g_outptr_list)
      {
        check_regu_var_list (xasl->proc.buildlist.g_outptr_list->valptrp);
      }
    check_regu_var_list (xasl->proc.buildlist.a_regu_list);
    check_regu_var_list (xasl->proc.buildlist.g_regu_list);
  }
```

## 관련 소스 파일

| 파일 | 위치 |
|------|------|
| session_define_variable | `src/session/session.c:2040` |
| session_add_variable | `src/session/session.c:1119` |
| fetch_peek_dbval (T_DEFINE_VARIABLE) | `src/query/fetch.c:3375-3383` |
| check_xasl_node (검사 누락) | `src/query/parallel/px_query_execute/px_query_checker.cpp:292-320` |
| check_regu_var (기존 체크) | `src/query/parallel/px_query_execute/px_query_checker.cpp:164-167` |
