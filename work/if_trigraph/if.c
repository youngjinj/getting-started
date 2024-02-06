#include <stdio.h>
#include <string.h>

int main(int argc, char* argv[])
{
	char *c = argv[1];
	char *r;

	if (strlen (c) == 1)
		r = "len: 1";
	else
		r = "none";

	printf ("%s\n", r);

	return 0;
}
