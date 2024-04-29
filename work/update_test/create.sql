drop table if exists t1;

create table t1 (
  c1 varchar (100) primary key,
  c2 varchar (100),
  c3 varchar (100),
  c4 varchar (100),
  c5 varchar (100),
  c6 varchar (100),
  c7 varchar (100),
  c8 varchar (100),
  c9 varchar (100),
  c10 varchar (100),
  c11 varchar (100),
  c12 varchar (100),
  c13 varchar (100),
  c14 varchar (100),
  c15 varchar (100),
  c16 varchar (100),
  c17 varchar (100),
  c18 varchar (100),
  c19 varchar (100),
  c20 varchar (100),
  c21 varchar (100),
  c22 varchar (100),
  c23 varchar (100),
  c24 varchar (100),
  c25 varchar (100),
  c26 varchar (100),
  c27 varchar (100),
  c28 varchar (100),
  c29 varchar (100),
  c30 varchar (100)
) reuse_oid;

create index idx1 ON t1 (c2, c3, c4);
create index idx2 ON t1 (c5, c6, c7);
create index idx3 ON t1 (c8, c9, c11);
create index idx4 ON t1 (c12, c13, c14);
create index idx5 ON t1 (c15, c16, c17);
create index idx6 ON t1 (c18, c19, c20);
create index idx7 ON t1 (c21, c22, c23);
create index idx8 ON t1 (c24, c25, c26);
create index idx9 ON t1 (c27, c28, c29);
