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

if [ ! -z $CLASSPATH ]; then
	CLASSPATH=.:$CUBRID/jdbc/cubrid_jdbc.jar:$CUBRID/java/lib/cubrid-jdbc-11.0.0.0248.jar:$CLASSPATH
else
	CLASSPATH=.:$CUBRID/jdbc/cubrid_jdbc.jar:$CUBRID/java/lib/cubrid-jdbc-11.0.0.0248.jar
fi

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
