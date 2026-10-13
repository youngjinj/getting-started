#!/bin/bash

cat << EOF > create_dummy.sql
drop table if exists dummy;
create table dummy (c int);
insert into dummy
  with recursive cte (n) as (
      select 1
      union all
      select n + 1 from cte where n < 2000
    )
  select rownum from cte a, cte b, cte c limit 3000000;
EOF

for ((i=1000000; i<=1000000; i+=500000)); do

cat << EOF > nl_${i:0:-4}.sql
select /*+ recompile ordered use_nl */ count (*)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1 /* 1/10 */ and a.c2 = b.c2 /* 1/100 */ and a.c3 = b.c3 /* 1/1000 */ and a.c4 = b.c4;
EOF

cat << EOF > sm_${i:0:-4}.sql
select /*+ recompile ordered use_merge */ count (*)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1 /* 1/10 */ and a.c2 = b.c2 /* 1/100 */ and a.c3 = b.c3 /* 1/1000 */ and a.c4 = b.c4;
EOF

done

for ((i=500000; i<=3000000; i+=500000)); do

cat << EOF > create_${i:0:-4}.sql
drop table if exists t${i:0:-4};
create table t${i:0:-4} (c1 varchar, c2 varchar, c3 varchar, c4 varchar, index i1 (c1, c2, c3, c4), index i2 (c4));
insert into t${i:0:-4} select mod (rownum, 10), mod (rownum, 100), mod (rownum, 1000), rownum from dummy where c <= ${i} order by random ();
EOF

cat << EOF > hash_${i:0:-4}.sql
select /*+ recompile ordered use_hash */ count (*)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1 /* 1/10 */ and a.c2 = b.c2 /* 1/100 */ and a.c3 = b.c3 /* 1/1000 */ and a.c4 = b.c4;
EOF

done
