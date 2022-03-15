#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main ()
{
  char name[] = "dba.t1";
  char *name_copy = NULL;
  char *owner_name = NULL;
  char *class_name = NULL;
  char *save_token = NULL;
  clock_t begin, end;

  begin = clock ();

  name_copy = strdup (name);
  owner_name = strtok_r (name_copy, ".", &save_token);
  class_name = strtok_r (NULL, ".", &save_token);

  printf ("owner_name: %s, class_name: %s\n", owner_name, class_name);

  free (name_copy);

  end = clock ();

  printf ("%f\n", (double) end - begin);

  return 0;
}
