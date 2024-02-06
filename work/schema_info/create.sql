create user u1;
create user u2;
create user u3;

call login ('u1') on class db_user;
create table t1 (c1 int primary key, c2 varchar);
create table t2 (c1 int primary key, c2 varchar, c3 varchar);
create table t3 (c1 int primary key, c2 varchar, c3 varchar, c4 varchar);
insert into t1 values (1, 'u1_t1_c1_test');
insert into t2 values (1, 'u1_t2_c1_test', 'u1_t2_c2_test');
insert into t3 values (1, 'u1_t3_c1_test', 'u1_t3_c2_test', 'u1_t3_c3_test');
grant select on t2 to u2;
grant select on t3 to u3;

call login ('u2') on class db_user;
create table t1 (c1 int primary key, c2 varchar);
create table t2 (c1 int primary key, c2 varchar, c3 varchar);
create table t3 (c1 int primary key, c2 varchar, c3 varchar, c4 varchar);
insert into t1 values (1, 'u2_t1_c1_test');
insert into t2 values (1, 'u2_t2_c1_test', 'u2_t2_c2_test');
insert into t3 values (1, 'u2_t3_c1_test', 'u2_t3_c2_test', 'u2_t3_c3_test');
grant select on t3 to u3;


call login ('u3') on class db_user;
create table t1 (c1 int primary key, c2 varchar);
create table t2 (c1 int primary key, c2 varchar, c3 varchar);
create table t3 (c1 int primary key, c2 varchar, c3 varchar, c4 varchar);
insert into t1 values (1, 'u3_t1_c1_test');
insert into t2 values (1, 'u3_t2_c1_test', 'u3_t2_c2_test');
insert into t3 values (1, 'u3_t3_c1_test', 'u3_t3_c2_test', 'u3_t3_c3_test');
