drop table if exists t40;
create table t40 (c1 int, index i1 (c1));
insert into t40 select c from dummy where c <= 400000 order by random ();
