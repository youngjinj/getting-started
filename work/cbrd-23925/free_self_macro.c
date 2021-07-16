#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#define free_and_init(ptr) \
  do { \
    free ((void *) (ptr)); \
    (ptr) = NULL; \
  } while (0)

#define dept_free(dept) \
  do { \
    if ((dept)) { \
      if ((dept)->name) { \
        printf("[free] 부서 이름: %s\n", (dept)->name); \
      } \
      if ((dept)->description) { \
        printf("[free] 부서 설명: %s\n", (dept)->description); \
      } \
    } \
  } while (0)

#define dept_free_self(dept) \
  do { \
    dept_free ((DEPARTMENT *) dept); \
    free_and_init (dept); \
  } while (0)
 
struct Department {
  char name[20];
  char description[100];
};
typedef struct Department DEPARTMENT;

struct Company {
  char name[20];
  DEPARTMENT dept;
};
typedef struct Company COMPANY;

DEPARTMENT * create_department (const char * name, const char * description);
COMPANY * create_company (const char * name, const char * dept_name, const char * dept_description);

int main()
{
  /**/
  void * v1;
  v1 = create_department ("개발1팀", "연구소/개발1팀");

  // dept_free_self ((DEPARTMENT *) v1);
  do {
    // dept_free ((DEPARTMENT *) v1);
    do {
      if (((DEPARTMENT *) v1)) {
        if (((DEPARTMENT *) v1)->name) {
          printf("[free] 부서 이름: %s\n", ((DEPARTMENT *) v1)->name);
	}
	if (((DEPARTMENT *) v1)->description) {
	  printf("[free] 부서 설명: %s\n", ((DEPARTMENT *) v1)->description);
	}
      }
    } while (0);

    // free_and_init ((DEPARTMENT *) v1);
    do {
      free ((void *) ((DEPARTMENT *) v1));
      // (reinterpret_cast<DEPARTMENT * &>((DEPARTMENT *) v1)) = NULL;
      // (reinterpret_cast<DEPARTMENT * &>(v1)) = NULL;
      (v1) = NULL;
    } while (0);
  } while (0);
  //
  
  if (v1 == NULL)
    {
      printf("v1 is null\n");
    }
  /**/

  /**
  void * v1;
  v1 = create_department ("개발1팀", "연구소/개발1팀");

  dept_free_self ((DEPARTMENT *) v1);
  
  if (v1 == NULL)
    {
      printf("v1 is null\n");
    }
  /**/
  
  /**
  DEPARTMENT * dept1;
  dept1 = create_department ("개발2팀", "연구소/개발2팀");
  dept_free_self (dept1);
  
  if (dept1 == NULL)
    {
      printf("dept1 is null\n");
    }
  /**/

  /**
  COMPANY * company1;
  company1 = create_company ("큐브리드", "개발3팀", "연구소/개발3팀");
  dept_free ((DEPARTMENT *) &(company1->dept));
  
  if (company1 == NULL)
    {
      printf("company1 is null\n");
    }
  /**/

  return 0;
}

DEPARTMENT *
create_department (const char * name, const char * description)
{
  DEPARTMENT * dept = (DEPARTMENT *) malloc (sizeof (DEPARTMENT));

  strcpy(dept->name, name);
  strcpy(dept->description, description);

  printf("부서 이름: %s\n", dept->name);
  printf("부서 설명: %s\n", dept->description);

  return dept;
}

COMPANY *
create_company (const char * name, const char * dept_name, const char * dept_description)
{
  COMPANY * company = (COMPANY *) malloc (sizeof (COMPANY));

  strcpy(company->name, name);
  strcpy(company->dept.name, dept_name);
  strcpy(company->dept.description, dept_description);

  printf("회사 이름: %s\n", company->name);
  printf("- 부서 이름: %s\n", company->dept.name);
  printf("- 부서 설명: %s\n", company->dept.description);

  return company;
}
