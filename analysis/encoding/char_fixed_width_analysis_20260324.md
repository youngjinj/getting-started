# CHAR(n) UTF-8 고정 폭 저장 분석 및 개선안

> 분석일: 2026-03-24
> 대상: CHAR 타입의 디스크/네트워크/XASL 저장 방식

---

## 1. 현재 동작: CHAR(n) UTF-8 = n * 4 바이트 고정

### 1.1 크기 계산 경로

`STR_SIZE` 매크로 (`src/object/object_primitive.c:122-124`):
```c
#define STR_SIZE(prec, codeset)                                    \
     (((codeset) == INTL_CODESET_RAW_BITS) ? ((prec+7)/8) :       \
      INTL_CODESET_MULT (codeset) * (prec))
```

`INTL_CODESET_MULT` (`src/base/intl_support.h:77-79`):
```c
#define INTL_CODESET_MULT(codeset)                                 \
    (((codeset) == INTL_CODESET_UTF8) ? INTL_UTF8_MAX_CHAR_SIZE :  \
     ((codeset) == INTL_CODESET_KSC5601_EUC) ? 3 : 1)
```

`INTL_UTF8_MAX_CHAR_SIZE` (`src/base/locale_lib_common.h:35`):
```c
#define INTL_UTF8_MAX_CHAR_SIZE  4
```

**결과**: `CHAR(10) UTF-8 = STR_SIZE(10, UTF8) = 4 * 10 = 40바이트`

### 1.2 Codeset별 CHAR(10) 크기

| Codeset | INTL_CODESET_MULT | CHAR(10) 크기 |
|---|---|---|
| UTF-8 | 4 | 40바이트 |
| EUC-KR (KSC5601) | 3 | 30바이트 |
| RAW_BYTES (ISO-8859) | 1 | 10바이트 |

### 1.3 모든 계층에서 고정 크기 적용

| 계층 | 함수 | 파일:라인 | 동작 |
|---|---|---|---|
| 속성 분류 | `or_attribute.is_fixed = 1` | `object_representation_sr.c:2559` | CHAR는 고정 폭 영역 배치 |
| 레코드 할당 | `tp_domain_disk_size()` | `object_domain.c:10865` | STR_SIZE 바이트 고정 반환 |
| 디스크 기록 크기 | `mr_data_lengthval_char()` | `object_primitive.c:11562` | STR_SIZE 반환 |
| 디스크 기록 | `mr_writeval_char_internal()` | `object_primitive.c:11623` | STR_SIZE까지 공백 패딩 |
| 디스크 읽기 | `mr_readval_char_internal()` | `object_primitive.c:11723` | STR_SIZE 바이트 읽기 |
| 네트워크 전송 | `or_pack_db_value()` → 동일 함수 | `object_representation.c:5534` | STR_SIZE 바이트 전송 |
| XASL 직렬화 | `or_db_value_size()` → 동일 함수 | `object_representation.c:5545` | STR_SIZE 바이트 포함 |

### 1.4 디스크 기록 상세 (`mr_writeval_char_internal`)

`src/object/object_primitive.c:11623-11706`:

```c
src_precision = db_value_precision (value);
src_length = db_get_string_size (value);          // 실제 바이트 수
packed_length = STR_SIZE (src_precision, codeset); // 항상 고정 크기

rc = or_put_data (buf, src, src_length);           // 실제 데이터 기록
pad = packed_length - src_length;
if (pad)
  {
    int i;
    for (i = src_length; i < packed_length; i++)
      {
        rc = or_put_byte (buf, (int) ' ');         // 1바이트씩 공백 패딩
      }
  }
```

**예시**: CHAR(10) UTF-8에 "abc" 저장 시
- `src_length` = 3 (실제 데이터)
- `packed_length` = 40 (STR_SIZE)
- **37번의 `or_put_byte` 루프** 실행

---

## 2. 다른 DB와의 비교

### 2.1 CHAR(10) UTF-8에 "가나다" 저장 시

