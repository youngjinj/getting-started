#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>

int main()
{
    char test[2084];
    char buf[1024];
    char * start = buf;
    char * end = &buf[sizeof(buf)-1];
    memset(test,0,sizeof(test));
    int rc ;

    rc = snprintf(test,sizeof(test)-1,"%s",NULL);
    printf("test=%s, rc=%d\n", test, rc);

    rc = snprintf(test,3, "%c%c", 'c','d');
    printf("test=%s, rc=%d\n", test, rc);

    rc = snprintf(test,2, "%c", 'c');
    printf("test=%s, rc=%d\n", test, rc);

    rc = snprintf(test,1, "%c", 'c');
    printf("test=%s, rc=%d\n", test, rc);

    rc = snprintf(test,0, "%c", 'c');
    printf("test=%s, rc=%d\n", test, rc);

    rc = snprintf(NULL,0, "%c", 'c');
    printf("test=%s, rc=%d\n", test, rc);

    rc = sprintf(NULL, "%c", 'c');
    printf("test=%s, rc=%d\n", test, rc);

    return 0;
}
