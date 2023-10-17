queue=("11.2.0.0658" "11.2.1.0677" "11.2.2.0705" "11.2.3.0730" "11.2.4.0775" "11.2.5.0779")

queue=( $(shuf -e "${queue[@]}") )
printf "%s " "${queue[@]}"
echo ""

while [ ${#queue[@]} -gt 0 ]
do
	iostat_=`iostat -c -y 1 1 | grep -A1 avg-cpu | grep -v avg-cpu`
	user_=`echo $iostat_ | awk '$3<0.5{print $1}'`
	system_=`echo $iostat_ | awk '$3<0.5{print $3}'`
	iowait_=`echo $iostat_ | awk '$4<0.1{print $4}'`

	while [ -z $system_ ] || [ -z $iowait_ ]  
	do
		sleep 2
		echo "sleep 2"

		iostat_=`iostat -c -y 1 1 | grep -A1 avg-cpu | grep -v avg-cpu`
		user_=`echo $iostat_ | awk '$3<0.5{print $1}'`
		system_=`echo $iostat_ | awk '$3<0.5{print $3}'`
		iowait_=`echo $iostat_ | awk '$4<0.1{print $4}'`
	done

	echo $user_ $system_ $iowait_

	echo "Queue: ${queue[0]}, length: ${#queue[@]}"
csql -u dba demodb -C -c "select /*+ ordered */ tb.c9 from t1 ta, t2 tb where ta.c1 = tb.c1 and ta.c2 = tb.c2 and tb.c3 = 1 limit 99999, 1" | tail -1 | awk -F '\\(|\\)' '{print $2}' | awk '{print $1}'

	# Pop the first element (a path)
	path=${queue[0]}
	queue=("${queue[@]:1}")
done
