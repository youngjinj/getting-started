create user user_1st;
create user user_2nd;
create user user_3rd;
create user user_4th;


set system parameters 'create_table_reuseoid=n';


call login ('user_1st') on class db_user;

create table table_1st class attribute (column_1st int) (
    column_1st int primary key comment 'user_1st > table_1st > column_1st',
    column_2nd int comment 'user_1st > table_1st > column_2nd'
  ) comment 'user_1st > table_1st';

create table table_2nd class attribute (column_1st int) (
    column_1st int primary key comment 'user_1st > table_2nd > column_1st',
    column_2nd int comment 'user_1st > table_2nd > column_2nd'
  ) comment 'user_1st > table_2nd';

create view view_1st (
    column_1st comment 'user_1st > view_1st > column_1st',
    column_2nd comment 'user_1st > view_1st > column_2nd'
  )
as select * from table_1st comment 'user_1st > view_1st';

create view view_2nd (
    column_1st comment 'user_1st > view_2nd > column_1st',
    column_2nd comment 'user_1st > view_2nd > column_2nd'
  )
as select * from table_2nd comment 'user_1st > view_2nd';

create table table_3rd (
    column_1st int comment 'user_1st > table_3rd > column_1st'
  ) comment 'user_1st > table_3rd (method)'
  method class method_1st (int) int function funtion_1st,
               method_2nd (varchar(255)) bigint function funtion_2nd
  file '$home/method';

create table table_4th (
    column_1st int comment 'user_1st > table_4th > column_1st'
  ) comment 'user_1st > table_4th (super)';

create table table_5th as subclass of table_4th (
    column_1st int comment 'user_1st > table_5th > column_1st' 
  ) comment 'user_1st > table_5th (inherit)'
  inherit column_1st of table_4th as column_1st_S;

create table table_6th as subclass of table_5th (
    column_1st int comment 'user_1st > table_6th > column_1st' 
  ) comment 'user_1st > table_6th (inherit)'
  inherit column_1st_S of table_5th as column_1st_SS,
          column_1st of table_5th as column_1st_S;

create table table_7th (
    column_1st int comment 'user_1st > table_7th > column_1st'
  ) comment 'user_1st > table_7th (hash)'
  partition by hash (column_1st) partitions 4;

create table table_8th (
    column_1st int primary key comment 'user_1st > table_8th > column_1st (pk)',
    column_2nd int unique comment 'user_1st > table_8th > column_2nd (unique)',
    column_3rd int not null comment 'user_1st > table_8th > column_3rd (not null)',
    column_4th int comment 'user_1st > table_8th > column_4th',
    column_5th int comment 'user_1st > table_8th > column_5th',
    index index_1st (column_3rd, column_4th),
    index index_2nd (column_4th desc)
  ) comment 'user_1st > table_8th';
create reverse index index_3rd on table_8th (column_5th);

create table table_9th (
    column_1st int primary key comment 'user_1st > table_9th > column_1st (pk)',
    column_2nd int references table_8th (column_1st) comment 'user_1st > table_9th > column_2nd (fk)'
  ) comment 'user_1st > table_9th';

create trigger trigger_1st after insert on table_1st
execute insert into table_2nd values (obj.column_1st, obj.column_2nd)
comment 'user_1st > trigger_1st (insert)';

create trigger trigger_2nd after update on table_1st
execute update table_2nd set column_2nd = obj.column_2nd where column_1st = obj.column_1st
comment 'user_1st > trigger_2nd (update)';

create trigger trigger_3rd before delete on table_1st
execute reject
comment 'user_1st > trigger_3rd (delete)';

grant select, insert, update, delete on table_1st to user_3rd;
grant select on table_2nd to user_3rd with grant option;


call login ('user_2nd') on class db_user;

create table table2_1st class attribute (column_1st int) (
    column_1st int primary key comment 'user_2nd > table_1st > column_1st',
    column_2nd int comment 'user_2nd > table_1st > column_2nd'
  ) comment 'user_2nd > table_1st';

create table table2_2nd class attribute (column_1st int) (
    column_1st int primary key comment 'user_2nd > table_2nd > column_1st',
    column_2nd int comment 'user_2nd > table_2nd > column_2nd'
  ) comment 'user_2nd > table_2nd';

create view view2_1st (
    column_1st comment 'user_2nd > view_1st > column_1st',
    column_2nd comment 'user_2nd > view_1st > column_2nd'
  )
as select * from table2_1st comment 'user_2nd > view_1st';

create view view2_2nd (
    column_1st comment 'user_2nd > view_2nd > column_1st',
    column_2nd comment 'user_2nd > view_2nd > column_2nd'
  )
as select * from table2_2nd comment 'user_2nd > view_2nd';

create table table2_3rd (
    column_1st int comment 'user_2nd > table_3rd > column_1st'
  ) comment 'user_2nd > table_3rd (method)'
  method class method_1st (int) int function funtion_1st,
               method_2nd (varchar(255)) bigint function funtion_2nd
  file '$home/method';

create table table2_4th (
    column_1st int comment 'user_2nd > table_4th > column_1st'
  ) comment 'user_2nd > table_4th (super)';

create table table2_5th as subclass of table2_4th (
    column_1st int comment 'user_2nd > table_5th > column_1st' 
  ) comment 'user_2nd > table_5th (inherit)'
  inherit column_1st of table2_4th as column_1st_S;

create table table2_6th as subclass of table2_5th (
    column_1st int comment 'user_2nd > table_6th > column_1st' 
  ) comment 'user_2nd > table_6th (inherit)'
  inherit column_1st_S of table2_5th as column_1st_SS,
          column_1st of table2_5th as column_1st_S;

create table table2_7th (
    column_1st int comment 'user_2nd > table_7th > column_1st'
  ) comment 'user_2nd > table_7th (hash)'
  partition by hash (column_1st) partitions 4;

create table table2_8th (
    column_1st int primary key comment 'user_2nd > table_8th > column_1st (pk)',
    column_2nd int unique comment 'user_2nd > table_8th > column_2nd (unique)',
    column_3rd int not null comment 'user_2nd > table_8th > column_3rd (not null)',
    column_4th int comment 'user_2nd > table_8th > column_4th',
    column_5th int comment 'user_2nd > table_8th > column_5th',
    index index_1st (column_3rd, column_4th),
    index index_2nd (column_4th desc)
  ) comment 'user_2nd > table_8th';
create reverse index index_3rd on table2_8th (column_5th);

create table table2_9th (
    column_1st int primary key comment 'user_2nd > table_9th > column_1st (pk)',
    column_2nd int references table2_8th (column_1st) comment 'user_2nd > table_9th > column_2nd (fk)'
  ) comment 'user_2nd > table_9th';

create trigger trigger2_1st after insert on table2_1st
execute insert into table2_2nd values (obj.column_1st, obj.column_2nd)
comment 'user_2nd > trigger_1st (insert)';

create trigger trigger2_2nd after update on table2_1st
execute update table2_2nd set column_2nd = obj.column_2nd where column_1st = obj.column_1st
comment 'user_2nd > trigger_2nd (update)';

create trigger trigger2_3rd before delete on table2_1st
execute reject
comment 'user_2nd > trigger_3rd (delete)';

grant select, insert, update, delete on table2_1st to user_4th;
grant select on table2_2nd to user_4th with grant option;
