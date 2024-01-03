#!/bin/bash

cubrid service stop

sed -i /^demodb/d $CUBRID/databases/databases.txt
rm -rf $CUBRID/databases/demodb
rm -rf $CUBRID/databases/demodb_*
