#include <stdio.h>

int function (int c);

int main ()
{
  int c;
  int s = 0;

  printf("Input count : ");
  scanf("%d", &c);
  printf("INput count : %d\n", c);

  s = function(c) + function(c) + function(c) + function(c) + function(c);

  printf("Sum : %d\n", s);

  return 0;
}

int
function (int c)
{
  int s = 0;

  for (int i = 0; i < c; i++)
    {
      s += i;
    }

  return s;
}
