drop table if exists t80;
create table t80 (c1 int, index i1 (c1));
insert into t80 select c from dummy where c <= 800000 order by random ();
