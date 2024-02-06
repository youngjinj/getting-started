#include <stdio.h>
#include <string>

int main ()
{
  std::string str(1, '.');
  printf ("sizeof: %d\n", sizeof ("."));
  printf ("sizeof: %d\n", str.size());
}
