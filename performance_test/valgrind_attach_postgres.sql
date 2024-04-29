drop table if exists t1, t2;

create table t1 (c1 int, c2 int, dummy1 varchar, dummy2 date);
insert into t1
select ta.c1, tb.c1, '__t1_' || md5 (cast ((row_number() over()) as varchar)), now()
from generate_series(1,1000) as ta (c1),
     generate_series(1,100) as tb (c1);

create table t2 (c1 int, c2 int, c3 int, dummy1 varchar, dummy2 date);
create index i1 on t2 (c1, c2, c3);
insert into t2
select ta.c1, tb.c1, tc.c1 % 2, '__t2_' || md5 (cast ((row_number() over()) as varchar)), now()
from generate_series(1,1000) as ta (c1),
     generate_series(1,100) as tb (c1),
     generate_series(1,20) as tc (c1);

vacuum full analyze;
