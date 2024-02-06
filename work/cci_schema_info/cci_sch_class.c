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
  conn = cci_connect ("localhost", 33000, "demodb", "u1", "");
  if (conn < 0) {
    fprintf (stdout, "(%s, %d) ERROR : cci_connect \n", __FILE__, __LINE__);
    goto _END;
  }

  req = cci_get_db_version (conn, db_ver, sizeof(db_ver));
  if (req < 0) {
    fprintf (stdout, "(%s, %d) ERROR : cci_get_db_version \n", __FILE__, __LINE__);
    goto _END;
  }
  fprintf (stdout, "DB Version is %s\n", db_ver);

  /* cci_sch_class */
  req = cci_schema_info(conn, CCI_SCH_CLASS, "t1", NULL, CCI_CLASS_NAME_PATTERN_MATCH , &cci_error);
  if (req < 0)
  {
    fprintf (stdout, "(%s, %d) ERROR : %s [%d] \n", __FILE__, __LINE__, cci_error.err_msg, cci_error.err_code);
    goto _END;
  }

  res = cci_cursor (req, 1, CCI_CURSOR_FIRST, &cci_error);
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
      strcat (query_result_buffer, "\n");

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
