# CHAR 타입 readval 시 intl 함수 병목 분석

- 날짜: 2026-03-31
- 대상 쿼리: `select /*+ parallel(0) */ count(*) from t1 where c2 = 'CUBRID TEST';`
- 모드: csql -S (Standalone)
- 프로파일링: `perf record -g -F 997`

## 1. 전체 함수별 Self Overhead (Top 25)

| Rank | Overhead | 함수명 | 모듈 |
|------|---------|--------|------|
| 1 | **30.84%** | `intl_nextchar_utf8` | libcubridsa |
| 2 | **14.07%** | `intl_char_size` | libcubridsa |
| 3 | 10.12% | `rep_movs_alternative` | kernel (page copy) |
| 4 | **4.29%** | `intl_nextchar_utf8@plt` | libcubridsa (PLT) |
| 5 | 2.67% | `heap_attrinfo_read_dbvalues` | libcubridsa |
| 6 | 2.00% | `heap_next_internal` | libcubridsa |
| 7 | 1.29% | `fetch_peek_dbval` | libcubridsa |
| 8 | 1.25% | `scan_next_scan_local` | libcubridsa |
| 9 | 1.16% | `mr_data_readval_char` | libcubridsa |
| 10 | 1.05% | `mr_cmpval_char` | libcubridsa |
| 11 | 0.99% | `tp_value_compare_with_error` | libcubridsa |
| 12 | 0.93% | `heap_scan_get_visible_version` | libcubridsa |
| 13 | 0.80% | `or_mvcc_get_header` | libcubridsa |
| 14 | 0.75% | `eval_value_rel_cmp` | libcubridsa |
| 15 | 0.71% | `eval_pred_comp0` | libcubridsa |
| 16 | 0.70% | `filemap_read` | kernel |
| 17 | 0.64% | `eval_data_filter` | libcubridsa |
| 18 | 0.62% | `filemap_get_read_batch` | kernel |
| 19 | 0.61% | `clear_page_erms` | kernel |
| 20 | 0.59% | `spage_next_record` | libcubridsa |
| 21 | 0.55% | `lang_fastcmp_byte` | libcubridsa |
| 22 | 0.54% | `folio_mark_accessed` | kernel |
| 23 | 0.52% | `__memset_evex_unaligned_erms` | libc |
| 24 | 0.45% | `spage_get_record_data` | libcubridsa |
| 25 | 0.43% | `pgbuf_unlatch_void_zone_bcb` | libcubridsa |

## 2. 카테고리별 합산

| 카테고리 | 합산 | 주요 함수 |
|----------|------|-----------|
| **intl (문자열 인코딩 처리)** | **49.20%** | `intl_nextchar_utf8`(30.84%) + `intl_char_size`(14.07%) + `@plt`(4.29%) |
| Heap Scan / Page I/O | ~15.56% | `rep_movs_alternative`(10.12%) + `heap_next_internal`(2.00%) + `heap_attrinfo_read_dbvalues`(2.67%) + `or_mvcc_get_header`(0.80%) |
| 문자열 비교 | ~3.34% | `mr_cmpval_char`(1.05%) + `tp_value_compare_with_error`(0.99%) + `eval_value_rel_cmp`(0.75%) + `lang_fastcmp_byte`(0.55%) |
| 스캔/필터 로직 | ~3.89% | `scan_next_scan_local`(1.25%) + `eval_data_filter`(0.64%) + `eval_pred_comp0`(0.71%) + `fetch_peek_dbval`(1.29%) |

## 3. 핵심 Call Chain

```
qexec_execute_mainblock
 └─ scan_next_scan → scan_next_scan_local
     ├─ heap_next → heap_next_internal                     ← 페이지 I/O (~15%)
     │   └─ pgbuf_ordered_fix_release → read() syscall
     └─ eval_data_filter                                   ← 필터 평가
         ├─ heap_attrinfo_read_dbvalues                    ← 컬럼 값 역직렬화
         │   └─ mr_data_readval_char                       ← CHAR 타입 읽기
         │       └─ intl_char_size                  ★ 14.07%
         │           └─ intl_count_utf8_bytes
         │               └─ intl_nextchar_utf8      ★ 30.84%  (루프 내 반복 호출)
         └─ eval_pred_comp0                                ← WHERE 비교
             └─ eval_value_rel_cmp
                 └─ tp_value_compare_with_error
                     └─ mr_cmpval_char → lang_fastcmp_byte ← 실제 비교 (0.55%)
```

## 4. 병목 원인: 왜 mr_data_readval_char에서 intl 함수가 필요한가?

### CHAR(n) 디스크 저장 방식의 문제

CHAR 타입은 **고정 길이** 타입이다. `CHAR(100)`이면 디스크에 항상 고정 크기로 저장된다.

디스크 할당 크기는 `STR_SIZE` 매크로로 계산된다:

