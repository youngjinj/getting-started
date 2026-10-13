drop table if exists t100;
create table t100 (c1 int, index i1 (c1));
insert into t100 select c from dummy where c <= 1000000 order by random ();
