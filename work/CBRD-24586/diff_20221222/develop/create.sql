create user u0 groups dba;
create user u0_1 groups u0;
create user u1;
create user u1_1 groups u1;
create user u2;
create user u2_1 groups u2;
create user u3 groups u1_1, u2_1;
create user u3_1 groups u3;
create user u4;
create user u5;
create user u6;




set system parameters 'create_table_reuseoid=n';



call login ('u0') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u0 {dba} > t1';
create view v1 as select * from t1 as t comment 'u0 {dba} > v1';
create table t2_r (c1 int) comment 'u0 {dba} > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u0 {dba} > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u0 {dba} > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u0 {dba} > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u0 {dba} > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u0 {dba} > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u0 {dba} > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u0 {dba} > t3_d (domain)';
create table t3_s (c1 int) comment 'u0 {dba} > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u0 {dba} > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u0 {dba} > t4';
create index i1 on t4 (c1, c2) comment 'u0 {dba} > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u0 {dba} > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u0 {dba} > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u0 {dba} > t5';
create table t5_c (c1 int unique, c2 int) comment 'u0 {dba} > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u0 {dba} > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u0 {dba} > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u0 {dba} > r_d (delete)';
create function j0 (arg1 int comment 'u0 {dba} > j0 > arg1 (in)', arg2 out int comment 'u0 {dba} > j0 > arg2 (out)') return int
  as language java name 'test.j0(int) return int' comment 'u0 {dba} > j0 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u0 {dba} > s1 (dblink)');



call login ('u0_1') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u0_1 {dba} > t1';
create view v1 as select * from t1 as t comment 'u0_1 {dba} > v1';
create table t2_r (c1 int) comment 'u0_1 {dba} > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u0_1 {dba} > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u0_1 {dba} > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u0_1 {dba} > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u0_1 {dba} > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u0_1 {dba} > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u0_1 {dba} > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u0_1 {dba} > t3_d (domain)';
create table t3_s (c1 int) comment 'u0_1 {dba} > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u0_1 {dba} > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u0_1 {dba} > t4';
create index i1 on t4 (c1, c2) comment 'u0_1 {dba} > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u0_1 {dba} > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u0_1 {dba} > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u0_1 {dba} > t5';
create table t5_c (c1 int unique, c2 int) comment 'u0_1 {dba} > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u0_1 {dba} > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u0_1 {dba} > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u0_1 {dba} > r_d (delete)';
create function j0_1 (arg1 int comment 'u0_1 {dba} > j0_1 > arg1 (in)', arg2 out int comment 'u0_1 {dba} > j0_1 > arg2 (out)') return int
  as language java name 'test.j0(int) return int' comment 'u0_1 {dba} > j0_1 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u0_1 {dba} > s1 (dblink)');



call login ('u1') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u1 > t1';
create view v1 as select * from t1 as t comment 'u1 > v1';
create table t2_r (c1 int) comment 'u1 > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u1 > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u1 > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u1 > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u1 > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u1 > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u1 > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u1 > t3_d (domain)';
create table t3_s (c1 int) comment 'u1 > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u1 > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u1 > t4';
create index i1 on t4 (c1, c2) comment 'u1 > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u1 > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u1 > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u1 > t5';
create table t5_c (c1 int unique, c2 int) comment 'u1 > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u1 > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u1 > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u1 > r_d (delete)';
create function j1 (arg1 int comment 'u1 > j1 > arg1 (in)', arg2 out int comment 'u1 > j1 > arg2 (out)') return int
  as language java name 'Test.j1(int) return int' comment 'u1 > j1 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u1 > s1 (dblink)');




call login ('u1_1') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u1_1 {u1} > t1';
create view v1 as select * from t1 as t comment 'u1_1 {u1} > v1';
create table t2_r (c1 int) comment 'u1_1 {u1} > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u1_1 {u1} > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u1_1 {u1} > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u1_1 {u1} > t2_h (hash)'
 partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u1_1 {u1} > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u1_1 {u1} > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u1_1 {u1} > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u1_1 {u1} > t3_d (domain)';
create table t3_s (c1 int) comment 'u1_1 {u1} > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u1_1 {u1} > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u1_1 {u1} > t4';
create index i1 on t4 (c1, c2) comment 'u1_1 {u1} > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u1_1 {u1} > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u1_1 {u1} > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u1_1 {u1} > t5';
create table t5_c (c1 int unique, c2 int) comment 'u1_1 {u1} > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u1_1 {u1} > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u1_1 {u1} > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u1_1 {u1} > r_d (delete)';
create function j1_1 (arg1 int comment 'u1_1 {u1} > j1_1 > arg1 (in)', arg2 out int comment 'u1_1 {u1} > j1_1 > arg2 (out)') return int
  as language java name 'Test.j1_1(int) return int' comment 'u1_1 {u1} > j1_1 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u1_1 {u1} > s1 (dblink)');