```c
// object_primitive.c:122
#define STR_SIZE(prec, codeset) \
    (((codeset) == INTL_CODESET_RAW_BITS) ? ((prec+7)/8) : \
     INTL_CODESET_MULT(codeset) * (prec))

// intl_support.h:77
#define INTL_CODESET_MULT(codeset) \
    (((codeset) == INTL_CODESET_UTF8) ? INTL_UTF8_MAX_CHAR_SIZE : \  // = 4
     ((codeset) == INTL_CODESET_KSC5601_EUC) ? 3 : 1)
```

**UTF-8 + CHAR(100)인 경우:**

- `STR_SIZE(100, UTF8) = 4 * 100 = 400 bytes` (디스크에 400바이트 할당)
- 실제 `'CUBRID TEST'`는 11바이트만 사용, 나머지는 패딩

### readval 시 intl_char_size 호출이 필요한 이유

`mr_readval_char_internal`에서 디스크의 400바이트 중 **실제 유효 데이터가 몇 바이트인지** 알아내야 한다:

```c
// object_primitive.c:11806
mem_length = STR_SIZE(domain->precision, TP_DOMAIN_CODESET(domain));  // = 400

// object_primitive.c:11829 (copy=false 경로)
intl_char_size((unsigned char *) buf->ptr, domain->precision,
               TP_DOMAIN_CODESET(domain), &str_length);
// → precision(100)개 문자의 실제 바이트 수를 계산

// object_primitive.c:11872 (copy=true 경로도 동일)
intl_char_size((unsigned char *) new_, domain->precision,
               TP_DOMAIN_CODESET(domain), &actual_size);
```

**즉, 디스크에는 400바이트가 있지만 DB_VALUE에는 실제 문자열 길이(바이트)를 넣어야 하므로,
precision(100)개 문자를 하나씩 순회하면서 바이트 수를 세야 한다.**

### intl_count_utf8_bytes의 O(n) 순회

```c
// intl_support.c:2204
static int
intl_count_utf8_bytes (const unsigned char *s, int length_in_chars)
{
  for (char_count = 0, byte_count = 0; char_count < length_in_chars; char_count++)
    {
      s = intl_nextchar_utf8 (s, &char_width);  // ← 매 문자마다 호출
      byte_count += char_width;
    }
  return byte_count;
}
```

`intl_nextchar_utf8`는 lookup table `intl_Len_utf8_char[]`로 현재 바이트의 UTF-8 문자 길이를 구하고 포인터를 전진시킨다:

```c
// intl_support.h:71
#define INTL_GET_NEXTCHAR_UTF8(c, l) { \
    l = intl_Len_utf8_char[*(unsigned char*)(c)]; \
    c += (l); \
}
```

### 왜 이것이 전체 CPU의 49%를 차지하는가

1. **매 레코드마다 호출**: heap full scan이므로 테이블의 모든 행에 대해 실행
2. **precision 횟수만큼 루프**: `CHAR(100)`이면 100번 반복 (실제 데이터가 11바이트뿐이어도)
3. **함수 호출 오버헤드**: `intl_nextchar_utf8`는 별도 `.c` 파일의 함수 → PLT 경유 호출 (4.29% 추가)
4. **실제 비교(0.55%)보다 역직렬화(49.20%)가 90배 비쌈**

### 패딩 영역도 순회하는 문제

`CHAR(100)`에 `'CUBRID TEST'`(11문자)를 저장하면, 나머지 89문자분은 공백(0x20) 패딩이다.
`intl_char_size`는 `domain->precision`(=100)만큼 순회하므로, **패딩 영역의 89개 공백 문자도 모두 순회**한다.

## 5. 400바이트 전부 비교하면 안 되는가?

### 디스크 레이아웃 상세

CHAR(100) UTF-8에 `'CUBRID TEST'`(11문자, 전부 ASCII)를 저장한 경우:

```
디스크 400바이트:
[C][U][B][R][I][D][ ][T][E][S][T][ ][ ]...[ ][ ][ ]...[ ]
|<--- 11문자 실데이터 --->|<-- 89문자 CHAR 패딩(0x20) -->|<-- 300바이트 잔여(0x20) -->|
|<---------- 100문자 (precision) = 100바이트 ----------->|
|<------------------------- 400바이트 (STR_SIZE) --------------------------->|
```

write 시(`mr_writeval_char_internal`, object_primitive.c:11623) 동작:

```c
packed_length = STR_SIZE(src_precision, codeset);  // 400
src_length = db_get_string_size(value);            // 실제 바이트 (예: 100)

or_put_data(buf, src, src_length);                 // 실제 데이터 100바이트
for (i = src_length; i < packed_length; i++)
  or_put_byte(buf, (int) ' ');                     // 나머지 300바이트를 0x20으로 채움
```

### 문제점: 100문자 CHAR 패딩과 잔여 300바이트가 모두 0x20

