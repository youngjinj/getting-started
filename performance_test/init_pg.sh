# set -x

# pg_ctl -D /home/youngjinj/pgsql/data stop

pg_ctl -D /home/youngjinj/pgsql/data -l /home/youngjinj/pgsql/logfile start

dropdb test

createdb test

psql test -f init_pg.sql

pg_ctl -D /home/youngjinj/pgsql/data stop
