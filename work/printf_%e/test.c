#include <stdio.h>
#include <string.h>

int main ()
{
  char name_copy[65] = { '\0' };
  char *name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  name_copy[63] = '3';
  name_copy[64] = '\0';
  printf ("%.15e\n\n", 5.7400000000000002);
  memcpy (name_copy, name, 60);
  memcpy (name_copy + 60, "...", 4);
  // name_copy[64] = '\0';
  printf ("%s\n", name_copy);
  printf ("%c\n", name_copy[63]);
}
