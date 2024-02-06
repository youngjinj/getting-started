#include <stdio.h>
#include <limits.h>
#include <ctype.h>

#include <cstring>

const char *trim (const char *str, char *buf, int buf_size);

int
main ()
{
	const char *test1 = "    test    ";
	const char *test2 = "";
	const char *test3 = NULL;
	const char *str = NULL;
	char buf[LINE_MAX] = { '\0' };

	printf ("********** test1 **********\n");
	str = test1;
	printf ("before trim: _%s_\n", str);
	printf (" after trim: _%s_\n", trim (str, buf, LINE_MAX));

	printf ("********** test2 **********\n");
	str = test2;
	printf ("before trim: _%s_\n", str);
	printf (" after trim: _%s_\n", trim (str, buf, LINE_MAX));

	printf ("********** test1 **********\n");
	str = test3;
	printf ("before trim: _%s_\n", str);
	printf (" after trim: _%s_\n", trim (str, buf, LINE_MAX));

	return 0;
}

const char *
trim (const char *str, char *buf, int buf_size)
{
	char *begin = NULL;
	char *end = NULL;
	int len = -1;

	if (str == NULL)
	{
		return NULL;
	}

	len = strlen (str);

	memset (buf, 0, buf_size);
	memcpy (buf, str, len);
	buf[len] = '\0';

	begin = buf;
	while (isspace (static_cast<unsigned char> (*begin)))
	{
		begin++; 
	}

	if (*begin == '\0') {
		return buf;	
	}

	end = begin + static_cast<int> (strlen (begin)) - 1;
	while (end > begin && isspace (static_cast<unsigned char> (*end)))
	{
		end --;
	}

	end[1] = '\0';

	return begin;
}
