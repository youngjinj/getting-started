drop table if exists tab_a, tab_b;
create table tab_a (col1 varchar(100), col2 varchar(100));
create table tab_b (col1 varchar(100), col2 varchar(100));
insert into tab_a select to_char(rownum mod 100) col1, to_char(rownum) col2 from table({0,1,2,3,4,5,6,7,8,9}) a, table({0,1,2,3,4,5,6,7,8,9}) b,table({0,1,2,3,4,5,6,7,8,9}) c,table({0,1,2,3,4,5,6,7,8,9}) d,table({0,1,2,3,4,5,6,7,8,9})  e,table({0,1,2,3,4,5,6,7,8,9})  f limit 10;
insert into tab_b select to_char(rownum mod 100) col1, to_char(rownum) col2 from table({0,1,2,3,4,5,6,7,8,9}) a, table({0,1,2,3,4,5,6,7,8,9}) b,table({0,1,2,3,4,5,6,7,8,9}) c,table({0,1,2,3,4,5,6,7,8,9}) d,table({0,1,2,3,4,5,6,7,8,9})  e,table({0,1,2,3,4,5,6,7,8,9})  f limit 10;
create index idx on tab_a(col1,col2);
create index idx on tab_b(col1,col2);
create or replace view v1 as select col1, rank() OVER(PARTITION BY col1 ORDER BY col2) col2 from tab_b;
