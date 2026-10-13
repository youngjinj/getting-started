drop table if exists t1, t2;

create table t1 (c1 int, index i1 (c1));
insert into t1 values (1);

create table t2 (c1 int, c2 int, index i1 (c1, c2));
insert into t2
  select 1, rownum from db_class a, db_class b, db_class c, db_class d, db_class e limit 12000;
 
update statistics on t1, t2 with fullscan;
