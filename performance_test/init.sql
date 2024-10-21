drop table if exists t1;

create table t1 (c1 int, c2 int);
create index i1 on t1 (c1, c2);
insert into t1
  select rownum, 0
  from
    table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) a (c),
    table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) b (c),
    table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) c (c),
    table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) d (c),
    table ({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) e (c)
  limit 100000;

update statistics on t1 with fullscan;
