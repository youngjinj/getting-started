#!/bin/bash

TARGET_PATH=$1

if [ -z ${TARGET_PATH} ]; then
        TARGET_PATH=${PWD}
fi

if [ ! -e ${TARGET_PATH}/.gitignore ]; then
        touch ${TARGET_PATH}/.gitignore
fi

if [ `grep Youngjinj ${TARGET_PATH}/.gitignore | wc -l` != 0 ]; then
        exit
fi

cat <<EOF >> ${TARGET_PATH}/.gitignore

## Youngjinj
build/
.vscode/
cscope.files
cscope.out
tags
csql.access
csql.err

## sql
sql/**/*.sql
sql/**/*.result
sql/**/*.answer

## medium
medium/**/*.sql
medium/**/*.result
medium/**/*.answer

## sql cases
# sql/_01_object/cases/**/*.sql
# sql/_02_user_authorization/cases/**/*.sql
# sql/_03_object_oriented/cases/**/*.sql
# sql/_04_operator_function/cases/**/*.sql
# sql/_06_manipulation/cases/**/*.sql
# sql/_07_misc/cases/**/*.sql
# sql/_08_javasp/cases/**/*.sql
# sql/_09_64bit/cases/**/*.sql
# sql/_10_connect_by/cases/**/*.sql
# sql/_11_codecoverage/cases/**/*.sql
# sql/_12_mysql_compatibility/cases/**/*.sql
# sql/_13_issues/cases/**/*.sql
# sql/_14_mysql_compatibility_2/cases/**/*.sql
# sql/_15_fbo/cases/**/*.sql
# sql/_16_index_enhancement/cases/**/*.sql
# sql/_17_sql_extension2/cases/**/*.sql
# sql/_18_index_enhancement_qa/cases/**/*.sql
# sql/_19_apricot/cases/**/*.sql
# sql/_22_news_service_mysql_compatibility/cases/**/*.sql
# sql/_23_apricot_qa/cases/**/*.sql
# sql/_24_aprium_qa/cases/**/*.sql
# sql/_25_features_844/cases/**/*.sql
# sql/_26_features_920/cases/**/*.sql
# sql/_27_banana_qa/cases/**/*.sql
# sql/_28_features_930/cases/**/*.sql
# sql/_29_CTE_recursive/cases/**/*.sql
# sql/_29_recovery/cases/**/*.sql
# sql/_30_banana_pie_qa/cases/**/*.sql
# sql/_31_cherry/cases/**/*.sql
# sql/_32_damson/cases/**/*.sql
# sql/_33_elderberry/cases/**/*.sql

## sql result
# sql/_01_object/cases/**/*.result
# sql/_02_user_authorization/cases/**/*.result
# sql/_03_object_oriented/cases/**/*.result
# sql/_04_operator_function/cases/**/*.result
# sql/_06_manipulation/cases/**/*.result
# sql/_07_misc/cases/**/*.result
# sql/_08_javasp/cases/**/*.result
# sql/_09_64bit/cases/**/*.result
# sql/_10_connect_by/cases/**/*.result
# sql/_11_codecoverage/cases/**/*.result
# sql/_12_mysql_compatibility/cases/**/*.result
# sql/_13_issues/cases/**/*.result
# sql/_14_mysql_compatibility_2/cases/**/*.result
# sql/_15_fbo/cases/**/*.result
# sql/_16_index_enhancement/cases/**/*.result
# sql/_17_sql_extension2/cases/**/*.result
# sql/_18_index_enhancement_qa/cases/**/*.result
# sql/_19_apricot/cases/**/*.result
# sql/_22_news_service_mysql_compatibility/cases/**/*.result
# sql/_23_apricot_qa/cases/**/*.result
# sql/_24_aprium_qa/cases/**/*.result
# sql/_25_features_844/cases/**/*.result
# sql/_26_features_920/cases/**/*.result
# sql/_27_banana_qa/cases/**/*.result
# sql/_28_features_930/cases/**/*.result
# sql/_29_CTE_recursive/cases/**/*.result
# sql/_29_recovery/cases/**/*.result
# sql/_30_banana_pie_qa/cases/**/*.result
# sql/_31_cherry/cases/**/*.result
# sql/_32_damson/cases/**/*.result
# sql/_33_elderberry/cases/**/*.result

## sql answers
# sql/_01_object/answers/**/*.answer
# sql/_02_user_authorization/answers/**/*.answer
# sql/_03_object_oriented/answers/**/*.answer
# sql/_04_operator_function/answers/**/*.answer
# sql/_06_manipulation/answers/**/*.answer
# sql/_07_misc/answers/**/*.answer
# sql/_08_javasp/answers/**/*.answer
# sql/_09_64bit/answers/**/*.answer
# sql/_10_connect_by/answers/**/*.answer
# sql/_11_codecoverage/answers/**/*.answer
# sql/_12_mysql_compatibility/answers/**/*.answer
# sql/_13_issues/answers/**/*.answer
# sql/_14_mysql_compatibility_2/answers/**/*.answer
# sql/_15_fbo/answers/**/*.answer
# sql/_16_index_enhancement/answers/**/*.answer
# sql/_17_sql_extension2/answers/**/*.answer
# sql/_18_index_enhancement_qa/answers/**/*.answer
# sql/_19_apricot/answers/**/*.answer
# sql/_22_news_service_mysql_compatibility/answers/**/*.answer
# sql/_23_apricot_qa/answers/**/*.answer
# sql/_24_aprium_qa/answers/**/*.answer
# sql/_25_features_844/answers/**/*.answer
# sql/_26_features_920/answers/**/*.answer
# sql/_27_banana_qa/answers/**/*.answer
# sql/_28_features_930/answers/**/*.answer
# sql/_29_CTE_recursive/answers/**/*.answer
# sql/_29_recovery/answers/**/*.answer
# sql/_30_banana_pie_qa/answers/**/*.answer
# sql/_31_cherry/answers/**/*.answer
# sql/_32_damson/answers/**/*.answer
# sql/_33_elderberry/answers/**/*.answer

## medium cases
# medium/_01_fixed/cases/**/*.sql
# medium/_02_xtests/cases/**/*.sql
# medium/_03_full_mdb/cases/**/*.sql
# medium/_04_full/cases/**/*.sql
# medium/_05_err_x/cases/**/*.sql
# medium/_06_fulltests/cases/**/*.sql
# medium/_07_mc_dep/cases/**/*.sql
# medium/_08_mc_ind/cases/**/*.sql

## medium result
# medium/_01_fixed/cases/**/*.result
# medium/_02_xtests/cases/**/*.result
# medium/_03_full_mdb/cases/**/*.result
# medium/_04_full/cases/**/*.result
# medium/_05_err_x/cases/**/*.result
# medium/_06_fulltests/cases/**/*.result
# medium/_07_mc_dep/cases/**/*.result
# medium/_08_mc_ind/cases/**/*.result

## medium answers
# medium/_01_fixed/answers/**/*.answer
# medium/_02_xtests/answers/**/*.answer
# medium/_03_full_mdb/answers/**/*.answer
# medium/_04_full/answers/**/*.answer
# medium/_05_err_x/answers/**/*.answer
# medium/_06_fulltests/answers/**/*.answer
# medium/_07_mc_dep/answers/**/*.answer
# medium/_08_mc_ind/answers/**/*.answer
# medium/_01_fixed/answers/**/*.answer3277.answer

EOF
