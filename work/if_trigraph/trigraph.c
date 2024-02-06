#include <stdio.h>
#include <string.h>

int main(int argc, char* argv[])
{
	char *c = argv[1];
	char *r;

	r = (strlen (c) == 1) ? "len: 1" : "none";

	printf ("%s\n", r);

	return 0;
}
