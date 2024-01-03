drop table if exists t1, t2;

create table t1 (c1 int, c2 varchar (40), c3 numeric (20, 10), c4 varchar (40));
insert into t1
select
  rownum % 1000, md5 (rownum % 100), (rownum % 10) * 1.1, md5 (rownum)
from
  table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) a (c),
  table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) b (c),
  table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) c (c),
  table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) d (c),
  table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) e (c),
  table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) f (c)
-- limit 300000;
limit 100000;

create table t2 (c1 int, c2 varchar (40), c3 numeric (20, 10), c4 varchar (40), c5 varchar);
create index i1 on t2 (c1, c2, c3, c4);
insert into t2 select c1, c2, c3, c4, md5 ('0') from t1;
insert into t2 select c1, c2, c3, c4, md5 ('1') from t1;
insert into t2 select c1, c2, c3, c4, md5 ('2') from t1;

update statistics on all classes with fullscan;
