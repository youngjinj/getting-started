drop table if exists t2;
create table t2 (c1 varchar, c2 varchar, c3 varchar, c4 varchar, c5 varchar, c6 varchar, c7 varchar, c8 varchar, c9 varchar) REUSE_OID;
create index i1 on t2 (c1, c2, c3, c4, c5, c6, c7, c8, c9);
