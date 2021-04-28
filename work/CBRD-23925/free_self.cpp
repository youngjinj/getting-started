#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#define free_and_init(ptr) \
  do { \
    free ((void*) (ptr)); \
    (ptr) = NULL; \
  } while (0)

struct Person {
  char name[20];
  int age;
  char address[100];
};
typedef struct Person PERSON;

PERSON * create_person (const char * name, const int age, const char * address);

void person_free_self (PERSON * p);
void person_free (PERSON * p, bool self);

void person_free_self_v (void ** v);
void person_free_v (void ** v, bool self);

#ifdef __cplusplus
void person_free_r (PERSON * & p, bool self);
#endif

int main()
{
  void * v1;
  
  v1 = create_person ("홍길동", 30, "서울시 용산구 한남동");
  // person_free_self (v1);
  // person_free_self_v (&v1);
  person_free_r ((PERSON *) v1, true);
  
  
  if (v1 == NULL)
    {
      printf("v1 is null");
    }
  
  return 0;
}

PERSON *
create_person (const char * name, const int age, const char * address)
{
  PERSON * p = (PERSON *) malloc (sizeof (PERSON));
  
  strcpy(p->name, name);
  p->age = age;
  strcpy(p->address, address);
  
  printf("이름: %s\n", p->name);
  printf("나이: %d\n", p->age);
  printf("주소: %s\n", p->address);
  
  return p;
}

void
person_free_self (PERSON * p)
{
  if (p != NULL)
    {
      person_free (p, true);
    }
}

void
person_free (PERSON * p, bool self)
{
  if (self)
    {
      free_and_init (p);
    }
}

void
person_free_self_v (void ** v)
{
  if (((PERSON *) v) != NULL)
    {
      person_free_v (v, true);
    }
}

void
person_free_v (void ** v, bool self)
{
  if (self)
    {
      free_and_init ((*v));
    }
}

void
person_free_r (PERSON * & p, bool self)
{
  if (self)
    {
      free_and_init (p);
    }
}