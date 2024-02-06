#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

int main()
{
    char buf[10];
    const char *test1 = "aaaaaaaaaa";
    const char *test2 = "bbb";
    const char *test3 = "ccc";
    int rc ;

    rc = snprintf(buf, sizeof(buf) - 1, "%s", test1);
    printf("test=%s, rc=%d\n", buf, rc);

    rc = snprintf(buf, sizeof(buf), "%s", test1);
    printf("test=%s, rc=%d\n", buf, rc);

    rc = snprintf(buf, sizeof(buf) - 1, "%s%s", test2, test3);
    printf("test=%s, rc=%d\n", buf, rc);

    rc = snprintf(NULL, 0, "%s%s", test2, test3);
    printf("test=%s, rc=%d\n", buf, rc);

    return 0;
}
