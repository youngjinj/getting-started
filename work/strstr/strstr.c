#include <stdio.h>
#include <string.h>

int main()
{
	if (strstr(NULL, ".") != NULL)
		printf("Not null.\n");
	else
		printf("Null.\n");

	return 0;
}
