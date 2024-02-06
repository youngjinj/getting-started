#include <stdio.h>

#include "cas_cci.h"

static int test2_cci_schema_info (char *user_name, T_CCI_SCH_TYPE type, char *class_name, char *attr_name, int pattern_flag);

int main (int argc, char *argv[])
{
  test2_cci_schema_info ("dba", CCI_SCH_TRIGGER, "dba.test1", NULL, 0); 
}

static int
test2_cci_schema_info (char *user_name, T_CCI_SCH_TYPE type, char *class_name, char *attr_name, int pattern_flag)
{
  T_CCI_ERROR cci_error;
  T_CCI_COL_INFO *cci_col_info;
  T_CCI_CUBRID_STMT cci_stmt_type;
  char *buffer;
  int con_id = 0, cci_request = 0, cci_retval = 0, cci_ind = 0;
  int col_count = 0;
  int i;

  con_id = cci_connect ("localhost", 30000, "demodb", user_name, "");
  if (con_id < 0)
    {
      printf ("%s(%d): cci_connect fail.\n", __FILE__, __LINE__);
      return -1;
    }

  printf ("first\n");
  cci_request = cci_schema_info (con_id, type, class_name, attr_name, pattern_flag, &cci_error);
  if (cci_request < 0)
    {
      printf ("%s(%d): cci_schema_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  cci_col_info = cci_get_result_info (cci_request, &cci_stmt_type, &col_count);
  if (!cci_col_info)
    {
      printf ("%s(%d): cci_get_result_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  while (1)
    {
      cci_retval = cci_cursor (cci_request, 1, CCI_CURSOR_CURRENT, &cci_error);
      if (cci_retval == CCI_ER_NO_MORE_DATA)
        {
          break;
        }

      if (cci_retval < 0)
        {
          printf ("%s(%d): cci_cursor fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
          goto handle_error;
        }

      cci_retval = cci_fetch (cci_request, &cci_error);
      if (cci_retval < 0)
        {
          printf ("%s(%d): cci_fetch fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
          goto handle_error;
        }

      for (i = 1; i <= col_count; i++)
        {
          if (i == 1)
            {
              printf("  ");
            }
          else
            {
              printf(" | ");
            }

          cci_retval = cci_get_data (cci_request, i, CCI_A_TYPE_STR, &buffer, &cci_ind);
          if (cci_retval < 0)
            {
              printf( "%s(%d): cci_get_data fail.\n", __FILE__, __LINE__);
              goto handle_error;
            }

          printf("%s", buffer);
        }

      printf("\n");
    }

  cci_retval = cci_close_req_handle (cci_request);
  if (cci_retval < 0)
    {
      printf ("%s(%d): cci_close_req_handle fail.", __FILE__, __LINE__);
      goto handle_error;
    }

  printf ("second\n");
  cci_request = cci_schema_info (con_id, type, class_name, attr_name, pattern_flag, &cci_error);
  if (cci_request < 0)
    {
      printf ("%s(%d): cci_schema_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  cci_col_info = cci_get_result_info (cci_request, &cci_stmt_type, &col_count);
  if (!cci_col_info)
    {
      printf ("%s(%d): cci_get_result_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  while (1)
    {
      cci_retval = cci_cursor (cci_request, 1, CCI_CURSOR_CURRENT, &cci_error);
      if (cci_retval == CCI_ER_NO_MORE_DATA)
        {
          break;
        }

      if (cci_retval < 0)
        {
          printf ("%s(%d): cci_cursor fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
          goto handle_error;
        }

      cci_retval = cci_fetch (cci_request, &cci_error);
      if (cci_retval < 0)
        {
          printf ("%s(%d): cci_fetch fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
          goto handle_error;
        }

      for (i = 1; i <= col_count; i++)
        {
          if (i == 1)
            {
              printf("  ");
            }
          else
            {
              printf(" | ");
            }

          cci_retval = cci_get_data (cci_request, i, CCI_A_TYPE_STR, &buffer, &cci_ind);
          if (cci_retval < 0)
            {
              printf( "%s(%d): cci_get_data fail.\n", __FILE__, __LINE__);
              goto handle_error;
            }

          printf("%s", buffer);
        }

      printf("\n");
    }

  cci_retval = cci_close_req_handle (cci_request);
  if (cci_retval < 0)
    {
      printf ("%s(%d): cci_close_req_handle fail.", __FILE__, __LINE__);
      goto handle_error;
    }

  printf ("third\n");
  cci_request = cci_schema_info (con_id, type, class_name, attr_name, pattern_flag, &cci_error);
  if (cci_request < 0)
    {
      printf ("%s(%d): cci_schema_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  cci_col_info = cci_get_result_info (cci_request, &cci_stmt_type, &col_count);
  if (!cci_col_info)
    {
      printf ("%s(%d): cci_get_result_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  while (1)
    {
      cci_retval = cci_cursor (cci_request, 1, CCI_CURSOR_CURRENT, &cci_error);
      if (cci_retval == CCI_ER_NO_MORE_DATA)
        {
          break;
        }

      if (cci_retval < 0)
        {
          printf ("%s(%d): cci_cursor fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
          goto handle_error;
        }

      cci_retval = cci_fetch (cci_request, &cci_error);
      if (cci_retval < 0)
        {
          printf ("%s(%d): cci_fetch fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
          goto handle_error;
        }

      for (i = 1; i <= col_count; i++)
        {
          if (i == 1)
            {
              printf("  ");
            }
          else
            {
              printf(" | ");
            }

          cci_retval = cci_get_data (cci_request, i, CCI_A_TYPE_STR, &buffer, &cci_ind);
          if (cci_retval < 0)
            {
              printf( "%s(%d): cci_get_data fail.\n", __FILE__, __LINE__);
              goto handle_error;
            }

          printf("%s", buffer);
        }

      printf("\n");
    }

  cci_retval = cci_close_req_handle (cci_request);
  if (cci_retval < 0)
    {
      printf ("%s(%d): cci_close_req_handle fail.", __FILE__, __LINE__);
      goto handle_error;
    }

  cci_retval = cci_disconnect (con_id, &cci_error);
  if (cci_retval < 0)
    {
      printf( "%s(%d): cci_disconnect fail. (%d)", __FILE__, __LINE__, cci_error.err_code);
      goto handle_error;
    }

  return 0;

handle_error:
  if (cci_request > 0)
    {
      cci_close_req_handle (cci_request);
    }

  if (con_id > 0)
    {
      cci_disconnect (con_id, &cci_error);
    }

  return -1;
}
