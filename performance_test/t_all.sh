#!/bin/bash

T_COUNT=16
T_UNIT_COUNT=8

# T_VERSION_LIST=("8.4.4.19002" "9.2.30.0004" "9.3.6.0002" "9.3.9.1602" "10.1.7.7819" "10.2.12.8947" "11.0.11.0365" "11.2.5.0779" "11.3.0.0975" "12.0.0.1512" "11.3.0.0991")
# T_VERSION_LIST=("9.3.9.1602" "10.2.12.8947" "11.0.11.0365" "11.2.5.0779" "11.3.0.0975" "12.0.0.1512" "11.3.0.0991")
# T_VERSION_LIST=("9.3.9.1602" "10.2.0.8797" "11.0.0.0248" "11.2.0.0658" "11.3.0.1066" "12.0.0.1541" "11.3.0.1082-tobe")
# T_VERSION_LIST=("11.2.0.0658" "11.2.1.0677" "11.2.2.0705" "11.2.3.0730" "11.2.4.0775" "11.2.5.0779")
# T_VERSION_LIST=("9.3.9.1602" "10.2.0.8797" "11.0.0.0248" "11.2.0.0658" "11.3.0.1066" "12.0.0.1541" "11.3.0.1082-tobe" "postgres")
T_VERSION_LIST=("11.4.0.1448-943ea08" "11.4.0.1452-cbdbd0b")
# T_VERSION_LIST=("postgres")

echo "#### All Start. (${T_VERSION_LIST[@]})"

for ((i=1; i<=${T_COUNT}; i++)); do
  echo "#### Unit Start. (${i}/${T_COUNT})"

  T_VERSION_LIST=( $(shuf -e "${T_VERSION_LIST[@]}") )
  printf "%s " "${T_VERSION_LIST[@]}"

  echo ""

  for T_VERSION in ${T_VERSION_LIST[@]}; do
    echo "#### Init. (${T_VERSION})"

    if [ "${T_VERSION}" = "postgres" ]; then
      if [ ${i} -eq 1 ]; then
        ./init_pg.sh
      fi

      sudo sh -c "/usr/bin/echo 3 > /proc/sys/vm/drop_caches"
      sleep 5

      ./t_cs_pg.sh ${T_VERSION} ${T_UNIT_COUNT}
    else
      init_cubrid.sh ${T_VERSION}

      . ${HOME}/cubrid.sh

      cubrid_rel

      T_MAJOR=`echo ${T_VERSION} | cut -d "." -f1`
      
      if [ ${i} -eq 1 ]; then
        if [ ${T_MAJOR} -eq 8 ]; then
          ./init_8.sh
        elif [ ${T_MAJOR} -eq 9 ]; then
          ./init_9.sh
        else
          ./init.sh
        fi
      fi

#      sudo sh -c "/usr/bin/echo 3 > /proc/sys/vm/drop_caches"
#      sleep 5

#      ./t_sa.sh ${T_VERSION} ${T_UNIT_COUNT}

      sudo sh -c "/usr/bin/echo 3 > /proc/sys/vm/drop_caches"
      sleep 5

      ./t_cs.sh ${T_VERSION} ${T_UNIT_COUNT}
    fi
  done
  
  echo "#### Unit End.   (${i}/${T_COUNT})"
done

echo "#### All End.   (${T_VERSION_LIST[@]})"
