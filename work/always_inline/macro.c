#include <stdio.h>
#include <stdbool.h>

typedef struct test_data
{
  char *a;
  char *b;
  int c;
} TEST_DATA;

#define is_abc(td) ((td) == NULL) ? false : ((td)->c == 1)

int main ()
{
  TEST_DATA td = { "abc", "def", 1 };

  if (is_abc (&td))
  {
    printf ("%s\n", td.a);
  }
  else
  {
    printf ("%s\n", td.b);
  }

  return 0;
}
