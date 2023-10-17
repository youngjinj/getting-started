drop table if exists t1, t2;

create table t1 (c1 int, c2 varchar (40), c3 numeric (20, 10), c4 varchar (40));
insert into t1
select
  t.c % 1000, md5 (cast (t.c % 100 as varchar)), (t.c % 10) *1.1, md5 (cast (t.c as varchar))
from
--  generate_series (1, 300000) as t (c);
  generate_series (1, 100000) as t (c);

create table t2 (c1 int, c2 varchar (40), c3 numeric (20, 10), c4 varchar (40), c5 varchar);
create index i1 on t2 (c1, c2, c3, c4);
insert into t2 select c1, c2, c3, c4, md5 ('0') from t1;
insert into t2 select c1, c2, c3, c4, md5 ('1') from t1;
insert into t2 select c1, c2, c3, c4, md5 ('2') from t1;

vacuum full analyze;

/*
create extension pgstattuple;
select * from pgstatindex('i1');
*/
