# PR-6753 히스토그램 기능 통합 리뷰

**날짜:** 2026-04-04  
**브랜치:** pr-6753 (베이스: upstream/develop)  
**규모:** 140개 파일 변경 (upstream/develop 기준)

> 이 문서는 `upstream/develop` 대비 실제 변경된 코드만을 리뷰합니다.  
> 기존 코드에서 발견된 이슈는 [부록](#부록-pr-변경분이-아닌-기존-코드-이슈)에 별도 정리합니다.

---

## 목차

1. [기능 개요](#1-기능-개요)
2. [기존 동작과 변경 내용](#2-기존-동작과-변경-내용)
3. [히스토그램 수집 과정](#3-히스토그램-수집-과정)
4. [히스토그램 사용 과정 선택도-추정](#4-히스토그램-사용-과정-선택도-추정)
5. [코드 상세 분석](#5-코드-상세-분석)
6. [부수 변경사항](#6-부수-변경사항)
7. [코드 일관성 이슈](#7-코드-일관성-이슈)
8. [종합 평가 및 권고사항](#8-종합-평가-및-권고사항)
9. [부록: PR 변경분이 아닌 기존 코드 이슈](#부록-pr-변경분이-아닌-기존-코드-이슈)

---

## 1. 기능 개요

이 PR은 CUBRID 옵티마이저에 **컬럼 단위 히스토그램** 기능을 추가합니다. 히스토그램은 데이터 분포 정보를 사전에 수집해두고, 쿼리 최적화 시 조건절의 **선택도(selectivity)**를 정밀하게 추정하는 데 사용됩니다.

### 전체 아키텍처

```
[ 수집 단계 ]  ANALYZE TABLE t UPDATE HISTOGRAM ON (col)
                   |
                   v
            SQL 쿼리로 데이터 수집 (MCV 분리 + equi-depth)
                   |
                   v
            HistogramBuilder.build()  -- 바이너리 직렬화
                   |
                   v
            _db_histogram 테이블 저장 (histogram_values VARBIT)


[ 사용 단계 ]  SELECT * FROM t WHERE col = 5
                   |
                   v
            Parser -> PT_NODE
                   |
                   v
            qo_get_attr_info()  -- histogram / null_freq 로딩
                   |
                   v
            query_planner.c  -- 조건절 타입별 선택도 계산
              = (equal)      : histogram_get_equal_selectivity()
              < > <= >=      : histogram_get_comp_selectivity()
              BETWEEN        : qo_range_selectivity()
              LIKE           : histogram_get_like_selectivity()
              IS NULL        : null_frequency 직접 사용
                   |
                   v
            비용 기반 플랜 선택
```

### 지원 SQL 구문

| 구문 | 설명 |
|------|------|
| `ANALYZE TABLE t UPDATE HISTOGRAM ON (col1, col2) WITH 20 BUCKETS` | 히스토그램 생성/갱신 |
| `ANALYZE TABLE t UPDATE HISTOGRAM ON (col1) WITH FULLSCAN` | 풀스캔으로 정확한 히스토그램 생성 |
| `SHOW HISTOGRAM ON t (col1)` | 히스토그램 통계 출력 |
| `ANALYZE TABLE t DROP HISTOGRAM ON (col1)` | 히스토그램 삭제 |

### 주요 신규/변경 파일

| 영역 | 파일 | 설명 |
|------|------|------|
| 히스토그램 핵심 | `src/optimizer/histogram/` (6개 신규) | 수집/빌더/리더/선택도 계산 |
| 파서 | `csql_grammar.y`, `parse_tree.h` | DDL 구문, 파서 노드 타입 |
| 실행기 | `execute_schema.c`, `execute_statement.c` | DDL 실행 로직 |
| 옵티마이저 | `query_planner.c`, `query_graph.c` | 선택도 계산 통합 |
| 카탈로그 | `schema_system_catalog_install.cpp`, `schema_template.c` | `_db_histogram` 테이블 |
| 스키마 관리 | `schema_manager.c`, `class_object.c` | 히스토그램 생성/삭제/무효화 |

---

## 2. 기존 동작과 변경 내용

### 2.1 기존 선택도 추정 방식

기존 `qo_equal_selectivity()`는 **System R 알고리즘**을 사용합니다 (query_planner.c:9370):

| 조건 타입 | 기존 동작 | 한계 |
|-----------|-----------|------|
| `col = 상수` (인덱스 있음) | `1.0 / index_cardinality` | NDV만 알고 분포는 모름 |
| `col = 상수` (인덱스 없음) | `DEFAULT_EQUAL_SELECTIVITY = 0.001` (0.1%) | 고정값 |
| `col < 상수` | `DEFAULT_SELECTIVITY = 0.1` (10%) | 고정값 |
| `col LIKE 'abc%'` | 패턴 길이 기반 휴리스틱 | 실제 데이터와 무관 |
| `col IS NULL` | `DEFAULT_NULL_SELECTIVITY = 0.01` (1%) | 항상 1% 가정 |

인덱스가 있는 컬럼은 `1.0 / NDV`로 어느 정도 추정이 가능했으나, **데이터 분포(skew)를 반영하지 못합니다.** 예를 들어 `status` 컬럼에 `'active'` 95%, `'inactive'` 5%로 분포하고 NDV=2이면, `WHERE status = 'inactive'` 선택도를 실제 5%가 아닌 `1/2 = 50%`로 계산합니다. 인덱스가 없는 컬럼은 항상 고정값만 사용합니다.

### 2.2 변경 후 동작

이 PR은 **사전에 수집된 히스토그램 데이터를 사용하여 실제 데이터 분포에 기반한 선택도를 추정**합니다.

```
[기존]
  WHERE col = 5
      -> selectivity = 0.1 (고정)

[변경 후]
  WHERE col = 5
      -> _db_histogram 에서 col의 히스토그램 로딩
      -> 버킷 탐색으로 실제 빈도 계산
      -> selectivity = (버킷 내 행 수 / 전체 행 수) / approx_ndv
```

히스토그램이 없는 컬럼은 기존 기본값으로 폴백(fallback)하므로, **히스토그램이 없는 컬럼의 동작은 기존과 동일**합니다.

### 2.3 주요 변경 항목 요약

#### 파서 계층 변경 (`csql_grammar.y`, `parse_tree.h`)

기존에 없던 `ANALYZE TABLE ... UPDATE/DROP HISTOGRAM`, `SHOW HISTOGRAM` DDL 구문이 추가되었습니다.

- **추가된 토큰:** `BUCKETS`, `HISTOGRAM` 키워드
- **추가된 파서 노드 타입:** `PT_UPDATE_HISTOGRAM`, `PT_SHOW_HISTOGRAM`, `PT_DROP_HISTOGRAM`
- **추가된 구조체:** `PT_HISTOGRAM_INFO` (target_table_spec, target_columns, bucket_count, with_fullscan)
- **PT_NAME 노드 확장:** 기존 이름 노드에 `histogram`(DB_VALUE*), `null_frequency`(double) 필드 추가 — 옵티마이저가 속성별 히스토그램 데이터를 파서 노드에 직접 캐시하기 위함

#### 카탈로그 변경 (`schema_system_catalog_install.cpp`)

히스토그램을 저장할 새로운 시스템 카탈로그 테이블 `_db_histogram`이 추가되었습니다.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `class_of` | OBJECT | 대상 클래스 참조 |
| `key_attr` | VARCHAR(255) | 속성명 |
| `with_fullscan` | INTEGER | 풀스캔 여부 |
| `null_frequency` | DOUBLE | NULL 비율 (0.0~1.0) |
| `histogram_values` | VARBIT | 바이너리 히스토그램 blob |

유니크 제약: `(class_of, key_attr)`  
사용자용 뷰: `db_histogram` (with_fullscan을 'full scan'/'sampling scan' 문자열로 변환)

기존에는 `_db_statistics`에 간단한 통계만 있었습니다. `CNT_CATCLS_OBJECTS`가 6에서 8로 증가합니다.

#### 옵티마이저 변경 (`query_planner.c`, `query_graph.c`)

기존 `qo_equal_selectivity()`, `qo_comp_selectivity()` 함수들은 고정 기본값을 반환했습니다. 이번 변경으로:

- **`qo_get_attr_info()`** (query_graph.c): 쿼리 컴파일 시 `stats_get_histogram()`을 호출하여 관련 속성의 히스토그램을 PT_NAME 노드에 로딩
- **`qo_equal_selectivity()`**: 히스토그램이 있으면 `histogram_get_equal_selectivity()` 호출, 없으면 기존 기본값 사용
- **`qo_comp_selectivity()`**: 히스토그램이 있으면 `histogram_get_comp_selectivity()` 호출
- **`qo_expr_selectivity()`**: `IS NULL`/`IS NOT NULL` 조건에 대해 `null_frequency` 직접 사용 (기존: 항상 1%)
- **비NULL 조건 보정**: 모든 조건절 선택도에 `(1 - null_frequency)` 곱하기 추가 — NULL 행은 조건에 매칭되지 않으므로 정확도 향상
- **`qo_like_selectivity()`** (신규): LIKE 조건에 히스토그램 기반 선택도 적용

#### 스키마 생명주기 관리 변경 (`schema_manager.c`, `execute_schema.c`)

히스토그램의 stale 데이터 방지를 위한 자동 무효화 로직이 추가되었습니다:

- **`ALTER TABLE ... DROP/MODIFY/CHANGE/RENAME COLUMN`**: 영향받는 컬럼의 히스토그램 자동 삭제
- **`DROP CLASS`**: 클래스 삭제 시 해당 클래스의 모든 히스토그램 cascade 삭제
- **`UPDATE STATISTICS`**: 통계 갱신 시 히스토그램도 함께 갱신
- **`install_new_representation()`**: 새 클래스 표현 설치 시 히스토그램 정리

---

## 3. 히스토그램 수집 과정

### 3.1 실행 경로

```
csql_grammar.y:4765       PT_UPDATE_HISTOGRAM 파서 노드 생성
       |
execute_statement.c:3279  do_update_histogram() 디스패치
       |
execute_schema.c:4442     update_or_drop_histogram_helper()
       |                    1) sm_update_statistics()   -- 먼저 테이블 통계 갱신
       |                    2) sm_add_histogram()        -- _db_histogram 카탈로그 엔트리 생성
       |                    3) analyze_classes()         -- 실제 데이터 수집 (아래 3단계)
       |
histogram_cl.cpp:56       analyze_classes() 3단계 파이프라인
```

`sm_add_histogram()`과 `sm_drop_histogram()`은 savepoint를 사용하여 카탈로그 조작의 원자성을 보장합니다.

### 3.2 3단계 수집 파이프라인

#### 1단계: NULL 빈도 수집

`get_null_frequency()` (histogram_cl.cpp:112-211)

내부적으로 SQL 쿼리를 실행하여 NULL 비율을 구합니다:

```sql
-- 샘플링 모드 (기본)
SELECT /*+ SAMPLING_SCAN */
  AVG(CASE WHEN [col] IS NULL THEN 1.0 ELSE 0.0 END) AS null_frequency
FROM [table];

-- 풀스캔 모드 (WITH FULLSCAN 지정 시)
SELECT SUM(CASE WHEN [col] IS NULL THEN 1 ELSE 0 END) * 1.0
  / NULLIF(COUNT(*), 0) AS null_frequency
FROM [table];
```

> 샘플링 모드에서 `AVG`를 사용하는 이유: `SAMPLING_SCAN` 힌트는 행 수를 스케일링하여 반환하므로 `COUNT(*)`를 분모로 쓰면 과소 집계될 수 있습니다. `AVG(0/1)`은 비율을 그대로 유지합니다.

결과를 `_db_histogram.null_frequency` 컬럼에 저장합니다.

#### 2단계: 히스토그램 버킷 구축

`get_histogram()` (histogram_cl.cpp:227-445)

두 번의 SQL 쿼리를 실행합니다.

**쿼리 1 - MCV(Most Common Value) 개수 산출:**

```sql
WITH s AS (SELECT /*+ SAMPLING_SCAN */ [col] val FROM [tbl] WHERE [col] IS NOT NULL),
     f AS (SELECT val, COUNT(*) cnt FROM s GROUP BY val),
     t AS (SELECT COUNT(*) total_cnt FROM s)
SELECT COUNT(*) mcv_count
FROM f, t WHERE cnt > total_cnt * (0.5 / bucket_count);
```

빈도가 `total / (2 * bucket_count)` 초과인 값을 MCV로 분류합니다.

**쿼리 2 - MCV + Equi-depth 버킷 구축:**

```sql
WITH
  cnt AS (SELECT val, COUNT(*) AS c FROM src GROUP BY val),
  mcv_ranked AS (SELECT val, c, ROW_NUMBER() OVER (ORDER BY c DESC, val) AS rn
                 FROM cnt ORDER BY c DESC LIMIT mcv_count),
  non_mcv AS (...),
  hist_buckets AS (SELECT FLOOR((seg_cum-1)/cap) AS local_bid, ...),
  hist_grouped AS (SELECT MAX(val) AS endpoint,    -- 버킷 상한값
                          SUM(c) AS rows_in_bucket, -- 버킷 행 수
                          COUNT(*) AS approx_ndv,   -- 추정 고유값 수
                          FALSE AS is_mcv
                   FROM hist_buckets GROUP BY seg_id, local_bid),
  mcv_buckets AS (SELECT val AS endpoint, c AS rows_in_bucket,
                         1 AS approx_ndv, TRUE AS is_mcv
                  FROM mcv_ranked)
SELECT endpoint, rows_in_bucket,
       SUM(rows_in_bucket) OVER (ORDER BY endpoint) AS cumulative,
       approx_ndv, is_mcv
FROM (SELECT * FROM hist_grouped UNION ALL SELECT * FROM mcv_buckets)
ORDER BY endpoint;
```

핵심 설계:
- **MCV 버킷**: 고빈도 값은 개별 버킷으로 분리 (`approx_ndv = 1`) → 정확한 빈도 추정 가능
- **Equi-depth 버킷**: 나머지 값들을 누적 행 수 기준으로 균등 분할 (`approx_ndv >= 1`)
- MCV 값들 사이에 세그먼트가 생겨, 각 세그먼트 내에서 equi-depth 분할이 독립적으로 수행됨

#### 3단계: 바이너리 직렬화 후 저장

`HistogramBuilder::build()` (histogram_builder.cpp:85-264) → `set_histogram()` (histogram_cl.cpp:448-500)

### 3.3 바이너리 포맷과 저장

```
바이너리 포맷 (HST1):
+------------------+------------------------+----------------+
|  HeaderV1 (24B)  |  버킷 레코드 * N (24B) | 문자열 blob    |
+------------------+------------------------+----------------+

HeaderV1:                             각 버킷 레코드 (24B):
  magic[4]    = "HST1"                 data_hi     : 8B  -- endpoint 값
  version     = 1                      cumulative  : 8B  -- 누적 행 수
  nbuckets    = N                      approx_ndv  : 8B  -- 추정 고유값 수
  str_size    = 문자열 blob 크기
  type        = DB_TYPE
  total_size  = 전체 바이트 크기
```

모든 정수 필드는 네트워크 바이트 오더(big-endian)로 저장되어 플랫폼 독립성을 보장합니다.

문자열 컬럼의 특수 처리: 4바이트 이하 문자열은 버킷 레코드에 인라인으로 저장, 초과하면 별도 문자열 blob에 저장 후 오프셋 기록.

**샘플링 최적화:** `WITH FULLSCAN` 미지정 시 `/*+ SAMPLING_SCAN */` 힌트로 근사 수집하여 대용량 테이블의 수집 비용을 줄입니다.

### 3.4 수집 과정의 문제점

#### [CRITICAL] 헤더 내 `static const char*` SQL 템플릿 - ODR 위반

- **파일:** `src/optimizer/histogram/histogram_cl.hpp:38-252`
- **왜 문제인가:** C/C++에서 헤더에 `static const char*`를 정의하면, 이 헤더를 `#include`하는 **모든 .c/.cpp 파일**에 동일한 문자열의 복사본이 각각 생깁니다. 현재 이 헤더는 5개 파일(execute_schema.c, query_planner.c, histogram_cl.cpp, schema_manager.c, class_object.c)에서 포함되므로, 100줄짜리 SQL 문자열 5개 × 5 TU = **25개 복사본**이 바이너리에 들어갑니다. 실제로 SQL 템플릿을 사용하는 곳은 `histogram_cl.cpp` 한 곳뿐입니다.
- **수정 방안:** `histogram_cl.cpp`로 이동하여 파일 범위 `static`으로 변경. 추가로 거의 동일한 두 템플릿(SAMPLING_SCAN 유무 차이만)을 힌트 부분 `%s`로 통합:

```c
/* histogram_cl.cpp로 이동 + 중복 통합 */
static const char *HISTOGRAM_QUERY_TEMPLATE_FMT =
    "WITH s AS (SELECT %s %s val FROM %s WHERE %s IS NOT NULL), ...";
/*                    ^^ 힌트 자리 */
snprintf (query_buf, ..., HISTOGRAM_QUERY_TEMPLATE_FMT,
          use_sampling ? "/*+ SAMPLING_SCAN */" : "",
          escaped_col, escaped_tbl, escaped_col);
```

#### [CRITICAL] `quiet_NaN()` 정수형에서 0 반환

- **파일:** `src/optimizer/histogram/histogram_builder.hpp:48`
- **왜 문제인가:** `std::numeric_limits<int64_t>::quiet_NaN()`은 **정수형에서 항상 0을 반환**합니다. NaN은 부동소수점 전용 개념입니다. 이 값이 `approx_ndv`의 기본 매개변수로 사용되므로, 호출자가 NDV를 생략하면 `approx_ndv = 0`이 되어 선택도 계산에서 `bucket_rows / total_rows / approx_ndv`가 **0으로 나누기**(+infinity)를 일으킵니다. 현재 모든 호출부가 값을 명시하고 있어 즉시 발생하지는 않지만, 코드 변경 시 발현 가능합니다.
- **수정 방안:**

```cpp
/* 수정안 A (권장 - 기본값 제거하여 호출자 명시 강제) */
void add (HistogramTypes data_hi, std::int64_t cumulative, std::int64_t approx_ndv);

/* 수정안 B (기본값 유지 필요 시) */
static constexpr std::int64_t APPROX_NDV_UNKNOWN = -1;
void add (HistogramTypes data_hi, std::int64_t cumulative,
          std::int64_t approx_ndv = APPROX_NDV_UNKNOWN);
```

#### [HIGH] `HistogramBuilder::build`에서 `db_private_realloc` 실패 시 메모리 누수

- **파일:** `src/optimizer/histogram/histogram_builder.cpp:246-252`
- **왜 문제인가:** `db_private_realloc` 실패 시 POSIX 규칙에 따라 원본 `buffer`는 이미 해제됩니다. 그런데 실패 직후 `str_blob_ptr`만 해제(line 250)하고 `buffer`는 NULL로 초기화하지 않은 채 반환하여, 호출자가 `buffer`를 재해제하면 **use-after-free**가 발생합니다. `end_buffer`/`buffer_ptr`는 realloc 이후 실제로 접근되지 않으므로 stale 포인터 자체는 문제없습니다.

#### [MEDIUM] `er_set()` 미호출로 stale 에러 정보 전파

- **파일:** `histogram_cl.cpp` 다수 위치
- **왜 문제인가:** CUBRID에서 `er_errid()`/`er_msg()`는 마지막 `er_set()` 호출의 정보를 반환합니다. `er_set()` 없이 `ER_FAILED`만 반환하면, 호출자가 `er_msg()`로 에러 내용을 확인할 때 **이전의 전혀 관계없는 에러 메시지**가 출력되어 디버깅이 매우 어려워집니다.

#### [MEDIUM] `db_compile_and_execute_local` 반환값 체크 불일치

- **파일:** `histogram_cl.cpp`
- **왜 문제인가:** 이 함수는 성공 시 **행 수(>=0)**, 실패 시 **음수**를 반환합니다. `get_null_frequency()`는 `< 1`로 체크하여 0행(빈 테이블)도 에러로 취급하고, `get_histogram()`은 `< 0`으로 체크합니다. 빈 테이블에 대해 `get_null_frequency()`가 실패를 반환하면 히스토그램 생성 자체가 중단됩니다.

#### [MEDIUM] 잘못된 에러코드 `ER_QPROC_DB_SERIAL_NOT_FOUND`

- **파일:** `schema_template.c:~2098`
- **왜 문제인가:** 히스토그램 클래스 조회 실패 시 시리얼(시퀀스) 관련 에러코드를 사용합니다. 에러 로그에 "시리얼을 찾을 수 없음" 메시지가 나와 운영자가 전혀 다른 문제로 오인할 수 있습니다.

#### [MEDIUM] `dbt_abort_object(NULL)` 호출

- **파일:** `histogram_cl.cpp:175-176`
- **왜 문제인가:** `dbt_edit_object` 실패(NULL 반환) 후 `dbt_abort_object(NULL)`을 호출합니다. abort할 대상이 없으므로 의미 없는 호출이며, `dbt_abort_object`의 NULL 처리 여부에 따라 crash가 발생할 수 있습니다.

#### [LOW] 쿼리 버퍼 매직 넘버 `222`, `254`

- **파일:** `histogram_cl.cpp:122,244`
- **왜 문제인가:** 이 숫자들이 테이블/컬럼명 최대 길이를 의미하는 것 같지만, 코드만 봐서는 근거를 알 수 없습니다. `SM_MAX_IDENTIFIER_LENGTH` 같은 기존 상수를 사용하면 자동으로 따라갑니다.

#### [LOW] 중복 쿼리 템플릿 (~200줄)

- **파일:** `histogram_cl.hpp`
- **왜 문제인가:** `HISTOGRAM_QUERY_TEMPLATE`과 `HISTOGRAM_WITH_SAMPLING_SCAN_QUERY_TEMPLATE`이 ~100줄씩 거의 동일하고, 차이는 `/*+ SAMPLING_SCAN */` 힌트 유무뿐입니다. 한 템플릿의 버그를 수정하면서 다른 쪽을 놓칠 위험이 높습니다.

---

## 4. 히스토그램 사용 과정 (선택도 추정)

### 4.1 히스토그램 로딩

```
query_graph.c: qo_get_attr_info() (5251-5310행)
  -> sm_get_class_with_statistics()로 클래스 통계 로딩
  -> stats_get_histogram()으로 각 속성의 히스토그램 blob + null_frequency 로딩
  -> PT_NAME 노드의 info.name.histogram / info.name.null_frequency에 설정
```

쿼리 컴파일 시 옵티마이저가 관련 테이블의 히스토그램을 자동으로 로딩합니다.

`stats_get_histogram()` (histogram_cl.cpp:1346-1491):
- 클래스의 모든 속성에 대해 히스토그램 로딩
- `HIST_STATS` 구조체 할당 (n_attrs 크기 배열)
- 각 속성마다 `db_get_histogram()` → `histogram_values`/`null_frequency` 추출
- 에러 시 부분 할당된 메모리 전체 정리

### 4.2 등호 선택도 (`col = 값`)

`histogram_get_equal_selectivity()` (histogram_cl.cpp:774-847)

```
1. 이진 탐색으로 해당 값이 속한 버킷 찾기
2-a. 값을 찾지 못함:
     selectivity = 1 / total_rows           -- 한 행만 존재한다고 추정
2-b. MCV 버킷에서 찾음 (approx_ndv == 1):
     selectivity = bucket_rows / total_rows  -- 정확한 빈도 비율
2-c. 일반 버킷에서 찾음 (approx_ndv > 1):
     selectivity = (bucket_rows / total_rows) / approx_ndv
                                              -- 균등 분포 가정
```

### 4.3 비교 선택도 (`col < 값`, `col >= 값` 등)

`histogram_get_comp_selectivity()` (histogram_cl.cpp:850-1093)

```
1. 이진 탐색으로 버킷 위치 결정
2. MCV 버킷이면:
     누적값(cumulative)으로 정확한 경계 계산
3. 일반 버킷이면 (선형 보간):
     lo = bucket_hi[i-1]   -- 이전 버킷 상한
     hi = bucket_hi[i]     -- 현재 버킷 상한
     frac = (value - lo) / (hi - lo)
     estimated_rows = cumulative[i-1] + bucket_rows[i] * frac
     selectivity = estimated_rows / total_rows
4. 방향 조정:
     >= 또는 > 이면: selectivity = 1.0 - selectivity
```

타입별 보간 함수 (`histogram_cl.cpp`):
- 정수: `numeric_domain_frac_i64_lt()` (657행)
- 실수: `numeric_domain_frac_dbl_lt()` (689행, long double 정밀도)
- 문자열: `string_domain_frac_lt()` (743행, 바이트별 수치 보간)
- 부호없는 정수: `numeric_domain_frac_u64_lt()` (670행)

`string_pos()`는 문자열의 첫 16바이트를 base-257 수치로 변환하여 [0,1) 범위의 정규화된 위치를 반환합니다. 이를 통해 문자열 간의 "거리"를 수치적으로 추정할 수 있습니다.

### 4.4 범위/BETWEEN 선택도

`qo_range_selectivity()` (query_planner.c:10447-10650)

두 번의 비교 선택도 호출 결과의 차이로 계산합니다:

```
BETWEEN a AND b:
  selectivity = sel(col <= b) - sel(col < a)

방향별 조합:
  GE_LE:  sel_le(b) - sel_lt(a)      -- a <= col <= b
  GT_LT:  sel_lt(b) - sel_le(a)      -- a < col < b
  GE_INF: sel_ge(a)                   -- col >= a (상한 없음)
  INF_LE: sel_le(a)                   -- col <= a (하한 없음)
```

### 4.5 LIKE 선택도 (`col LIKE 'abc%'`)

`histogram_get_like_selectivity()` (histogram_cl.cpp:1221-1310)

히스토그램 기반 매칭과 패턴 휴리스틱을 결합합니다:

```
1. MCV 버킷에 패턴 매칭:
   matched_mcv_rows = SUM(bucket_rows) where like_match(pattern, value)

2. 일반 버킷에 패턴 매칭:
   matched_buckets_sel = 매칭된 버킷의 비율
   confidence = SUM(1/approx_ndv)  -- NDV가 작을수록 신뢰도 높음

3. 패턴 휴리스틱 (히스토그램이 커버하지 못하는 부분):
   고정문자: 0.20, _ 와일드카드: 0.90, % 와일드카드: 5.0 (1.0 클램프)
   pattern_sel = 각 문자 계수의 곱

4. 최종 결합:
   hist_weight = min(1.0, confidence)
   non_mcv_sel = matched_buckets_sel * hist_weight
               + pattern_sel * (1.0 - hist_weight)
   selectivity = (matched_mcv_rows / total_rows)
               + (1 - mcv_rows/total_rows) * non_mcv_sel
```

### 4.6 IS NULL / IS NOT NULL 선택도

query_planner.c:9806-9846에서 직접 처리:

```
IS NULL:     selectivity = null_frequency
IS NOT NULL: selectivity = 1.0 - null_frequency

null_frequency >= 0.0 이면 유효, -1.0이면 미설정 (기존 기본값 사용)
```

**기존과의 차이:** 기존에는 IS NULL 선택도가 항상 `DEFAULT_NULL_SELECTIVITY = 0.01` (1%)였습니다. 이제 히스토그램 수집 시 측정한 실제 NULL 비율을 사용합니다.

### 4.7 주요 함수 참조 테이블

| 선택도 타입 | 함수 | 파일:행 |
|-------------|------|---------|
| 등호 (=) | `histogram_get_equal_selectivity()` | histogram_cl.cpp:774 |
| 비교 (<,>,<=,>=) | `histogram_get_comp_selectivity()` | histogram_cl.cpp:850 |
| LIKE | `histogram_get_like_selectivity()` | histogram_cl.cpp:1221 |
| 범위/BETWEEN | `qo_range_selectivity()` | query_planner.c:10447 |
| IS NULL | (인라인) | query_planner.c:9806 |
| 패턴 휴리스틱 | `pattern_heuristic_selectivity()` | histogram_cl.cpp:1096 |
| 패턴 매칭 | `like_match_string()` | histogram_cl.cpp:1168 |
| 히스토그램 로딩 | `stats_get_histogram()` | histogram_cl.cpp:1346 |
| 키 추출 | `histogram_extract_key()` | histogram_cl.cpp:538 |
| 버킷 탐색 | `HistogramReader::find_bucket<T>()` | histogram_reader.hpp:100 |
| 수집 오케스트레이션 | `analyze_classes()` | histogram_cl.cpp:56 |
| NULL 빈도 수집 | `get_null_frequency()` | histogram_cl.cpp:112 |
| 히스토그램 데이터 수집 | `get_histogram()` | histogram_cl.cpp:227 |
| 바이너리 빌드 | `HistogramBuilder::build()` | histogram_builder.cpp:85 |
| 카탈로그 저장 | `set_histogram()` | histogram_cl.cpp:448 |

### 4.8 선택도 추정의 문제점

#### [HIGH] 빈 히스토그램에서 0으로 나누기

- **파일:** `histogram_cl.cpp:829`
- **왜 문제인가:** 빈 테이블(행 없음)에 히스토그램을 만들면 `total_rows() = 0`입니다. 이때 값을 찾지 못한 경로에서 `selectivity = 1.0 / total_rows()`가 실행되어 **+infinity**가 됩니다. 이 값이 옵티마이저 비용 계산에 전파되면 잘못된 플랜이 선택됩니다. found 경로(837행)에는 `total_rows <= 0.0` 가드가 있으나, not-found 경로(829행)에는 빠져 있습니다.
- **수정 방안:** `if (total_rows() <= 0) { *selectivity = 0.0; return; }` 가드 추가

#### [HIGH] `like_match_string` 멀티바이트 문자 미지원

- **파일:** `histogram_cl.cpp:1168-1218`
- **왜 문제인가:** LIKE 패턴의 `_`는 "한 문자"를 의미하는데, 이 함수는 `*p`와 `*s`를 **바이트 단위**로 비교합니다. UTF-8에서 한글 '가'는 3바이트(`0xEA 0xB0 0x80`)이므로, `_`가 1바이트만 매칭하여 한글 한 글자를 제대로 매칭하지 못합니다. 결과적으로 한글 등 멀티바이트 데이터에 대한 LIKE 선택도가 잘못 추정됩니다.
- **수정 방안:** CUBRID의 기존 collation-aware LIKE 매칭 사용, 또는 근사치임을 명시하는 주석 추가

#### [HIGH] 범위 선택도에서 음수 가능

- **파일:** `query_planner.c` (범위 선택도)
- **왜 문제인가:** `BETWEEN a AND b`의 선택도는 `sel(<=b) - sel(<a)`로 계산됩니다. 히스토그램 보간은 근사값이므로, 좁은 범위에서 `sel(<=b) < sel(<a)`가 될 수 있어 **음수 선택도**가 나옵니다. 음수 선택도는 비용 추정에서 음수 행 수로 이어져 옵티마이저가 비정상적인 플랜을 선택합니다.
- **수정 방안:** 뺄셈 직후 `MAX(selectivity, 0.0)` 클램프 추가

#### [HIGH] `const std::string&`로의 임시 객체 바인딩

- **파일:** `histogram_cl.cpp:1253`
- **왜 문제인가:** `db_get_string()`은 `const char*`를 반환하는데, 이를 `const std::string&`로 받으면 **임시 std::string 객체**가 생성됩니다. C++ 규칙상 `const&`에 바인딩된 임시 객체의 수명이 연장되어 동작은 하지만, 이 패턴은 코드 리뷰어가 메모리 소유권을 오인하기 쉽고, 미묘한 lifetime 버그의 원인이 됩니다.
- **수정 방안:** `std::string pattern(db_get_string(rhs_db_value))`로 명시적 복사

#### [MEDIUM] 비교 선택도 4개 타입별 ~160줄 코드 중복

- **파일:** `histogram_cl.cpp:849-1093`
- **왜 문제인가:** `switch(key.kind)`에서 i64/dbl/str/u64 각 케이스가 MCV 처리 + 선형 보간 + 방향 조정까지 ~40줄씩 거의 동일하게 반복됩니다. 만약 보간 알고리즘에 버그가 발견되면 **4곳 모두를 동일하게 수정**해야 하는데, 한 곳을 놓치면 특정 타입에서만 잘못된 선택도가 나옵니다.

#### [MEDIUM] `null_frequency` 센티넬 불일치

- **파일:** `query_graph.c` vs `histogram_cl.cpp:1418`
- **왜 문제인가:** 히스토그램이 없는 컬럼에 대해 `query_graph.c`는 `null_frequency = 0.0`을 설정하고, `histogram_cl.cpp`는 `-1.0`을 "미설정"으로 사용합니다. 옵티마이저는 `null_frequency >= 0.0`이면 유효한 값으로 판단하므로, `0.0`은 "NULL이 전혀 없다"로 해석됩니다. 실제로 NULL이 많은 컬럼에서 히스토그램이 없으면 `IS NULL`의 선택도가 0%로 계산되어 **인덱스 스캔 대신 풀 스캔을 선택**할 수 있습니다.

#### [MEDIUM] `bucket_count` 센티넬 처리 취약

- **파일:** `execute_statement.c:~4526`
- **왜 문제인가:** `bucket_count = -1`을 "사용자 미지정" 센티넬로 사용하나, `execute_schema.c`에서의 체크는 `== 0`입니다. `-1`이 버킷 수로 전달되어도 min-clamp(`< bucket_count_min`)에 의해 우연히 올바른 값으로 보정됩니다. 이 우연한 동작에 의존하면, min-clamp 로직이 변경될 때 `-1`개의 버킷을 생성하려는 시도가 발생할 수 있습니다.

---

## 5. 코드 상세 분석

### 5.1 신규 파일: 히스토그램 핵심 모듈 (6개)

#### histogram_cl.hpp - 쿼리 템플릿과 함수 선언

**경로:** `src/optimizer/histogram/histogram_cl.hpp`

**쿼리 템플릿 상수 (38-252행):**

| 상수명 | 행 | 용도 |
|--------|------|------|
| `NULL_FREQUENCY_QUERY_TEMPLATE` | 38-39 | NULL 비율 계산 (풀스캔). `SUM(CASE WHEN IS NULL)/COUNT(*)` |
| `NULL_FREQUENCY_WITH_SAMPLING_SCAN_QUERY_TEMPLATE` | 42-43 | NULL 비율 계산 (샘플링). 샘플링에서는 `COUNT(*)`가 스케일링되므로 `AVG`를 사용 |
| `MCV_COUNT_QUERY_TEMPLATE` | 46-50 | MCV 개수 산출. 빈도 > `total * 0.5/bucket_count`인 값의 수 |
| `HISTOGRAM_QUERY_TEMPLATE` | 53-151 | 전체 히스토그램 구축 (풀스캔). MCV 분리 + equi-depth 버킷 생성 |
| `HISTOGRAM_WITH_SAMPLING_SCAN_QUERY_TEMPLATE` | 154-252 | 위와 동일하나 `/*+ SAMPLING_SCAN */` 힌트 포함 |

**타입 정의 (namespace hist, 258-274행):**

```cpp
enum histogram_key_kind { invalid, i64, dbl, str, u64 };

struct histogram_key {
  histogram_key_kind kind;
  std::int64_t i64;    // INTEGER, SHORT, BIGINT
  double dbl;          // FLOAT, DOUBLE, NUMERIC
  std::string str;     // CHAR, STRING, BIT, VARBIT
  std::uint64_t u64;   // DATE, TIME, TIMESTAMP 등
};
```

DB_VALUE의 타입을 4가지 카테고리로 분류하여 히스토그램 버킷에서 통일된 방식으로 비교/보간합니다.

#### histogram_cl.cpp - 수집/선택도 구현

**경로:** `src/optimizer/histogram/histogram_cl.cpp`

**내부 유틸리티 함수:**

`histogram_init_reader_from_lhs()` (505-535행, static):
- PT_NAME 노드에서 히스토그램 blob을 꺼내 `HistogramReader`를 초기화
- `info.name.histogram` DB_VALUE에서 비트 데이터 추출
- 비트 길이를 8로 나누어 바이트 길이로 변환

`histogram_extract_key()` (538-652행, static):
- DB_VALUE의 타입에 따라 적절한 histogram_key로 변환
- 지원 매핑:
  - `DB_TYPE_INTEGER/SHORT/BIGINT` → `kind=i64`
  - `DB_TYPE_FLOAT/DOUBLE/NUMERIC` → `kind=dbl` (NUMERIC은 `numeric_db_value_coerce_to_num()`으로 변환)
  - `DB_TYPE_CHAR/STRING/BIT/VARBIT` → `kind=str`
  - `DB_TYPE_DATE/TIME/TIMESTAMP/*TZ/*LTZ` → `kind=u64`

#### histogram_builder.hpp/cpp - 빌더

**경로:** `src/optimizer/histogram/histogram_builder.hpp`

```cpp
namespace hist {

using HistogramTypes = std::variant<std::int64_t, double, std::uint64_t,
                                    std::string_view, std::string>;

struct Bucket {
  HistogramTypes data_hi;      // 버킷 상한값
  std::int64_t cumulative;     // 누적 행 수
  std::int64_t approx_ndv;     // 추정 고유값 수
};

class HistogramBuilder {
public:
  void add(HistogramTypes data_hi, std::int64_t cumulative,
           std::int64_t approx_ndv = std::numeric_limits<std::int64_t>::quiet_NaN());
  char *build(THREAD_ENTRY *thread_p, DB_TYPE type, int *histogram_total_length);
private:
  HeaderV1 header_;
  std::vector<Bucket> buckets_;
  std::int32_t cur_str_off_ = 0;   // 문자열 blob 누적 오프셋
};

} // namespace hist
```

**`write<T>()` 템플릿 특수화 (32-77행):**

| 특수화 | 동작 |
|--------|------|
| `write<int32_t>` | `OR_PUT_INT`, 8바이트 슬롯 (4B 값 + 4B 패딩) |
| `write<int64_t>` | `OR_PUT_INT64`, 8바이트 |
| `write<uint64_t>` | int64_t* reinterpret cast 후 `OR_PUT_INT64` |
| `write<double>` | `OR_PUT_DOUBLE`, 8바이트 |
| `write<string>` | 길이(4B) + 인라인(<=4B) 또는 blob 오프셋(>4B). 총 8바이트 |

**`build()` (85-264행) - 핵심 직렬화 로직:**

```
Phase 1: 버퍼 할당
  bucket_area_size = BUCKET_RECORD_SIZE(24) * bucket_count
  buffer = db_private_alloc(sizeof(HeaderV1) + bucket_area_size)

Phase 2: 버킷 레코드 쓰기
  각 버킷마다 DB_TYPE에 따라 적절한 write<T>() 호출
  assert(buffer_ptr == end_buffer)로 크기 계산 검증

Phase 3: 문자열 blob 구축 (4바이트 초과 문자열 존재 시)
  별도 blob 버퍼 할당
  db_private_realloc()으로 메인 버퍼 확장
  blob을 메인 버퍼 뒤에 연결

Phase 4: 헤더 쓰기
  memcpy(buffer, &H, sizeof(HeaderV1))
```

#### histogram_reader.hpp/cpp - 리더

**경로:** `src/optimizer/histogram/histogram_reader.hpp`

**HistogramReader 주요 메서드:**

| 메서드 | 반환 | 설명 |
|--------|------|------|
| `reset(blob)` | int | blob 파싱, 헤더 검증, 포인터 초기화 |
| `bucket_count()` | uint64_t | 버킷 수 |
| `total_rows()` | uint64_t | 마지막 버킷의 cumulative (전체 행 수) |
| `bucket_cumulative(i)` | int64_t | i번째 버킷까지의 누적 행 수. i<0이면 0 |
| `bucket_approx_ndv(i)` | int64_t | i번째 버킷의 추정 고유값 수 |
| `bucket_rows(i)` | int64_t | i번째 버킷의 행 수 (cumulative[i] - cumulative[i-1]) |
| `bucket_hi<T>(i)` | T | i번째 버킷의 상한값. i<0이면 `lowest()` |
| `find_bucket<T>(value)` | int | 이진 탐색으로 값이 속한 버킷 인덱스 반환. 빈 히스토그램이면 -1 |
| `check_value_included<T>(i, value)` | bool | MCV이면 정확 일치, 아니면 범위 포함 |
| `find_bucket_and_check<T>(value, idx)` | bool | find + check 결합. MCV 불일치 시 다음 버킷으로 이동 |

`find_bucket<T>()`의 이진 탐색:
```
if nb_ == 0: return -1
if value > bucket_hi[last]: return nb_ - 1
lo=0, hi=nb_-1
while lo < hi:
  mid = lo + (hi-lo)/2
  if value <= bucket_hi[mid]: hi = mid
  else: lo = mid + 1
return lo
```

`reset()` 검증 절차:
1. blob 크기 >= HeaderV1 크기 검증
2. 매직 넘버 "HST1" 검증
3. 버전 == 1 검증
4. nbuckets, str_size, type, total_size 읽기 (네트워크 바이트 오더)
5. `assert(total_size == blob.size())`
6. 버킷 영역 시작/끝 포인터 계산 및 경계 검증
7. 문자열 blob 포인터 설정

### 5.2 변경 파일: 파서 계층

#### csql_grammar.y - 문법 규칙

새 문법 규칙 (4694-4850행):

```
opt_with_column_list:
    ON '(' identifier_list ')'
  | /* empty */

update_histogram_stmt:
    ANALYZE TABLE class_name UPDATE HISTOGRAM opt_with_column_list
    opt_with_n_buckets opt_with_fullscan

drop_histogram_stmt:
    ANALYZE TABLE class_name DROP HISTOGRAM opt_with_column_list

show_histogram_stmt:
    SHOW HISTOGRAM ON class_name '(' identifier_list ')'

opt_with_n_buckets:
    WITH unsigned_integer BUCKETS
  | /* empty: default bucket count */
```

각 규칙은 `PT_UPDATE_HISTOGRAM`/`PT_DROP_HISTOGRAM`/`PT_SHOW_HISTOGRAM` 노드를 생성하고, `info.histogram` 구조체에 테이블/컬럼/버킷수/풀스캔 정보를 채웁니다.

#### semantic_check.c - 의미 분석

새 함수 `pt_check_update_histogram()` (9051-9121행):
- 대상 테이블이 실제 클래스인지 확인 (가상 클래스/시노님 거부)
- 파티션 클래스 거부
- 사용자 소유권 확인

#### name_resolution.c - 이름 해석

`pt_bind_names()` 확장 (3294-3311행):
- 히스토그램 문에 대해 스코프 스택을 설정하고 테이블/컬럼명을 바인딩
- target_table_spec을 스코프에 등록한 뒤 컬럼명 해석

### 5.3 변경 파일: 실행 계층

#### execute_statement.c - 문 실행 디스패치

- **MVCC 버전 설정 (3199-3201행):** `PT_UPDATE_HISTOGRAM`, `PT_DROP_HISTOGRAM`에 대해 `LC_FETCH_MVCC_VERSION` 설정
- **디스패치 (3280-3288행):** 각 히스토그램 문 타입을 `do_update_histogram()`, `do_drop_histogram()`, `do_show_histogram()`으로 라우팅
- **UPDATE STATISTICS 연동 (4513-4542행):** `do_update_stats()` 내에서 통계 갱신 후 히스토그램도 함께 갱신하도록 `update_or_drop_histogram_helper(DO_HISTOGRAM_CREATE)` 호출 추가

#### execute_schema.c - 스키마 실행 구현

`update_or_drop_histogram_helper()` (4156-4394행):
- 버킷 수 결정: 0이면 `prm_get_integer_value(PRM_ID_DEFAULT_HISTOGRAM_BUCKET_COUNT)` 사용
- min(16)/max(256) 범위 클램프
- 속성 목록 순회 (지정된 컬럼 또는 전체 속성):
  - **CREATE:** 타입 검사 → `sm_add_histogram()` → `analyze_classes()` → `dump_histogram()`
  - **DROP:** `sm_drop_histogram()`
  - **SHOW:** `dump_histogram()`
- 완료 후 클래스 통계/히스토그램 캐시 재로딩

**ALTER 시 히스토그램 무효화 (1813-1930행):**
- `do_alter()`에서 컬럼 DROP/MODIFY/CHANGE/RENAME 감지
- 영향받는 속성의 히스토그램이 존재하면 자동 삭제

### 5.4 변경 파일: 옵티마이저 계층

#### query_planner.c - 선택도 계산 통합

**상수/열거형 이동 (query_planner.h로):**
- `DEFAULT_NULL_SELECTIVITY(0.01)`, `DEFAULT_SELECTIVITY(0.1)` 등 10개 상수
- `PRED_CLASS` 열거형 (PC_ATTR, PC_CONST, PC_HOST_VAR 등)
- `qo_classify()` 함수를 extern으로 공개

**`qo_comp_selectivity()` 재작성 (10302-10420행):**
- PT_GE/GT/LE/LT 각각에 대해 `histogram_get_comp_selectivity()` 호출
- `is_ge`, `include_equal` 플래그 매핑:
  - `>=`: is_ge=true, include_equal=true
  - `>`: is_ge=true, include_equal=false
  - `<=`: is_ge=false, include_equal=true
  - `<`: is_ge=false, include_equal=false
- 양방향(속성 op 상수, 상수 op 속성) 모두 처리

#### query_graph.c - 히스토그램 로딩

**`set_seg_node()` 확장 (2916-2919행):**
- 세그먼트 → PT_NAME 노드에 histogram과 null_frequency 전파

**`qo_get_attr_info()` 확장 (5178-5310행):**
- `QO_GET_HIST_STATS(class_info_entryp)` 매크로로 HIST_STATS 접근
- 각 속성에 대해 히스토그램 인덱스 매칭
- PT_NAME 노드에 `histogram`(DB_VALUE*)과 `null_frequency`(double) 설정
- 히스토그램 없으면 NULL/0.0 초기화

### 5.5 변경 파일: 스키마/카탈로그 계층

#### statistics.h - HIST_STATS 구조체 (신규)

```c
struct hist_stats {
  int n_attrs;               // 속성 수
  DB_VALUE **histogram;      // 히스토그램 blob 배열
  double *null_frequency;    // NULL 빈도 배열
};

#define stats_free_histogram_and_init_and_set_null(p) \
  do { stats_free_histogram_and_init(p); (p) = NULL; } while(0)
```

#### class_object.c/h - 클래스 구조체

- `sm_class` 구조체에 `HIST_STATS *histogram` 필드 추가 (787행)
- `classobj_make_class()`에서 `histogram = NULL` 초기화
- `classobj_free_class()`에서 `stats_free_histogram_and_init_and_set_null()` 호출

#### schema_manager.c - 히스토그램 생명주기 관리

- `sm_add_histogram()`: savepoint 기반 원자적 카탈로그 엔트리 생성
- `sm_drop_histogram()`: 존재 확인 후 savepoint 기반 삭제
- `sm_get_class_with_statistics()`: 통계 로딩 시 히스토그램도 함께 로딩
- `sm_update_statistics()`: 통계 갱신 시 히스토그램 무효화
- `sm_delete_class_mop()`: 클래스 삭제 시 히스토그램 cascade 삭제

#### system_parameter.c - 시스템 파라미터

`PRM_ID_DEFAULT_HISTOGRAM_BUCKET_COUNT`:
- 이름: `"default_histogram_bucket_count"`
- 기본값: 16, 최소: 16, 최대: 256
- 플래그: `PRM_FOR_CLIENT | PRM_USER_CHANGE`
- 기존 `PRM_ID_LOG_POSTPONE_CACHE_SIZE`를 대체하여 같은 ID 슬롯을 사용

---

## 6. 부수 변경사항

### 6.1 스토리지/파일 매니저

- **`file_get_all_data_sectors`** (file_manager.c): 파일의 모든 데이터 섹터를 수집하는 신규 함수. 병렬 힙 스캔에서 ftab 기반 작업 분배에 사용
- **`random_poisson_weight`** (heap_file.c): 샘플링 스캔에서 포아송 분포 기반 확률적 페이지 스킵 구현
- **`mr_index_writeval_object`** (object_primitive.c): 인덱스 쓰기 함수 인라인 확장
- **`obj_find_multi_attr`** (object_accessor.c): BTREE 직접 조회 방식으로 리팩토링

### 6.2 스레드 개선

- **스레드 이름 지정:** 데몬/워커풀에 `pthread_setname_np` 추가 (kebab-case: `dwb-flush-block`, `log-checkpoint` 등)
- **컨텍스트 매니저 리팩토링:** `entry_manager` → `context_manager<T>` 템플릿 기반으로 전환

### 6.3 부수 변경의 문제점

#### [CRITICAL] `mr_index_writeval_object` SERVER_MODE NULL 역참조

- **파일:** `src/object/object_primitive.c:5192-5224`
- **왜 문제인가:** 원래 이 함수는 `return mr_index_writeval_oid(buf, value)` 한 줄이었습니다. 인라인 확장 후, `DB_TYPE_OBJECT`가 들어오면 `#if !defined(SERVER_MODE)` 안에서만 `oidp`를 설정합니다. 서버 프로세스(`SERVER_MODE`)에서는 이 블록이 컴파일되지 않으므로 `oidp`가 `NULL`로 남고, 바로 아래 `or_put_data(buf, (char *)(&oidp->pageid), ...)`에서 **NULL 포인터 역참조로 서버가 crash**합니다.
- **수정 방안:**

```c
if (DB_VALUE_TYPE (value) == DB_TYPE_OBJECT)
  {
#if !defined (SERVER_MODE)
    obj = db_get_object (value);
    oidp = WS_OID (obj);
#else
    /* SERVER_MODE에서는 DB_TYPE_OBJECT를 처리할 수 없음 */
    assert_release (false);
    return ER_FAILED;
#endif
  }
```

#### [CRITICAL] `file_get_all_data_sectors` 힙 버퍼 오버플로

- **파일:** `src/storage/file_manager.c:12550-12551`
- **왜 문제인가:** `ftab_collector.partsect_ftab` 배열을 `n_page_ftab`(ftab 페이지 수) 크기로 할당합니다. 그런데 콜백 함수 `file_extdata_collect_ftab_pages`는 ftab **페이지** 하나에서 여러 **섹터** 엔트리를 추출할 수 있습니다. 예를 들어 ftab 페이지가 3개인데 총 섹터가 30개이면, 3개짜리 배열에 30개를 쓰려고 하여 **힙 메모리가 덮어씌워집니다**. 바로 위 11958행에서 `collector_out->partsect_ftab`은 올바르게 `n_sector_total`로 할당하고 있어 불일치가 명확합니다.
- **수정 방안:**

```c
ftab_collector.partsect_ftab =
  (FILE_PARTIAL_SECTOR *) db_private_alloc (thread_p,
      fhead->n_sector_total * sizeof (FILE_PARTIAL_SECTOR));  /* n_page_ftab -> n_sector_total */
```

#### [HIGH] `obj_find_multi_attr` NULL 입력 검증 제거

- **파일:** `src/object/object_accessor.c:3675-3697`
- **왜 문제인가:** 리팩토링 전에는 `if (op == NULL || attr_names == NULL || values == NULL || size < 1)` 가드가 있었습니다. 리팩토링 후 이 검증이 사라져, NULL MOP이 전달되면 `dbt_create_object_internal(NULL, true)` 내부에서 **역참조 crash**가 발생합니다.

#### [HIGH] `obj_find_multi_attr` `oid_count` 미사용 변수

- **파일:** `src/object/object_accessor.c:3690,3782`
- **왜 문제인가:** `int oid_count = 0`으로 선언되지만 함수 어디에서도 증가시키지 않습니다. `assert(oid_count < 2)`는 항상 true이므로 아무 것도 검증하지 못합니다. 원래 의도가 "중복 OID 탐지"였다면, 이 검증이 빠져 있어 중복 OID가 무시됩니다.

#### [HIGH] `random_poisson_weight` 고정 난수 시드

- **파일:** `src/storage/heap_file.c:7887`
- **왜 문제인가:** `thread_local std::mt19937 rng { 123456789u }`는 **모든 스레드가 동일한 시드**를 사용합니다. `thread_local`이므로 각 스레드에 독립 인스턴스가 생기지만, 시드가 같아 **모든 스레드가 정확히 같은 난수 시퀀스**를 생성합니다. 병렬 스캔에서 4개 스레드가 각각 "3페이지 스킵, 5페이지 스킵, 2페이지 스킵..."을 동일하게 수행하면, 실질적으로 병렬화 효과가 줄어듭니다.
- **수정 방안:** `std::mt19937 rng { std::hash<std::thread::id>{}(std::this_thread::get_id()) }`

#### [HIGH] `config.h` include 순서 위반

- **파일:** `execute_schema.c:22`, `execute_statement.c:22-23`
- **왜 문제인가:** CUBRID 빌드 시스템은 `config.h`에서 플랫폼별 매크로(SERVER_MODE, SA_MODE 등)를 정의합니다. `config.h` 앞에 다른 헤더가 오면 해당 헤더가 **플랫폼 매크로 없이 컴파일**되어, `#ifdef SERVER_MODE` 블록이 의도와 다르게 동작할 수 있습니다.

#### [HIGH] 커밋 메시지 비표준

- **왜 문제인가:** CI가 PR 타이틀에 `^\[[A-Z]+-\d+\]\s.+` 패턴을 강제합니다. 커밋 메시지 `(ㅠㅠ)`, `(d)`, `\` 등은 git log에서 변경 의도를 전혀 파악할 수 없어, 향후 git bisect나 blame 시 디버깅이 불가능합니다.

#### [MEDIUM] 병렬 스캔 assert 순서 오류 (px_heap_scan_input_handler_ftabs.cpp:146-155)

- **왜 문제인가:** `pgbuf_ordered_fix` 실패(에러) 시에도 에러 체크(154행) 전에 assert(152행)가 먼저 실행됩니다. 에러 시 페이지 포인터가 NULL이므로 assert에서 NULL 역참조.

#### [MEDIUM] `CNT_CATCLS_OBJECTS` 주석 제거 (schema_class_truncator.cpp:529-532)

- **왜 문제인가:** 이 매직 넘버는 "시스템 카탈로그의 일반 객체 도메인 수"를 하드코딩한 값입니다. 히스토그램이 새 시스템 클래스를 추가했으므로 이 값이 변경되어야 할 수 있는데, 경고 주석이 삭제되어 놓치기 쉬워졌습니다.

#### [MEDIUM] `do_create_midxkey_for_constraint` 헤더 선언 누락 (execute_statement.c:12017)

- **왜 문제인가:** `static`에서 `extern`(외부 링키지)으로 변경했지만 헤더에 선언이 없어, 다른 파일에서 호출 시 **implicit declaration 경고** 및 잘못된 호출 규약으로 crash.

#### [MEDIUM] `TASK_COMM_LEN` 중복 정의 (thread_daemon.hpp, thread_worker_pool.hpp)

- **왜 문제인가:** 두 헤더에 `#ifndef` 가드로 동일 값이 정의됩니다. 한 곳만 변경하면 include 순서에 따라 적용되는 값이 달라집니다.

#### [LOW] `.c` 파일에 `<random>` C++ 헤더 (heap_file.c:42)
#### [LOW] 신규 `.hpp` 3개 파일 끝 newline 누락
#### [LOW] `histogram_cl.cpp` 일부 탭 인덴트 혼입
#### [LOW] `HIST_DUMP_WIDTH + 1` 버퍼 부족 가능 (histogram_cl.cpp:1577)
#### [LOW] MCV 덤프에서 미사용 변수 `lo` (histogram_cl.cpp:1771)
#### [LOW] `UPDATE STATISTICS ON ALL CLASSES`에서 전체 히스토그램 재빌드 (schema_manager.c:4445)

---

## 7. 코드 일관성 이슈

### 이름 규칙 불일치

| 이슈 | 위치 | 현재 | 기대값 |
|------|------|------|--------|
| C 함수명 규칙 미준수 | `histogram_cl.cpp` | `analyze_classes()`, `get_null_frequency()` | `histogram_analyze_classes()`, `histogram_get_null_frequency()` |
| 반환 문자열 불일치 | `parse_tree_cl.c:3079-3084` | `"update_histogram"`, `"show histogram"`, `"DROP_HISTOGRAM"` 혼재 | 모두 `"UPPER_CASE"` 통일 |
| 네임스페이스 닫기 주석 | `histogram_builder.hpp:63` | `} // namespace histo` | `} // namespace hist` |
| C++ 클래스명 PascalCase | `histogram_builder.hpp` 등 | `HistogramBuilder` | CUBRID 규칙: `snake_case` |
| 헬퍼 함수명 접두사 | `execute_schema.c:4156` | `update_or_drop_histogram_helper()` | `do_update_or_drop_histogram()` |
| 유사 함수명 혼동 | `class_object.c` vs `schema_manager.c` | `stats_free_histogram_and_init_and_set_null` vs `stats_free_histogram_and_init` | 차이점 문서화 |

### 서식 스타일 불일치

| 이슈 | 위치 | 설명 |
|------|------|------|
| `.c` 파일에 `//` 주석 | `schema_template.c:~2033` | CUBRID 규칙: `.c` 파일은 `/* */`만 |
| Grammar 4스페이스 인덴트 | `csql_grammar.y:~4741-4806` | 프로젝트 규칙은 2스페이스 |
| Grammar K&R 브레이스 | `csql_grammar.y:~4741-4806` | GNU 스타일 필요 |
| 시스템 헤더 위치 | `histogram_builder.cpp:28-31` | `<cstring>`이 프로젝트 includes 사이에 혼입 |
| C 헤더 사용 | `histogram_cl.cpp:~37-38` | `<stdio.h>` → `<cstdio>`, `<stdbool.h>` 제거 |

---

## 8. 종합 평가 및 권고사항

### 8.1 이슈 요약

| 심각도 | 수집 과정 | 선택도 추정 | 부수 변경 | 합계 |
|--------|-----------|-------------|-----------|------|
| CRITICAL | 2 | - | 2 | **4** |
| HIGH | 1 | 4 | 5 | **10** |
| MEDIUM | 4 | 3 | 5 | **12** |
| LOW | 2 | - | 6 | **8** |
| 일관성 | - | - | - | **11** |

**판정: 수정 요청 (REQUEST CHANGES)**

### 8.2 긍정적 평가

**설계:**
- MCV + Equi-depth 하이브리드 버킷 설계로 skewed distribution을 효과적으로 처리
- 매직 넘버 기반 버전 관리(HST1)와 O(1) 버킷 접근이 가능한 바이너리 포맷
- 이진 탐색 기반 버킷 조회로 효율적인 선택도 추정
- `SAMPLING_SCAN` 힌트를 통한 대용량 테이블 수집 비용 최적화

**안정성:**
- 트랜잭션 savepoint 활용으로 `sm_add_histogram`/`sm_drop_histogram` 원자성 보장
- ALTER/DROP column 시 히스토그램 자동 무효화로 stale 데이터 방지
- NULL 빈도 별도 추적으로 IS NULL/IS NOT NULL 선택도 정밀화 (기존 하드코딩 1% 대체)
- 시스템 파라미터(`PRM_ID_DEFAULT_HISTOGRAM_BUCKET_COUNT`)로 기본 버킷 수 설정 가능

**부수 변경:**
- `pthread_setname_np`로 스레드 이름 추가하여 디버깅 편의성 향상
- 에러 경로에서의 일관된 메모리 해제 및 페이지 unfix

### 8.3 수정 우선순위

#### 머지 전 반드시 수정 (CRITICAL 5건)

1. `mr_index_writeval_object` SERVER_MODE NULL 역참조 → `#else` 블록에 assert + 에러 반환
2. `file_get_all_data_sectors` 버퍼 크기 → `n_sector_total`로 변경
3. `quiet_NaN()` 센티넬 값 → 기본 매개변수 제거 또는 `-1`
4. `static const char*` 템플릿 → `.cpp`로 이동

#### 머지 전 수정 권장 (HIGH 10건)

- 빈 히스토그램 0으로 나누기 가드 추가
- `like_match_string` 멀티바이트 문서화 또는 수정
- 범위 선택도 음수 클램프 추가
- `obj_find_multi_attr` 입력 검증 복원 + `oid_count` 정리
- `random_poisson_weight` 고정 시드 수정
- `db_private_realloc` 실패 시 use-after-free 처리 (`buffer = NULL` 추가)
- `config.h` include 순서 수정
- 커밋 메시지 스쿼시 및 정리
- `const std::string&` 임시 객체 바인딩 수정

#### 개선 권고 (MEDIUM/LOW)

- 함수 이름 `module_action_object` 규칙 통일
- 에러 코드 일관성 (`er_set()` 호출, 적절한 에러코드)
- 비교 선택도 4개 타입별 중복 코드 템플릿화
- `null_frequency` / `bucket_count` 센티넬 값 통일
- GNU 브레이스 스타일 / 2스페이스 인덴트 준수

---

## 부록: PR 변경분이 아닌 기존 코드 이슈

> 아래 이슈들은 `upstream/develop`에 이미 존재하는 코드에서 발견된 것으로, 이 PR의 변경 범위에 포함되지 않습니다.

### 치명적 (CRITICAL)

| # | 파일 | 이슈 | 수정 방안 |
|---|------|------|-----------|
| A-C1 | `connection_support.cpp:1026` | `css_send_io_vector`가 `static`인데 헤더 템플릿에서 호출 -- 다른 TU에서 링크 실패 | `static` 제거 + 헤더 선언 추가 |
| A-C2 | `connection_less.cpp:215-240` | `css_remove_queued_connection_by_entry`에서 뮤텍스 누락 -- 리스트 손상 가능 | `CS_LOCK()`/`CS_UnLOCK()` 추가 |

### 높음 (HIGH)

| # | 파일 | 이슈 | 수정 방안 |
|---|------|------|-----------|
| A-H1 | `connection_less.cpp:158` | `free()` 사용 (`free_and_init` 필수 규칙 위반) | `free_and_init()` 변경 |
| A-H2 | `connection_cl.cpp:106` 등 | `CS_UnLOCK` 혼합 대소문자 매크로 | `CS_UNLOCK` 통일 |
| A-H3 | `connection_less.h:56` | 소멸자가 연결 리스트 미해제 | 소멸자에서 리스트 순회 해제 |
| A-H4 | `connection_less.cpp:183-207` | `css_get_queued_entry` 뮤텍스 미보호 순회 | `CS_LOCK()` 추가 |

### 중간/낮음 (MEDIUM/LOW)

| # | 파일 | 이슈 |
|---|------|------|
| A-M1 | `connection_defs.h:442-453` | `client_id` 등 `SERVER_MODE` 전용 이동 -- CS_MODE 빌드 확인 필요 |
| A-M2 | `connection_defs.h:532-554` | `CSS_MAP_ENTRY` `!SERVER_MODE` 제한 -- 서버 코드 참조 확인 |
| A-M3 | `connection_globals.h:84-85` | `css_Service_id`/`css_Service_name` 제거 -- 잔여 참조 확인 |
| A-M4 | `connection_less.cpp:100-105` | `css_make_entry_id` 뮤텍스 요구사항 주석 문서화만 |
| A-M5 | `object/elo.c:419-433` | `LOB_TRANSIENT_DELETED`에서 물리 파일 미이동 |
| A-L1 | `client_support.cpp:68-91` | `#if 0` 비활성 코드 블록 잔존 |
| A-L2 | `thread_worker_pool.hpp:586` | 데몬 이름 15자 초과 시 무경고 잘림 |

---

*Claude Code 리뷰 에이전트에 의해 생성됨 (2026-04-04)*
