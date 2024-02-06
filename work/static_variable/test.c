#include <stdio.h>
#include <string.h>

void check_env ();
int init_env (const int env_no);

int main()
{
	int i = 0;
	for (i = 0; i < 10; i++)
	{
		check_env();
	}

	return 0;
}

void check_env ()
{
	static int env_no = init_env (1);
	printf("Env No: $d\n", env_no);
}

int init_env (const int env_no)
{
	printf("Call `init_env`\n");

	if (env_no == 1)
	{
		return 1;
	}
	else
	{
		return 0;
	
	}
}
