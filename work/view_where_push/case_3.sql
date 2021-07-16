/* case 3: Push */

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
select t1_c1, t1_c2, t1_c3 from t1
union all select t2_c1, t2_c2, t2_c3 from t2
union all select t3_c1, t3_c2, t3_c3 from t3

set optimization level 513;
set trace on;

select /*+ recompile */ * from v1 where v1_c1 = 1;

/*

Query stmt: (Rewritten query:)

select v1.v1_c1, v1.v1_c2, v1.v1_c3
from (
  (
    select v1.t1_c1, v1.t1_c2, v1.t1_c3 from t1 v1 where (v1.t1_c1= ?:1 )
    union all select v1.t2_c1, v1.t2_c2, v1.t2_c3 from t2 v1 where (v1.t2_c1= ?:2 )
  )
  union all select v1.t3_c1, v1.t3_c2, v1.t3_c3 from t3 v1 where (v1.t3_c1= ?:3 )
) v1 (v1_c1, v1_c2, v1_c3)

*/
