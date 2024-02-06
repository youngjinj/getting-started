#include <stdio.h>
#include <cas_cci.h>
char *cci_client_name = "test";
int main (int argc, char *argv[])
{
    int con = 0, req = 0, col_count = 0, res, ind, i;
    T_CCI_ERROR error;
    T_CCI_COL_INFO *res_col_info;
    T_CCI_CUBRID_STMT stmt_type;
    char *buffer, db_ver[16];
    printf("Program started!\n");
    if ((con=cci_connect("localhost", 30000, "demodb", "public", ""))<0) {
        printf( "%s(%d): cci_connect fail\n", __FILE__, __LINE__);
        return -1;
    }

    if ((res=cci_get_db_version(con, db_ver, sizeof(db_ver)))<0) {
        printf( "%s(%d): cci_get_db_version fail\n", __FILE__, __LINE__);
        goto handle_error;
    }
    printf("DB Version is %s\n",db_ver);
    if ((req=cci_prepare(con, "select * from event limit 1", 0,&error))<0) {
        if (req < 0) {
            printf( "%s(%d): cci_prepare fail(%d)\n", __FILE__, __LINE__,error.err_code);
        }
        goto handle_error;
    }
    printf("Prepare ok!(%d)\n",req);
    res_col_info = cci_get_result_info(req, &stmt_type, &col_count);
    if (!res_col_info) {
        printf( "%s(%d): cci_get_result_info fail\n", __FILE__, __LINE__);
        goto handle_error;
    }

    printf("Result column information\n"
           "========================================\n");
    for (i=1; i<=col_count; i++) {
        printf("name:%s  type:%d(precision:%d scale:%d)\n",
            CCI_GET_RESULT_INFO_NAME(res_col_info, i),
            CCI_GET_RESULT_INFO_TYPE(res_col_info, i),
            CCI_GET_RESULT_INFO_PRECISION(res_col_info, i),
            CCI_GET_RESULT_INFO_SCALE(res_col_info, i));
    }
    printf("========================================\n");
    if ((res=cci_execute(req, 0, 0, &error))<0) {
        if (req < 0) {
            printf( "%s(%d): cci_execute fail(%d)\n", __FILE__, __LINE__,error.err_code);
        }
        goto handle_error;
    }

    while (1) {
        res = cci_cursor(req, 1, CCI_CURSOR_CURRENT, &error);
        if (res == CCI_ER_NO_MORE_DATA) {
            printf("Query END!\n");
            break;
        }
        if (res<0) {
            if (req < 0) {
                printf( "%s(%d): cci_cursor fail(%d)\n", __FILE__, __LINE__,error.err_code);
            }
            goto handle_error;
        }

        if ((res=cci_fetch(req, &error))<0) {
            if (res < 0) {
                printf( "%s(%d): cci_fetch fail(%d)\n", __FILE__, __LINE__,error.err_code);
            }
            goto handle_error;
        }

        for (i=1; i<=col_count; i++) {
            if ((res=cci_get_data(req, i, CCI_A_TYPE_STR, &buffer, &ind))<0) {
                printf( "%s(%d): cci_get_data fail\n", __FILE__, __LINE__);
                goto handle_error;
            }
            printf("%s \t|", buffer);
        }
        printf("\n");
    }
    if ((res=cci_close_req_handle(req))<0) {
        printf( "%s(%d): cci_close_req_handle fail", __FILE__, __LINE__);
       goto handle_error;
    }


    // req = cci_schema_info(con, CCI_SCH_CLASS, "t2", NULL, 1, &error);
    // req = cci_schema_info(con, CCI_SCH_ATTRIBUTE, "db_class", "class_name", 1, &error);
    if (req < 0) {
      printf ("error\n");
      goto handle_error;
    }

    res_col_info = cci_get_result_info(req, &stmt_type, &col_count);
    if (!res_col_info) {
        printf( "%s(%d): cci_get_result_info fail\n", __FILE__, __LINE__);
        goto handle_error;
    }

    while (1) {
        res = cci_cursor(req, 1, CCI_CURSOR_CURRENT, &error);
        if (res == CCI_ER_NO_MORE_DATA) {
            printf("Query END!\n");
            break;
        }
        if (res<0) {
            if (req < 0) {
                printf( "%s(%d): cci_cursor fail(%d)\n", __FILE__, __LINE__,error.err_code);
            }
            goto handle_error;
        }

        if ((res=cci_fetch(req, &error))<0) {
            if (res < 0) {
                printf( "%s(%d): cci_fetch fail(%d)\n", __FILE__, __LINE__,error.err_code);
            }
            goto handle_error;
        }

        for (i=1; i<=col_count; i++) {
            if ((res=cci_get_data(req, i, CCI_A_TYPE_STR, &buffer, &ind))<0) {
                printf( "%s(%d): cci_get_data fail\n", __FILE__, __LINE__);
                goto handle_error;
            }
            printf("%s \t|", buffer);
        }
        printf("\n");
    }
    if ((res=cci_close_req_handle(req))<0) {
        printf( "%s(%d): cci_close_req_handle fail", __FILE__, __LINE__);
       goto handle_error;
    }


    if ((res=cci_disconnect(con, &error))<0) {
        if (res < 0) {
            printf( "%s(%d): cci_disconnect fail(%d)", __FILE__, __LINE__,error.err_code);
        }
        goto handle_error;
    }
    printf("Program ended!\n");
    return 0;

    handle_error:
    if (req > 0)
        cci_close_req_handle(req);
    if (con > 0)
        cci_disconnect(con, &error);
    printf("Program failed!\n");
    return -1;
}
