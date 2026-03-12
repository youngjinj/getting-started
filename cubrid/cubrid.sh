CUBRID=${HOME}/CUBRID
CUBRID_DATABASES=${CUBRID}/databases

TEMP_LD_LIBRARY_PATH=${CUBRID}/lib:${CUBRID}/cci/lib
TEMP_PATH=${CUBRID}/bin

# LINUX
if [ -n "${LD_LIBRARY_PATH}" ]; then
        if [ `echo ${LD_LIBRARY_PATH} | grep ${TEMP_LD_LIBRARY_PATH} | wc -l` == 0 ]; then
                LD_LIBRARY_PATH=${TEMP_LD_LIBRARY_PATH}:${LD_LIBRARY_PATH}
        fi
# Length of string is zero.
else
        LD_LIBRARY_PATH=${TEMP_LD_LIBRARY_PATH}
fi

# HP-UX
SHLIB_PATH=${LD_LIBRARY_PATH}

# AIX
LIBPATH=${LD_LIBRARY_PATH}

if [ -n "${PATH}" ]; then
        if [ `echo ${PATH} | grep ${TEMP_PATH} | wc -l` == 0 ]; then
                PATH=${TEMP_PATH}:${PATH}
        fi
# Length of string is zero.
else
        PATH=${TEMP_PATH}
fi

export CUBRID
export CUBRID_DATABASES
export LD_LIBRARY_PATH
export SHLIB_PATH
export LIBPATH
export PATH

if [ ! -d $CUBRID_DATABASES ]; then
        mkdir -p $CUBRID_DATABASES
fi

#export TMPDIR=${CUBRID}/tmp
#if [ ! -d ${TMPDIR} ]; then
#        mkdir -p ${TMPDIR}
#fi

#export CUBRID_TMP=${CUBRID}/var/CUBRID_SOCK
#if [ ! -d ${CUBRID_TMP} ]; then
#        mkdir -p ${CUBRID_TMP}
#fi

#
#  tuning setting for glib memory library
#  
#  For more information on environment variables, see https://www.gnu.org/software/libc/manual/html_node/Malloc-Tunable-Parameters.html.
#  (Notice) To using the environment variables below, you should to remove comment them and add them to the export statement.
#
#MALLOC_MMAP_MAX_=65536            # default : 65536
#MALLOC_MMAP_THRESHOLD_=131072     # default : 131072 (128K)
MALLOC_TRIM_THRESHOLD_=0           # default : 131072 (128K)
#MALLOC_ARENA_MAX=                 # default : core * 8
export MALLOC_TRIM_THRESHOLD_

#
# preloading library for another memory library
#
#LD_PRELOAD=/usr/lib64/libjemalloc.so.2
#export LD_PRELOAD

#MALLOC_CONF="dirty_decay_ms:0,muzzy_decay_ms:0"
#export MALLOC_CONF

# export MALLOC_CHECK_=3           # Check Buffer Overflow, Double Free
# export MALLOC_PERTURB_=255       # Check Use-After-Free
