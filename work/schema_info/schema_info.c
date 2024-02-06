#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cas_cci.h"

int main (int argc, char *argv[])
{
  int conn = 0, req = 0, col_count = 0, res = 0, i, ind;
  char *data, query_result_buffer[1024], db_ver[16];
  T_CCI_ERROR cci_error;
  T_CCI_COL_INFO *col_info;
  T_CCI_CUBRID_STMT cmd_type;
  
  /* connect */
  conn = cci_connect ("192.168.2.204", 33000, "demodb", "u3", "");
  if (conn < 0) {
    fprintf (stdout, "(%s, %d) ERROR : cci_connect \n", __FILE__, __LINE__);
    goto _END;
  }

  /* cci_get_db_version */
  req = cci_get_db_version (conn, db_ver, sizeof(db_ver));
  if (req < 0) {
    fprintf (stdout, "(%s, %d) ERROR : cci_get_db_version \n", __FILE__, __LINE__);
    goto _END;
  }
  fprintf (stdout, "DB Version is %s\n", db_ver);

  /* cci_schema_info */
  req = cci_schema_info(conn, CCI_SCH_CLASS_PRIVILEGE, "u3.t3", "%", 1, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_CLASS_PRIVILEGE, "t3", "%", 0, &cci_error);
  // req = cci_schema_info (conn, CCI_SCH_TRIGGER, "public.tt1", NULL, 1, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_PRIMARY_KEY, "test1", NULL, CCI_CLASS_NAME_PATTERN_MATCH, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_TRIGGER, "dba.tt%", NULL, CCI_CLASS_NAME_PATTERN_MATCH, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_CLASS, NULL, NULL, CCI_CLASS_NAME_PATTERN_MATCH, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_CLASS, "u2.t3", NULL, CCI_CLASS_NAME_PATTERN_MATCH, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_CLASS_PRIVILEGE, "db\\_a%", "%", 1, &cci_error);
  // req = cci_schema_info(conn, CCI_SCH_QUERY_SPEC, "db_class", "class_name", 1, &cci_error);
  if (req < 0)
  {
    fprintf (stdout, "(%s, %d) ERROR : %s [%d] \n", __FILE__, __LINE__, cci_error.err_msg, cci_error.err_code);
    goto _END;
  }

  col_info = cci_get_result_info (req, &cmd_type, &col_count);
  if (!col_info) {
    fprintf (stdout, "(%s, %d) ERROR : cci_get_result_info \n", __FILE__, __LINE__);
    goto _END;
  }

  /* cci_cursor */
  res = cci_cursor (req, 1, CCI_CURSOR_CURRENT, &cci_error);
  if (res == CCI_ER_NO_MORE_DATA)
  {
    goto _END;
  }
  if (res < 0)
  {
    fprintf (stdout, "(%s, %d) ERROR : %s [%d] \n", __FILE__, __LINE__, cci_error.err_msg, cci_error.err_code);
    goto _END;
  }

  while (1)
  {
      res = cci_fetch (req, &cci_error);
      if (res < 0)
      {
          fprintf (stdout, "(%s, %d) ERROR : %s [%d] \n", __FILE__, __LINE__, cci_error.err_msg, cci_error.err_code);
          goto _END;
      }

      for (i = 1; i <= col_count; i++)
      {
          if ((res = cci_get_data (req, i, CCI_A_TYPE_STR, &data, &ind)) < 0)
          {
              goto _END;
          }
          if (ind != -1)
          {
              strcat (query_result_buffer, data);
              strcat (query_result_buffer, "|");
          }
          else
          {
              strcat (query_result_buffer, "NULL|");
          }
      }
      // strcat (query_result_buffer, "\n");

      res = cci_cursor (req, 1, CCI_CURSOR_CURRENT, &cci_error);
      if (res == CCI_ER_NO_MORE_DATA)
      {
          goto _END;
      }
      if (res < 0)
        {
          fprintf (stdout, "(%s, %d) ERROR : %s [%d] \n", __FILE__, __LINE__, cci_error.err_msg, cci_error.err_code);
          goto _END;
        }
  }

_END:
  if (req > 0)
  {
    cci_close_req_handle (req);
  }

  if (conn > 0)
  {
    res = cci_disconnect (conn, &cci_error);
  }

  if (res < 0)
  {
    fprintf (stdout, "(%s, %d) ERROR : %s [%d] \n", __FILE__, __LINE__, cci_error.err_msg, cci_error.err_code);
  }

  fprintf (stdout, "Result : %s\n", query_result_buffer);

  return 0;
}
