#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main ()
{
  char name[] = "dba.t1";
  char *owner_name = NULL;
  char *class_name = NULL;
  char *save_token = NULL;

  owner_name = strdup (name);
  class_name = strchr (owner_name, '.');
  *class_name++ = '\0';

  printf ("owner_name: %s, class_name: %s\n", owner_name, class_name);

  free (owner_name);

  return 0;
}
