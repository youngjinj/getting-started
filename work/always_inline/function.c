#include <stdio.h>
#include <stdbool.h>

typedef struct test_data
{
  char *a;
  char *b;
  int c;
} TEST_DATA;

bool is_abc (TEST_DATA * td)
{
  if (td == NULL)
  {
    return false;
  }

  return td->c == 1;
}

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