```
CUBRID:    |가나다                                 |  = 40바이트
            9B 데이터 + 31B 바이트 단위 공백 패딩

MySQL:     |가나다       |  = 16바이트
            9B 데이터 + 7B 문자 단위 공백 패딩

Oracle:    |가나다       |  = 16바이트
            9B 데이터 + 7B 문자 단위 공백 패딩

PG:        [varlena hdr]|가나다       |  = 20바이트
            4B 헤더 + 9B 데이터 + 7B 문자 단위 공백 패딩
```

### 2.2 핵심 차이

| | CUBRID | MySQL/Oracle | PostgreSQL |
|---|---|---|---|
| 패딩 기준 | **바이트** (최악 케이스) | **문자** (실제 글자 수) | **문자** (varlena 구조) |
| CHAR(10) 크기 | 항상 40B | 10~40B (내용 따라) | 14~44B (varlena hdr 포함) |
| 레코드 내 위치 | 고정 offset | 가변 | 가변 |
| 장점 | O(1) 필드 접근 | 공간 효율 | 공간 효율, CHAR=VARCHAR |
| 낭비율 (ASCII) | 75% | 0% | 0% |
| 낭비율 (한글) | 25% | 0% | 0% |

### 2.3 PostgreSQL 특이사항

PG는 CHAR(n)을 내부적으로 **VARCHAR(n)과 동일한 varlena 구조**로 저장한다.
파싱/최적화/실행이 같은 backend 프로세스 내에서 일어나므로
고정 offset 접근의 이점이 없고, 가변 길이가 자연스럽다.

PG 소스 (`src/backend/utils/adt/varchar.c`) 주석:
> *"CHAR is not a fixed-length type in the traditional sense..."*

---

## 3. 즉시 적용 가능한 개선: or_put_byte 루프 → memset

레코드 호환성을 깨지 않고도, 패딩 성능을 개선할 수 있다.

### 3.1 현재 코드

`src/object/object_primitive.c:11660-11668`:
```c
pad = packed_length - src_length;
if (pad)
  {
    int i;
    for (i = src_length; i < packed_length; i++)
      {
        rc = or_put_byte (buf, (int) ' ');
      }
  }
```

`or_put_byte` (`src/base/object_representation.h:1610-1616`):
```c
STATIC_INLINE int
or_put_byte (OR_BUF * buf, int num)
{
  assert (buf->ptr + OR_BYTE_SIZE <= buf->endptr);
  OR_PUT_BYTE (buf->ptr, num);
  buf->ptr += OR_BYTE_SIZE;
  return NO_ERROR;
}
```

**문제**: 매 바이트마다 함수 호출 + assert + ptr 증가.
CHAR(10) UTF-8에 "abc" 저장 시 **37번** 반복.
CHAR(255) UTF-8에 "abc" 저장 시 **1017번** 반복.

### 3.2 개선안

```c
pad = packed_length - src_length;
if (pad)
  {
    assert (buf->ptr + pad <= buf->endptr);
    memset (buf->ptr, ' ', pad);
    buf->ptr += pad;
  }
```

- `memset`은 CPU SIMD 명령어로 최적화됨 (glibc)
- 경계 체크 1회, memcpy 계열 1회로 완료
- **레코드 포맷 변경 없음, 완전 호환**

---

## 4. 장기 개선: 문자 단위 패딩 (레코드 비호환)

레코드 호환성을 깬다는 전제로, CHAR를 문자 단위 패딩으로 전환하는 변경.

### 4.1 목표

```
현재: CHAR(10) UTF-8 "가나다" → 9B + 31B 패딩 = 40B (바이트 기준)
목표: CHAR(10) UTF-8 "가나다" → 9B + 7B 패딩  = 16B (문자 기준)
```

CHAR(10)의 바이트 크기가 내용에 따라 **10~40바이트로 가변**이 되므로,
heap 레코드에서 **fixed → variable로 전환**해야 한다.

### 4.2 변경 지점

#### (1) 속성 분류: fixed → variable

`src/base/object_representation_sr.c:2555-2565`:

CHAR(UTF-8)를 variable 영역에 배치하도록 변경.

`src/object/object_domain.c:10865` — `tp_domain_disk_size()`:

