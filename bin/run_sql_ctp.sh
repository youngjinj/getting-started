#/bin/bash

SCENARIO_ROOT="${HOME}/CTP/conf/sql.conf"

SCENARIO_DIR_ARRAY=(									\
#	'scenario=${HOME}/cubrid-testcases/sql'						\
	'scenario=${HOME}/cubrid-testcases/sql/_01_object'				\
	'scenario=${HOME}/cubrid-testcases/sql/_02_user_authorization'			\
	'scenario=${HOME}/cubrid-testcases/sql/_03_object_oriented'			\
	'scenario=${HOME}/cubrid-testcases/sql/_04_operator_function'			\
	'scenario=${HOME}/cubrid-testcases/sql/_06_manipulation'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_07_misc'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_08_javasp'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_09_64bit'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_10_connect_by'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_11_codecoverage'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_12_mysql_compatibility'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_13_issues'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_14_mysql_compatibility_2'		\
#	'scenario=${HOME}/cubrid-testcases/sql/_15_fbo'					\
#	'scenario=${HOME}/cubrid-testcases/sql/_16_index_enhancement'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_17_sql_extension2'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_18_index_enhancement_qa'		\
#	'scenario=${HOME}/cubrid-testcases/sql/_19_apricot'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_22_news_service_mysql_compatibility'	\
#	'scenario=${HOME}/cubrid-testcases/sql/_23_apricot_qa'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_24_aprium_qa'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_25_features_844'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_26_features_920'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_27_banana_qa'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_28_features_930'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_29_CTE_recursive'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_29_recovery'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_30_banana_pie_qa'			\
#	'scenario=${HOME}/cubrid-testcases/sql/_31_cherry'				\
#	'scenario=${HOME}/cubrid-testcases/sql/_32_damson'				\
)

for SCENARIO_DIR in "${SCENARIO_DIR_ARRAY[@]}"; do
	sed -i 's/^\(scenario=.*\)$/#\ \1/' -i ${SCENARIO_ROOT}
	sed -i "s/^#\ \(${SCENARIO_DIR//\//\\/}\)$/\1/" ${SCENARIO_ROOT}

	nohup ctp.sh sql &
	mv nohup.out $(echo ${SCENARIO_DIR} | awk -F '/' '{print $NF}').out
	wait
done
