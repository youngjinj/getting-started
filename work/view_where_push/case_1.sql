/* case 1: No Push */

drop table if exists t1;
drop table if exists t2;
drop table if exists t3;

create table t1 (c1 int primary key, c2 varchar, c3 datetime);
create table t2 (c1 int primary key, c2 varchar, c3 datetime);
create table t3 (c1 int primary key, c2 varchar, c3 datetime);

insert into t1 select rownum, sys_guid(), sysdatetime from db_class a, db_class b, db_class c, db_class d, db_class e limit 100000;
insert into t2 select rownum, sys_guid(), sysdatetime from db_class a, db_class b, db_class c, db_class d, db_class e limit 100000;
insert into t3 select rownum, sys_guid(), sysdatetime from db_class a, db_class b, db_class c, db_class d, db_class e limit 100000;

drop view if exists v1;
create or replace view v1 as
select * from (
  select * from t1
  union all select * from t2
  union all select * from t3
);

set optimization level 513;
set trace on;

select /*+ recompile */ * from v1 where c1 = 1;

/*

Query stmt: (Rewritten query:)

select v1.c1, v1.c2, v1.c3 from v1 v1 (c1, c2, c3) where (v1.c1= ?:0 )

*/
