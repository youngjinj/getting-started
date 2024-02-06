#include <stdio.h>
#include <string.h>

#define ARRAY_COUNT 4

void print_binary (int n);

int main ()
{
  char data[ARRAY_COUNT];
  char *ptr = data;
  int i;

  memset (data, 0x00, sizeof (data));

  int mask = (1 << 7);
  print_binary (mask);
  printf ("\n");

  data[0] |= (1 << 7) - 1;
  data[0] |= (1 << 7);
  data[0] &= ~(1 << 4);
  data[1] |= (1 << 4);

  mask = (1 << 8) - 1;
  print_binary (mask);
  printf ("\n");

  mask = 0xFF;
  print_binary (mask);
  printf ("\n");

  for (i = 0; i < ARRAY_COUNT; i++)
    {
      printf ("has_null check index %d.\n", i);
      if (~(*(ptr + i)) & mask)
        {
          printf ("true\n");
          break;
        }
    }

  for (i = 0; i < ARRAY_COUNT; i++)
    {
      printf ("is_null check index %d.\n", i);
      if (!(*(ptr + i) & mask))
        {
	  printf ("true\n");
	  break;
        }
    }

  i = 3; 
  printf ("is_null_with_index check index %d.\n", i);
  if ((*(ptr + (i >> 3))) & (1 << (i & 7)))
    {
      printf ("true\n");
    }

  i = 4;
  printf ("is_null_with_index check index %d.\n", i);
  if ((*(ptr + (i >> 3))) & (1 << (i & 7)))
    {
      printf ("true\n");
    }

  i = 12;
  printf ("is_null_with_index check index %d.\n", i);
  if ((*(ptr + (i >> 3))) & (1 << (i & 7)))
    {
      printf ("true\n");
    }

  for (i = 0; i < ARRAY_COUNT; i++)
    {
      print_binary (data[i]);
      printf (" ");
    }
  printf ("\n");
}

void print_binary (int n)
{
  int mask = 1 << 7;

  while (mask)
    {
      if (mask & n)
        {
	  printf ("1");
        }
      else
        {
	  printf ("0");
        }

      mask = mask >> 1;
    }
}
