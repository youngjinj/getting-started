# CUBRID-11.0.0.0248-b53ae4a-Linux.x86_64
CUBRID=/home/cubrid/CUBRID
CUBRID_DATABASES=$CUBRID/databases
if [ "x${LD_LIBRARY_PATH}x" = xx ]; then
  LD_LIBRARY_PATH=$CUBRID/lib
else
  LD_LIBRARY_PATH=$CUBRID/lib:$LD_LIBRARY_PATH
fi
SHLIB_PATH=$LD_LIBRARY_PATH
LIBPATH=$LD_LIBRARY_PATH
PATH=$CUBRID/bin:$PATH
export CUBRID
export CUBRID_DATABASES
export LD_LIBRARY_PATH
export SHLIB_PATH
export LIBPATH
export PATH

LIB=$CUBRID/lib

if [ -f /etc/redhat-release ];then
	OS=$(cat /etc/system-release-cpe | cut -d':' -f'3-3')
elif [ -f /etc/os-release ];then
	OS=$(cat /etc/os-release | egrep "^ID=" | cut -d'=' -f2-2)
fi

case $OS in
	fedoraproject)
		if [ ! -h /lib64/libncurses.so.5 ] && [ ! -h $LIB/libncurses.so.5 ];then
			ln -s /lib64/libncurses.so.6 $LIB/libncurses.so.5
			ln -s /lib64/libform.so.6 $LIB/libform.so.5
			ln -s /lib64/libtinfo.so.6 $LIB/libtinfo.so.5
		fi
		;;
	centos)
		if [ ! -h /lib64/libncurses.so.5 ] && [ ! -h $LIB/libncurses.so.5 ];then
			ln -s /lib64/libncurses.so.6 $LIB/libncurses.so.5
			ln -s /lib64/libform.so.6 $LIB/libform.so.5
			ln -s /lib64/libtinfo.so.6 $LIB/libtinfo.so.5
		fi
		;;
	ubuntu)
		if [ ! -h /lib/x86_64-linux-gnu/libncurses.so.5 ] && [ ! -h $LIB/libncurses.so.5 ];then
			ln -s /lib/x86_64-linux-gnu/libncurses.so.6 $LIB/libncurses.so.5
			ln -s /lib/x86_64-linux-gnu/libform.so.6 $LIB/libform.so.5
			ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 $LIB/libtinfo.so.5
		fi
		;;
	debian)
		if [ ! -h /lib/x86_64-linux-gnu/libncurses.so.5 ] && [ ! -h $LIB/libncurses.so.5 ];then
			ln -s /lib/x86_64-linux-gnu/libncurses.so.6 $LIB/libncurses.so.5
			ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 $LIB/libtinfo.so.5
			ln -s /usr/lib/x86_64-linux-gnu/libform.so.6 $LIB/libform.so.5
		fi
		;;
esac