call login ('u2') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u2 > t1';
create view v1 as select * from t1 as t comment 'u2 > v1';
create table t2_r (c1 int) comment 'u2 > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u2 > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u2 > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u2 > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u2 > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u2 > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u2 > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u2 > t3_d (domain)';
create table t3_s (c1 int) comment 'u2 > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u2 > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u2 > t4';
create index i1 on t4 (c1, c2) comment 'u2 > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u2 > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u2 > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u2 > t5';
create table t5_c (c1 int unique, c2 int) comment 'u2 > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u2 > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u2 > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u2 > r_d (delete)';
create function j2 (arg1 int comment 'u2 > j2 > arg1 (in)', arg2 out int comment 'u2 > j2 > arg2 (out)') return int
  as language java name 'Test.j2(int) return int' comment 'u2 > j2 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u2 > s1 (dblink)');




call login ('u2_1') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u2_1 {u2} > t1';
create view v1 as select * from t1 as t comment 'u2_1 {u2} > v1';
create table t2_r (c1 int) comment 'u2_1 {u2} > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u2_1 {u2} > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u2_1 {u2} > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u2_1 {u2} > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u2_1 {u2} > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u2_1 {u2} > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u2_1 {u2} > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u2_1 {u2} > t3_d (domain)';
create table t3_s (c1 int) comment 'u2_1 {u2} > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u2_1 {u2} > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u2_1 {u2} > t4';
create index i1 on t4 (c1, c2) comment 'u2_1 {u2} > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u2_1 {u2} > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u2_1 {u2} > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u2_1 {u2} > t5';
create table t5_c (c1 int unique, c2 int) comment 'u2_1 {u2} > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u2_1 {u2} > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u2_1 {u2} > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u2_1 {u2} > r_d (delete)';
create function j2_1 (arg1 int comment 'u2_1 {u2} > j2_1 > arg1 (in)', arg2 out int comment 'u2_1 {u2} > j2_1 > arg2 (out)') return int
  as language java name 'Test.j2_1(int) return int' comment 'u2_1 {u2} > j2_1 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u2_1 {u2} > s1 (dblink)');




call login ('u3') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) collate euckr_bin) comment 'u3 {u1_1, u2_1} > t1';
create view v1 as select * from t1 as t comment 'u3 {u1_1, u2_1} > v1';
create table t2_r (c1 int) comment 'u3 {u1_1, u2_1} > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u3 {u1_1, u2_1} > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u3 {u1_1, u2_1} > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u3 {u1_1, u2_1} > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u3 {u1_1, u2_1} > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u3 {u1_1, u2_1} > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u3 {u1_1, u2_1} > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u3 {u1_1, u2_1} > t3_d (domain)';
create table t3_s (c1 int) comment 'u3 {u1_1, u2_1} > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u3 {u1_1, u2_1} > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u3 {u1_1, u2_1} > t4';
create index i1 on t4 (c1, c2) comment 'u3 {u1_1, u2_1} > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u3 {u1_1, u2_1} > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u3 {u1_1, u2_1} > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u3 {u1_1, u2_1} > t5';
create table t5_c (c1 int unique, c2 int) comment 'u3 {u1_1, u2_1} > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u3 {u1_1, u2_1} > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u3 {u1_1, u2_1} > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u3 {u1_1, u2_1} > r_d (delete)';
create function j3 (arg1 int comment 'u3 {u1_1, u2_1} > j3 > arg1 (in)', arg2 out int comment 'u3 {u1_1, u2_1} > j3 > arg2 (out)') return int
  as language java name 'Test.j3(int) return int' comment 'u3 {u1_1, u2_1} > j3 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u3 {u1_1, u2_1} > s1 (dblink)');




call login ('u3_1') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) COLLATE euckr_bin) comment 'u3_1 {u3} > t1';
create view v1 as select * from t1 as t comment 'u3_1 {u3} > v1';
create table t2_r (c1 int) comment 'u3_1 {u3} > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u3_1 {u3} > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u3_1 {u3} > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u3_1 {u3} > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u3_1 {u3} > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u3_1 {u3} > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u3_1 {u3} > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u3_1 {u3} > t3_d (domain)';
create table t3_s (c1 int) comment 'u3_1 {u3} > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u3_1 {u3} > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u3_1 {u3} > t4';
create index i1 on t4 (c1, c2) comment 'u3_1 {u3} > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u3_1 {u3} > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u3_1 {u3} > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u3_1 {u3} > t5';
create table t5_c (c1 int unique, c2 int) comment 'u3_1 {u3} > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u3_1 {u3} > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u3_1 {u3} > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u3_1 {u3} > r_d (delete)';
create function j3_1 (arg1 int comment 'u3_1 {u3} > j3_1 > arg1 (in)', arg2 out int comment 'u3_1 {u3} > j3_1 > arg2 (out)') return int
  as language java name 'Test.j3_1(int) return int' comment 'u3_1 {u3} > j3_1 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u3_1 {u3} > s1 (dblink)');




