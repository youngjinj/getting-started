#include <stdio.h>
#include <string.h>

int main ()
{
  char *src ="123456";
  char dest[20];

  printf ("sizeof: %d\n", sizeof (dest));
  strcpy (dest, src);
  printf ("dest = %s\n", dest);
}
