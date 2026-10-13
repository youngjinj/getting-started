drop table if exists dummy;
create table dummy (c int);
insert into dummy
  with recursive cte (n) as (
      select 1
      union all
      select n + 1 from cte where n < 2000
    )
  select rownum from cte a, cte b, cte c limit 1000000;
