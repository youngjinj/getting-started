#!/bin/bash

# alternatives --config java
# alternatives --config javac

export JDK_HOME=/usr/lib/jvm/java
export JAVA_HOME=$JDK_HOME
export PATH=$JAVA_HOME/bin:$PATH
export CLASSPATH=.:$CUBRID/jdbc/cubrid_jdbc.jar
export LD_LIBRARY_PATH=$JAVA_HOME/jre/lib/amd64:$JAVA_HOME/jre/lib/amd64/server:$LD_LIBRARY_PATH
