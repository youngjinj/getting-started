#!/bin/bash
#
# clock_coarse_csql_demo.sh
#
# CLOCK_REALTIME_COARSE 해상도 문제 데모
# csql elapsed time이 0 또는 ~4ms 배수로만 나옴
#
# 사용법:
#   bash clock_coarse_csql_demo.sh <dbname> [반복횟수]

DB=${1:?사용법: $0 <dbname> [반복횟수]}
N=${2:-100}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  CLOCK_REALTIME_COARSE 해상도 문제 데모                     ║"
echo "║  csql elapsed time이 0 또는 ~4ms 배수로만 찍힘              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 테이블 준비
cat <<'SQL' | csql -u dba "$DB" >/dev/null 2>&1
DROP TABLE IF EXISTS clock_demo;
CREATE TABLE clock_demo (id INT PRIMARY KEY, val VARCHAR(100), grp INT);
INSERT INTO clock_demo
SELECT ROWNUM, 'val_' || LPAD(CAST(ROWNUM AS VARCHAR), 5, '0'), MOD(ROWNUM, 10)
FROM db_class a, db_class b WHERE ROWNUM <= 1000;
COMMIT;
SQL

echo "DB: $DB, 반복: $N 회, 테이블: 1000행"
echo "쿼리: SELECT /*+ parallel(0) */ * FROM clock_demo ORDER BY val LIMIT 50"
echo ""

# 하나의 csql 세션에서 N회 반복
{
    for i in $(seq 1 $N); do
        echo "SELECT /*+ parallel(0) */ * FROM clock_demo ORDER BY val LIMIT 50;"
    done
} | csql -u dba "$DB" 2>/dev/null > clock_demo_output_$$.txt

grep -oP 'selected\. \(\K[0-9]+\.[0-9]+' clock_demo_output_$$.txt > clock_demo_times_$$.txt

total=$(wc -l < clock_demo_times_$$.txt)

echo "  elapsed time 분포 ($total 회):"
echo ""
printf "  %14s  %6s  %s\n" "elapsed (sec)" "횟수" ""
printf "  %14s  %6s  %s\n" "--------------" "------" "---"

sort clock_demo_times_$$.txt | uniq -c | sort -rn | while read cnt key; do
    pct=$((total > 0 ? cnt * 100 / total : 0))
    bar=$(printf '%*s' $((pct / 2)) '' | tr ' ' '#')
    printf "  %14s  %4d회  (%2d%%) %s\n" "$key" "$cnt" "$pct" "$bar"
done

echo ""
echo "  → 0.001000, 0.002000, 0.003000 같은 값이 있는지 확인."
echo "     없으면 4ms 미만 정밀도가 없다는 증거."
echo ""
echo "  ※ statdump 오버플로우는 NTP가 ms 단위로 뒤로 보정할 때 발생."
echo "     테스트 환경에서는 재현 어려움. 운영 서버 실제 사례:"
echo ""
echo "     Snapshot 3: 51000"
echo "     Snapshot 4: 3548512608093174  ← NTP 보정 시점"
echo "     Snapshot 5: 3548512608118174  ← 이후 영구 오염"
echo ""
echo "  수정 (1줄): src/base/tsc_timer.c:96"
echo "    - clock_gettime(CLOCK_REALTIME_COARSE, &ts);"
echo "    + clock_gettime(CLOCK_MONOTONIC, &ts);"
echo ""

rm -f clock_demo_output_$$.txt clock_demo_times_$$.txt
