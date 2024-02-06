#include <stdio.h>
#include <string.h>

int main()
{
	char name[255] = { '\0' };
	char *dot_name = NULL;
	char *dummy = "redorange";

	char *test31 = "_________1_________2_________31.test";
	char *test32 = "_________1_________2_________312.test";
	char *test33 = "_________1_________2_________3123.test";
	char *test21 = "_________1_________21.";
	char *test22 = "_________1_________212.test";
	char *test41 = "_________1_________2_________3_________41.test";
	char *test09 = ".123456789.test";
	char *testnull = NULL;

	char *dot31 = memchr (test31, '.', 32);
	char *dot32 = memchr (test32, '.', 32);
	char *dot33 = memchr (test33, '.', 32);
	char *dot21 = memchr (test21, '.', 32);
	char *dot22 = memchr (test22, '.', 32);
	char *dot41 = memchr (test41, '.', 32);
	char *dot09 = memchr (test09, '.', 32);
	// char *dotnull = memchr (testnull, '.', 32);

	printf ("dot31: %s\n", dot31);
	printf ("dot32: %s\n", dot32);
	printf ("dot33: %s\n", dot33);
	printf ("dot21: %s\n", dot21);
	printf ("dot22: %s\n", dot22);
	printf ("dot41: %s\n", dot41);
	printf ("dot09: %s\n", dot09);

	strcpy (name, test31);
	strcpy (name, dummy);
	char *dotgarbage = memchr (name, '.', 32);
	printf ("dotgarbage: %s\n", dotgarbage);

	// strcpy (name, dummy);
	// dot_name = strchr (name, '.');
	// *dot_name++ = '\0';

	return 0;
}
