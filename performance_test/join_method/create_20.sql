drop table if exists t20;
create table t20 (c1 int, index i1 (c1));
insert into t20 select c from dummy where c <= 200000 order by random ();
