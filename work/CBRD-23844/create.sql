drop table if exists t1;
create table t1 (c1 varchar, c2 bigint, unique index (c1, c2));
insert into t1 values ('A', 1);
insert into t1 values ('B', 2);
