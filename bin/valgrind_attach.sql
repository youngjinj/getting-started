drop table if exists t1, t2;

create table t1 (c1 int, c2 int, dummy1 varchar, dummy2 datetime);
insert into t1
select ta.c1, tb.c1, '__t1_' || md5 (rownum), sysdatetime
from (select rownum as c1 from db_class a, db_class b, db_class c limit 1000) as ta,
     (select rownum as c1 from db_class a, db_class b limit 100) as tb;

create table t2 (c1 int, c2 int, c3 int, dummy1 varchar, dummy2 datetime);
create index i1 on t2 (c1, c2, c3);
insert into t2
select ta.c1, tb.c1, tc.c1 % 2, '__t2_' || md5 (rownum), sysdatetime
from (select rownum as c1 from db_class a, db_class b, db_class c limit 1000) as ta,
     (select rownum as c1 from db_class a, db_class b limit 100) as tb,
     (select rownum as c1 from db_class a limit 20) as tc;

update statistics on t1, t2;