```c
// 현재: CHAR는 항상 고정 크기 반환
// 변경: codeset multiplier > 1이면 가변으로 취급
if (domain->type->get_id () == DB_TYPE_CHAR
    && INTL_CODESET_MULT (TP_DOMAIN_CODESET (domain)) > 1)
  {
    return -1;  // variable-length
  }
```

#### (2) 디스크 기록 크기 계산

`src/object/object_primitive.c:11562` — `mr_data_lengthval_char()`:

```c
// 현재
packed_length = STR_SIZE (src_precision, codeset);  // 항상 40B

// 변경: 실제 문자 수 기반 패딩
intl_char_count (src, src_size, codeset, &char_count);
pad_chars = src_precision - char_count;
packed_length = src_size + pad_chars;  // 실제 바이트 + 부족한 공백 문자 수
```

#### (3) 디스크 기록 (공백 패딩)

`src/object/object_primitive.c:11623` — `mr_writeval_char_internal()`:

```c
// 현재: STR_SIZE까지 바이트 단위 공백 패딩 (or_put_byte 루프)
// 변경: 문자 수 기준 공백 패딩
or_put_data (buf, src, src_length);
if (pad_chars > 0)
  {
    memset (buf->ptr, ' ', pad_chars);  // ASCII 공백은 1바이트
    buf->ptr += pad_chars;
  }
```

#### (4) 디스크 읽기

`src/object/object_primitive.c:11723` — `mr_readval_char_internal()`:

```c
// 현재: STR_SIZE 고정 바이트 읽기
mem_length = STR_SIZE (domain->precision, codeset);
or_advance (buf, mem_length);

// 변경: variable 영역에서 길이 헤더를 먼저 읽고 해당 바이트만 읽기
```

#### (5) 인덱스 레이아웃

`src/object/object_primitive.c` — `mr_index_writeval_char()` / `mr_index_readval_char()`:

인덱스 키도 동일하게 문자 단위 패딩으로 변경 필요.

#### (6) 네트워크 / XASL

`or_pack_db_value` → `mr_data_writeval_char()` 호출하므로,
위 변경이 적용되면 네트워크 전송과 XASL 직렬화도 **자동으로 줄어든다**.
추가 변경 불필요.

### 4.3 변경 파일 요약

| 파일 | 함수 | 변경 내용 |
|---|---|---|
| `src/object/object_domain.c` | `tp_domain_disk_size()` | CHAR(UTF-8) → 가변 반환 |
| `src/base/object_representation_sr.c` | 속성 분류 로직 | CHAR → variable 영역 배치 |
| `src/object/object_primitive.c` | `mr_data_lengthval_char()` | 문자 수 기반 크기 계산 |
| `src/object/object_primitive.c` | `mr_writeval_char_internal()` | 문자 단위 공백 패딩 |
| `src/object/object_primitive.c` | `mr_readval_char_internal()` | variable 영역 읽기 대응 |
| `src/object/object_primitive.c` | `mr_data_lengthmem_char()` | 메모리 크기도 가변 |
| `src/object/object_primitive.c` | `mr_index_writeval_char()` | 인덱스 키도 문자 단위 |
| `src/object/object_primitive.c` | `mr_index_readval_char()` | 인덱스 읽기 대응 |

### 4.4 주의사항

- **기존 DB 파일과 비호환** — 업그레이드 시 `unloaddb` → `loaddb` 필요
- **비교 연산** — `mr_cmpval_char`는 이미 문자 단위 비교이므로 변경 불필요
- **ASCII 전용 DB** — `INTL_CODESET_MULT == 1`인 경우 기존과 동일 (변경 영향 없음)
- **NCHAR 타입** — CHAR와 동일 구조이므로 같은 변경 필요

### 4.5 기대 효과

| 시나리오 | 현재 크기 | 변경 후 | 절감률 |
|---|---|---|---|
| CHAR(10) UTF-8, ASCII 데이터 | 40B | 10B | **75%** |
| CHAR(10) UTF-8, 한글 데이터 | 40B | 16B | **60%** |
| CHAR(10) UTF-8, 이모지 데이터 | 40B | 40B | 0% |
| CHAR(255) UTF-8, 짧은 ASCII | 1020B | 255B | **75%** |

디스크 공간, 네트워크 전송량, 버퍼풀 효율 모두 개선.
