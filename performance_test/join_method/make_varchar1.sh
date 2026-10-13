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
  select rownum from cte a, cte b, cte c limit 1000000;
EOF

for ((i=200000; i<=1000000; i+=200000)); do

cat << EOF > create_${i:0:-4}.sql
drop table if exists t${i:0:-4};
create table t${i:0:-4} (c1 varchar, index i1 (c1));
insert into t${i:0:-4} select md5 (c) from dummy where c <= ${i} order by random ();
EOF

cat << EOF > nl_${i:0:-4}.sql
select /*+ recompile ordered use_nl */ count (a.c1)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1;
EOF

cat << EOF > nl_cnt_only_${i:0:-4}.sql
select /*+ recompile ordered use_nl */ count (*)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1;
EOF

cat << EOF > sm_${i:0:-4}.sql
select /*+ recompile ordered use_merge */ count (a.c1)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1;
EOF

cat << EOF > sm_cnt_only_${i:0:-4}.sql
select /*+ recompile ordered use_merge */ count (*)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1;
EOF

cat << EOF > hash_${i:0:-4}.sql
select /*+ recompile ordered use_hash */ count (a.c1)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1;
EOF

cat << EOF > hash_cnt_only_${i:0:-4}.sql
select /*+ recompile ordered use_hash */ count (*)
from t${i:0:-4} a, t${i:0:-4} b
where a.c1 = b.c1;
EOF

done