- 89문자 CHAR 패딩 = 0x20 (SQL 표준)
- 300바이트 잔여 공간 = 0x20 (write 시 공백으로 채움)
- **둘 다 동일한 0x20이므로 100문자의 바이트 경계를 구분할 수 없다**

### 400바이트 그대로 비교하면?

CHAR 비교에서 `lang_fastcmp_byte`는 trailing space를 무시하므로 **비교 결과 자체는 정확하다.**

하지만 비교 외의 연산에서 문제 발생:
- `LENGTH()`, `SUBSTR()` 등 문자열 함수에서 결과가 달라짐 (400바이트 vs 100바이트)
- 네트워크 전송, 출력 시 400바이트를 보내게 됨
- 비교 시에도 300바이트 불필요한 공백을 추가 비교 (4배 비용)

### 잔여 영역을 0x00으로 채우는 방안

write 시 잔여 공간을 0x00으로 채우면:

```
[CUBRID TEST][ ][ ]...[ ][0x00][0x00]...[0x00]
|<-- 100문자 = 100바이트 -->|<-- 300바이트 0x00 -->|
```

read 시 **역방향 스캔**으로 바이트 경계를 O(1)에 가깝게 찾을 수 있다:

```c
// 현재: O(precision) 문자 순회
intl_char_size(buf, 100, UTF8, &str_length);  // 100번 반복

// 0x00 패딩이면: 역방향 스캔
for (i = mem_length - 1; i >= 0 && buf[i] == 0x00; i--);
str_length = i + 1;  // 빠름
```

단점: **디스크 포맷 변경 필요** (기존 데이터 마이그레이션, 하위 호환성 문제)

## 6. 다른 DBMS와의 비교

대부분의 주요 DBMS는 이 문제를 **디스크 포맷 설계 단계에서 회피**한다.

### PostgreSQL — CHAR도 내부적으로 varlena (가변 길이)

```
[varlena header (4 bytes, 바이트 길이 포함)][실제 데이터 + 공백 패딩]
```

- varlena 헤더에 바이트 길이가 포함 → 문자 순회 불필요
- 최대 바이트 할당(4*n)을 하지 않음. CHAR(100) ASCII면 100바이트 + 4바이트 헤더만 저장

### MySQL InnoDB — utf8mb4에서 CHAR를 가변 길이로 전환

MySQL 5.0.3 이후, 멀티바이트 charset의 CHAR는 내부적으로 가변 길이 저장:

```
InnoDB compact row format:
[레코드 헤더에 각 컬럼의 actual byte length 기록][데이터]
```

- CHAR(100) CHARACTER SET utf8mb4 → 최소 100~최대 400바이트 가변
- 레코드 헤더에 actual byte length 저장 → 순회 불필요

### Oracle — 행 헤더에 컬럼 길이 포함

```
[row header][col1_len][col1_data][col2_len][col2_data]...
```

- 각 컬럼 앞에 1~3바이트 길이 프리픽스
- CHAR(100)은 공백 패딩된 결과의 바이트 길이를 저장 → 순회 불필요

### 비교 요약

| DBMS | CHAR(n) + UTF-8 전략 | 디스크 크기 | readval 시 문자 순회 |
|------|---------------------|------------|-------------------|
| **CUBRID** | 고정 4*n 바이트, 길이 정보 없음 | 400 bytes 고정 | **O(n) 순회 필요 (49% overhead)** |
| **PostgreSQL** | varlena 헤더에 길이 포함 | 가변 (100+4) | 불필요 |
| **MySQL InnoDB** | 레코드 헤더에 길이 포함 | 가변 (100~400) | 불필요 |
| **Oracle** | 컬럼 길이 프리픽스 | 가변 + 길이 필드 | 불필요 |

**업계 표준은 "actual_byte_length를 레코드에 포함"하는 것이며,
문자 순회로 바이트 수를 계산하는 방식을 택하는 DBMS는 없다.**

## 7. 개선 가능성

| 방안 | 설명 | 난이도 |
|------|------|--------|
| **ASCII fast-path** | 문자열이 전부 ASCII(< 0x80)인 경우 `byte_count = length_in_chars`로 즉시 반환. CHAR 패딩은 0x20이므로 대부분 ASCII. | **코드만 수정** |
| **inline화** | `intl_nextchar_utf8`를 `static inline`으로 선언하면 PLT 오버헤드(4.29%) 제거 가능 | **코드만 수정** |
| **잔여 공간 0x00 패딩** | write 시 잔여를 0x00으로 채우고 read 시 역방향 스캔 | 디스크 포맷 변경 |
| **레코드에 byte_length 저장** | 다른 DBMS와 동일한 방식. 근본적 해결 | 디스크 포맷 변경 |
| **VARCHAR 사용 권장** | VARCHAR는 길이 정보가 포함되어 있어 이 문제가 발생하지 않음 | 스키마 변경 |
