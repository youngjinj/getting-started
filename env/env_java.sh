#!/bin/bash

# alternatives --config java
# alternatives --config javac

JDK_HOME=/usr/lib/jvm/java
JAVA_HOME=$JDK_HOME

if [ ! -z $PATH ]; then
	PATH=$JAVA_HOME/bin:$PATH
else
	PATH=$JAVA_HOME/bin
fi

for CUBRID_JDBC in `ls $CUBRID/java/lib/*`; do
	if [ ! -z $CLASSPATH ]; then
		if [ `echo $CLASSPATH | grep $CUBRID_JDBC | wc -l` -eq 0 ]; then
			CLASSPATH=$CUBRID_JDBC:$CLASSPATH
		else
			CLASSPATH=$CUBRID_JDBC
		fi
	else
		CLASSPATH=$CUBRID_JDBC
	fi
done

CLASSPATH=.:$CUBRID/jdbc/cubrid_jdbc.jar:$CLASSPATH

if [ ! -z $LD_LIBRARY_PATH ]; then
	LD_LIBRARY_PATH=$JAVA_HOME/jre/lib/amd64:$JAVA_HOME/jre/lib/amd64/server:$LD_LIBRARY_PATH
else
	LD_LIBRARY_PATH=$JAVA_HOME/jre/lib/amd64:$JAVA_HOME/jre/lib/amd64/server
fi

export JDK_HOME
export JAVA_HOME
export PATH
export CLASSPATH
export LD_LIBRARY_PATH
