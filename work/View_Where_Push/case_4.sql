/* case 4: Push, No Index */

drop table if exists t1;
drop table if exists t2;
drop table if exists t3;

create table t1 (t1_c1 int primary key, t1_c2 varchar, t1_c3 datetime);
create table t2 (t2_c1 int primary key, t2_c2 varchar, t2_c3 datetime);
create table t3 (t3_c1 int primary key, t3_c2 varchar, t3_c3 datetime);

insert into t1 select rownum, sys_guid(), sysdatetime from db_class a, db_class b, db_class c, db_class d, db_class e limit 100000;
insert into t2 select rownum, sys_guid(), sysdatetime from db_class a, db_class b, db_class c, db_class d, db_class e limit 100000;
insert into t3 select rownum, sys_guid(), sysdatetime from db_class a, db_class b, db_class c, db_class d, db_class e limit 100000;

drop view if exists v1;
create or replace view v1 (v1_c1, v1_c2, v1_c3) as
select nvl(t1_c1, -1), nvl(t1_c2, ''), to_char(t1_c3, 'YYYY-MM-DD HH24:MI:SS.FF') from t1
union all select nvl(t2_c1, -1), nvl(t2_c2, ''), to_char(t2_c3, 'YYYY-MM-DD HH24:MI:SS.FF') from t2
union all select nvl(t3_c1, -1), nvl(t3_c2, ''), to_char(t3_c3, 'YYYY-MM-DD HH24:MI:SS.FF') from t3

set optimization level 513;
set trace on;

select /*+ recompile */ * from v1 where v1_c1 = 1;

/*

Query stmt: (Rewritten query:)

select v1.v1_c1, v1.v1_c2, v1.v1_c3
from (
  (
    select (nvl(v1.t1_c1, -1)), (nvl(v1.t1_c2, '')), ( to_char(v1.t1_c3, 'YYYY-MM-DD HH24:MI:SS.FF')) from t1 v1 where ((nvl(v1.t1_c1, -1))=1)
    union all select (nvl(v1.t2_c1, -1)), (nvl(v1.t2_c2, '')), ( to_char(v1.t2_c3, 'YYYY-MM-DD HH24:MI:SS.FF')) from t2 v1 where ((nvl(v1.t2_c1, -1))=1)
  )
  union all select (nvl(v1.t3_c1, -1)), (nvl(v1.t3_c2, '')), ( to_char(v1.t3_c3, 'YYYY-MM-DD HH24:MI:SS.FF')) from t3 v1 where ((nvl(v1.t3_c1, -1))=1)
) v1 (v1_c1, v1_c2, v1_c3)

*/