call login ('u4') on class db_user;
create table t1 class attribute (a1 int) (c1 int, c2 varchar(255) COLLATE euckr_bin) comment 'u4 > t1';
create view v1 as select * from t1 as t comment 'u4 > v1';
create table t2_r (c1 int) comment 'u4 > t2_r (range)' 
  partition by range (c1) (
      partition p0 values less than (0) comment 'u4 > t2_r > p0 (range)',
      partition p1 values less than maxvalue comment 'u4 > t2_r > p1 (range)'
    );
create table t2_h (c1 int) comment 'u4 > t2_h (hash)'
  partition by hash (c1) partitions 2;
create table t2_l (c1 int) comment 'u4 > t2_l (list)' 
  partition by list (c1) (
      partition p0 values in (0) comment 'u4 > t2_l > p0 (list)',
      partition p1 values in (1) comment 'u4 > t2_l > p1 (list)'
    );
create table t3_d (c1 int) comment 'u4 > t3_d (domain)';
create table t3_s (c1 int) comment 'u4 > t3_s (super)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method_s';
create table t3 as subclass of t3_s (c1 int, c3 t3_d, c4 sequence of t3_d) comment 'u4 > t3 (inherit)'
  method class m0(sequence of t3_d) t3_d function f0, m1(varchar(255)) int function f1
  file '$home/method'
  inherit class m0 of t3_s as m0_s, m1 of t3_s as m1_s, c1 of t3_s as c1_s;
create table t4 (c1 int primary key, c2 int, c3 varchar(255)) comment 'u4 > t4';
create index i1 on t4 (c1, c2) comment 'u4 > t4 > i1 (index)' invisible;
create index i2 on t4 (c2) where c2 = 0 comment 'u4 > t4 > i2 (filter)';
create index i3 on t4 (replace (c3, ' ', '')) comment 'u4 > t4 > i3 (function)';
create table t5 (c1 int unique, c2 int) comment 'u4 > t5';
create table t5_c (c1 int unique, c2 int) comment 'u4 > t5_c (copy )';
create trigger r_i after insert on t5 execute insert into t5_c values (obj.c1, obj.c2) comment 'u4 > r_i (insert)';
create trigger r_u after update on t5 (c2) execute update t5_c set c2 = obj.c2 where c1 = obj.c1 comment 'u4 > r_u (update)';
create trigger r_d before delete on t5 execute reject comment 'u4 > r_d (delete)';
create function j4 (arg1 int comment 'u4 > j4 > arg1 (in)', arg2 out int comment 'u4 > j4 > arg2 (out)') return int
  as language java name 'Test.j4(int) return int' comment 'u4 > j4 (function)';
create server s1 (host='localhost', port=33000, dbname=demodb, user=dba, comment='u4 > s1 (dblink)');

grant select on t1 to u5 with grant option;
grant select on v1 to u5 with grant option;
grant select on t2_r to u5 with grant option;
grant select on t2_h to u5 with grant option;
grant select on t2_l to u5 with grant option;
grant select on t3 to u5 with grant option;
grant select on t4 to u5 with grant option;
grant select on t5 to u5 with grant option;
grant select on t5_c to u5 with grant option;




call login ('u5') on class db_user;
create synonym t1 for u4.t1 comment 'u5 > t1 (t1 of u4)';
create synonym v1 for u4.v1 comment 'u5 > v1 (v1 of u4)';
create synonym t2_r for u4.t2_r comment 'u5 > t2_r (t2_r of u4)';
create synonym t2_h for u4.t2_h comment 'u5 > t2_h (t2_h of u4)';
create synonym t2_l for u4.t2_l comment 'u5 > t2_l (t2_l of u4)';
create synonym t3 for u4.t3 comment 'u5 > t3 (t3 of u4)';
create synonym t4 for u4.t4 comment 'u5 > t4 (t4 of u4)';
create synonym t5 for u4.t5 comment 'u5 > t5 (t5 of u4)';
create synonym t5_c for u4.t5_c comment 'u5 > t5_c (t5_c of u4)';

grant select on t1 to u6;
grant select on v1 to u6;
grant select on t2_r to u6;
grant select on t2_h to u6;
grant select on t2_l to u6;
grant select on t3 to u6;
grant select on t4 to u6;
grant select on t5 to u6;
grant select on t5_c to u6;




call login ('u6') on class db_user;
/* None. */
