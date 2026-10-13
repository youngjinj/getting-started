drop table if exists t60;
create table t60 (c1 int, index i1 (c1));
insert into t60 select c from dummy where c <= 600000 order by random ();
