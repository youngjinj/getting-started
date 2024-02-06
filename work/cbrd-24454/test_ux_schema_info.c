#include <stdio.h>

#include "cas_cci.h"

static void test_cci_sch_class ();
static void test_cci_sch_class_pattern ();
static void test_cci_sch_vclass ();
static void test_cci_sch_vclass_pattern ();
static void test_cci_sch_query_spec ();
static void test_cci_sch_attr_info ();
static void test_cci_sch_attr_info_pattern ();
static void test_cci_sch_class_attr_info ();
static void test_cci_sch_class_attr_info_pattern ();
static void test_cci_sch_method_info ();
static void test_cci_sch_class_method_info ();
static void test_cci_sch_methfile_info ();
static void test_cci_sch_superclass ();
static void test_cci_sch_subclass ();
static void test_cci_sch_constraint ();
static void test_cci_sch_trigger ();
static void test_cci_sch_trigger_pattern ();
static void test_cci_sch_class_priv ();
static void  test_cci_sch_class_priv_pattern ();
static void test_cci_sch_attr_priv ();
static void test_cci_sch_attr_priv_pattern ();
static void test_cci_sch_direct_super_class ();
static void test_cci_sch_direct_super_class_pattern ();
static void test_cci_sch_primary_key ();
static void test_cci_sch_imported_keys ();
static void test_cci_sch_exported_keys ();
static void test_cci_sch_cross_reference ();
static int test_cci_schema_info (char *user_name, T_CCI_SCH_TYPE type, char *class_name, char *attr_name, int pattern_flag);

int main (int argc, char *argv[])
{
  // test_cci_sch_class (); /* Expect 1 result. */
  test_cci_sch_class_pattern ();
  //test_cci_sch_vclass (); /* Expect 1 result. */
  //test_cci_sch_vclass_pattern ();
  //test_cci_sch_query_spec (); /* Expect 1 result. */
  //test_cci_sch_attr_info (); /* Expect 1 result. */
  //test_cci_sch_attr_info_pattern ();
  //test_cci_sch_class_attr_info (); /* Expect 1 result. */
  //test_cci_sch_class_attr_info_pattern ();

  /* Difference between unique_name and class_name. */
  //test_cci_sch_method_info (); /* Why is ARG_DOMAIN not output? */
  //test_cci_sch_class_method_info (); /* Why is ARG_DOMAIN not output? */
  //test_cci_sch_methfile_info ();
  //test_cci_sch_superclass ();
  //test_cci_sch_subclass ();
  //test_cci_sch_constraint ();
  //test_cci_sch_trigger (); /* If the schema is not specified, even the objects it owns cannot be found. */
  //test_cci_sch_trigger_pattern (); /* If the schema is not specified, even the objects it owns cannot be found. */
  //test_cci_sch_class_priv ();
  //test_cci_sch_class_priv_pattern (); /* If the schema is not specified, even the objects it owns cannot be found. */
  //test_cci_sch_attr_priv (); /* If the schema is not specified, even the objects it owns cannot be found. */

  //test_cci_sch_attr_priv_pattern ();
  //test_cci_sch_direct_super_class (); /* Expect 1 result. */
  //test_cci_sch_direct_super_class_pattern ();  /* Expect 1 result. */

  /* Difference between unique_name and class_name. */
  //test_cci_sch_primary_key ();

  //test_cci_sch_imported_keys ();
  //test_cci_sch_exported_keys ();
  //test_cci_sch_cross_reference ();

  return 0;
}

static void
test_cci_sch_class ()
{
#define TEST_CCI_SCH_CLASS(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | TYPE | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS ("user_1st", NULL);

  TEST_CCI_SCH_CLASS ("user_1st", "db_class");
  TEST_CCI_SCH_CLASS ("user_1st", "dba.db_class");

  TEST_CCI_SCH_CLASS ("user_1st", "table_1st");

  TEST_CCI_SCH_CLASS ("user_2nd", NULL);

  TEST_CCI_SCH_CLASS ("user_2nd", "table_1st");
  TEST_CCI_SCH_CLASS ("user_2nd", "synonym_1st");
  TEST_CCI_SCH_CLASS ("user_2nd", "synonym_2nd");

  TEST_CCI_SCH_CLASS ("dba", "table_1st"); /* Expect 1 result. */
  TEST_CCI_SCH_CLASS ("dba", "user_2nd.table_1st");

#undef TEST_CCI_SCH_CLASS
}

static void
test_cci_sch_class_pattern ()
{
#define TEST_CCI_SCH_CLASS_PATTERN(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS, (class_name), NULL, CCI_CLASS_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | TYPE | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS_PATTERN ("user_1st", NULL);

  TEST_CCI_SCH_CLASS_PATTERN ("user_1st", "table%");
  TEST_CCI_SCH_CLASS_PATTERN ("user_1st", "%\\_1%");
  TEST_CCI_SCH_CLASS_PATTERN ("user_1st", "%1st");

  TEST_CCI_SCH_CLASS_PATTERN ("user_2nd", NULL);

  TEST_CCI_SCH_CLASS_PATTERN ("user_2nd", "table%");
  TEST_CCI_SCH_CLASS_PATTERN ("user_2nd", "%\\_1%");
  TEST_CCI_SCH_CLASS_PATTERN ("user_2nd", "%1st");

  TEST_CCI_SCH_CLASS_PATTERN ("user_2nd", "synonym%");

  TEST_CCI_SCH_CLASS_PATTERN ("dba", "user_2nd%");
  TEST_CCI_SCH_CLASS_PATTERN ("dba", "user_2nd.%");
  TEST_CCI_SCH_CLASS_PATTERN ("dba", "user_2nd.table%");
  TEST_CCI_SCH_CLASS_PATTERN ("dba", "user_2nd.%\\_1%");
  TEST_CCI_SCH_CLASS_PATTERN ("dba", "user_2nd.%1st");

#undef TEST_CCI_SCH_CLASS_PATTERN
}

static void
test_cci_sch_vclass ()
{
#define TEST_CCI_SCH_VCLASS(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_VCLASS, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_VCLASS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | TYPE | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_VCLASS ("user_1st", NULL);

  TEST_CCI_SCH_VCLASS ("user_1st", "db_class");
  TEST_CCI_SCH_VCLASS ("user_1st", "dba.db_class");

  TEST_CCI_SCH_VCLASS ("user_1st", "view_1st");

  TEST_CCI_SCH_VCLASS ("dba", "view_1st"); /* Expect 1 result. */
  TEST_CCI_SCH_VCLASS ("dba", "user_2nd.view_1st");

#undef TEST_CCI_SCH_VCLASS
}

static void
test_cci_sch_vclass_pattern ()
{
#define TEST_CCI_SCH_VCLASS_PATTERN(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_VCLASS, (class_name), NULL, CCI_CLASS_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_VCLASS (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | TYPE | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_VCLASS_PATTERN ("user_1st", NULL);

  TEST_CCI_SCH_VCLASS_PATTERN ("user_1st", "view%");
  TEST_CCI_SCH_VCLASS_PATTERN ("user_1st", "%\\_1%");
  TEST_CCI_SCH_VCLASS_PATTERN ("user_1st", "%1st");

  TEST_CCI_SCH_VCLASS_PATTERN ("dba", "user_2nd%");
  TEST_CCI_SCH_VCLASS_PATTERN ("dba", "user_2nd.%");
  TEST_CCI_SCH_VCLASS_PATTERN ("dba", "user_2nd.view%");
  TEST_CCI_SCH_VCLASS_PATTERN ("dba", "user_2nd.%\\_1%");
  TEST_CCI_SCH_VCLASS_PATTERN ("dba", "user_2nd.%1st");

#undef TEST_CCI_SCH_VCLASS_PATTERN
}

static void
test_cci_sch_query_spec ()
{
#define TEST_CCI_SCH_QUERY_SPEC(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_QUERY_SPEC, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_QUERY_SPEC");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  QUERY_SPEC\n");
  printf ("\n");

  TEST_CCI_SCH_QUERY_SPEC ("user_1st", NULL);

  TEST_CCI_SCH_QUERY_SPEC ("user_1st", "db_class");
  TEST_CCI_SCH_QUERY_SPEC ("user_1st", "dba.db_class");

  TEST_CCI_SCH_QUERY_SPEC ("user_1st", "view_1st");

  TEST_CCI_SCH_QUERY_SPEC ("dba", "view_1st"); /* Expect 1 result. */
  TEST_CCI_SCH_QUERY_SPEC ("dba", "user_2nd.view_1st");

#undef TEST_CCI_SCH_QUERY_SPEC
}

static void
test_cci_sch_attr_info ()
{
#define TEST_CCI_SCH_ATTRIBUTE(user_name, class_name, attr_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("   attr_name : %s\n", (attr_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_ATTRIBUTE, (class_name), (attr_name), 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_ATTRIBUTE");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | DOMAIN | SCALE | PRECISION | INDEXED | NON_NULL | SHARED | UNIQUE | DEFAULT | ATTR_ORDER | CLASS_NAME | SOURCE_CLASS | IS_KEY | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_ATTRIBUTE ("user_1st", NULL, NULL);
  TEST_CCI_SCH_ATTRIBUTE ("user_1st", "table_1st", NULL);
  TEST_CCI_SCH_ATTRIBUTE ("user_1st", NULL, "column_1st");

  TEST_CCI_SCH_ATTRIBUTE ("user_1st", "db_class", "class_name");
  TEST_CCI_SCH_ATTRIBUTE ("user_1st", "dba.db_class", "class_name");

  TEST_CCI_SCH_ATTRIBUTE ("user_1st", "table_1st", "column_1st");

  TEST_CCI_SCH_ATTRIBUTE ("dba", "table_1st", "column_1st"); /* Expect 1 result. */
  TEST_CCI_SCH_ATTRIBUTE ("dba", "user_2nd.table_1st", "column_1st");

#undef TEST_CCI_SCH_ATTRIBUTE
}

static void
test_cci_sch_attr_info_pattern ()
{
#define TEST_CCI_SCH_ATTRIBUTE_PATTERN(user_name, class_name, attr_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("   attr_name : %s\n", (attr_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_ATTRIBUTE, (class_name), (attr_name), (CCI_CLASS_NAME_PATTERN_MATCH + CCI_ATTR_NAME_PATTERN_MATCH)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_ATTRIBUTE (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | DOMAIN | SCALE | PRECISION | INDEXED | NON_NULL | SHARED | UNIQUE | DEFAULT | ATTR_ORDER | CLASS_NAME | SOURCE_CLASS | IS_KEY | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("user_1st", NULL, NULL); /* Too many results. */
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("user_1st", "table_1st", NULL);
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("user_1st", NULL, "column_1st");

  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("user_1st", "table%", "column%");
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("user_1st", "%\\_1%", "%\\_1%");
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("user_1st", "%1st", "%1st");

  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("dba", "user_2nd%", "column_1st");
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("dba", "user_2nd.%", "column_1st");
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("dba", "user_2nd.table%", "column%");
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("dba", "user_2nd.%\\_1%", "%\\_1%");
  TEST_CCI_SCH_ATTRIBUTE_PATTERN ("dba", "user_2nd.%1st", "%1st");

#undef TEST_CCI_SCH_ATTRIBUTE_PATTERN
}

static void
test_cci_sch_class_attr_info ()
{
#define TEST_CCI_SCH_CLASS_ATTRIBUTE(user_name, class_name, attr_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("   attr_name : %s\n", (attr_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS_ATTRIBUTE, (class_name), (attr_name), 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS_ATTRIBUTE");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | DOMAIN | SCALE | PRECISION | INDEXED | NON_NULL | SHARED | UNIQUE | DEFAULT | ATTR_ORDER | CLASS_NAME | SOURCE_CLASS | IS_KEY | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS_ATTRIBUTE ("user_1st", NULL, NULL);
  TEST_CCI_SCH_CLASS_ATTRIBUTE ("user_1st", "table_1st", NULL);
  TEST_CCI_SCH_CLASS_ATTRIBUTE ("user_1st", NULL, "column_1st");

  TEST_CCI_SCH_CLASS_ATTRIBUTE ("user_1st", "db_class", "class_name");
  TEST_CCI_SCH_CLASS_ATTRIBUTE ("user_1st", "dba.db_class", "class_name");

  TEST_CCI_SCH_CLASS_ATTRIBUTE ("user_1st", "table_1st", "column_1st");

  TEST_CCI_SCH_CLASS_ATTRIBUTE ("dba", "table_1st", "column_1st"); /* Expect 1 result. */
  TEST_CCI_SCH_CLASS_ATTRIBUTE ("dba", "user_2nd.table_1st", "column_1st");

#undef TEST_CCI_SCH_CLASS_ATTRIBUTE
}

static void
test_cci_sch_class_attr_info_pattern ()
{
#define TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN(user_name, class_name, attr_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("   attr_name : %s\n", (attr_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS_ATTRIBUTE, (class_name), (attr_name), (CCI_CLASS_NAME_PATTERN_MATCH + CCI_ATTR_NAME_PATTERN_MATCH)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS_ATTRIBUTE (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | DOMAIN | SCALE | PRECISION | INDEXED | NON_NULL | SHARED | UNIQUE | DEFAULT | ATTR_ORDER | CLASS_NAME | SOURCE_CLASS | IS_KEY | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("user_1st", NULL, NULL);
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("user_1st", "table_1st", NULL);
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("user_1st", NULL, "column_1st");

  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("user_1st", "table%", "column%");
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("user_1st", "%\\_1%", "%\\_1%");
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("user_1st", "%1st", "%1st");

  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("dba", "user_2nd%", "column_1st");
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("dba", "user_2nd.%", "column_1st");
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("dba", "user_2nd.table%", "column%");
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("dba", "user_2nd.%\\_1%", "%\\_1%");
  TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN ("dba", "user_2nd.%1st", "%1st");

#undef TEST_CCI_SCH_CLASS_ATTRIBUTE_PATTERN
}

static void
test_cci_sch_method_info ()
{
#define TEST_CCI_SCH_METHOD(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_METHOD, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_METHOD");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | RET_DOMAIN | ARG_DOMAIN\n");
  printf ("\n");

  TEST_CCI_SCH_METHOD ("user_1st", NULL);

  TEST_CCI_SCH_METHOD ("user_1st", "table_3rd");

  TEST_CCI_SCH_METHOD ("dba", "db_user");
  TEST_CCI_SCH_METHOD ("dba", "dba.db_user");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_METHOD ("dba", "table_3rd");
  TEST_CCI_SCH_METHOD ("dba", "user_2nd.table_3rd");

#undef TEST_CCI_SCH_METHOD
}

static void
test_cci_sch_class_method_info ()
{
  printf ("NAME | RET_DOMAIN | ARG_DOMAIN\n");

#define TEST_CCI_SCH_CLASS_METHOD(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS_METHOD, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS_METHOD");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | RET_DOMAIN | ARG_DOMAIN\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS_METHOD ("user_1st", NULL);

  TEST_CCI_SCH_CLASS_METHOD ("user_1st", "table_3rd");

  TEST_CCI_SCH_CLASS_METHOD ("dba", "db_user");
  TEST_CCI_SCH_CLASS_METHOD ("dba", "dba.db_user");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CLASS_METHOD ("dba", "table_3rd");
  TEST_CCI_SCH_CLASS_METHOD ("dba", "user_2nd.table_3rd");

#undef TEST_CCI_SCH_CLASS_METHOD
}

static void
test_cci_sch_methfile_info ()
{
#define TEST_CCI_SCH_METHOD_FILE(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_METHOD_FILE, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_METHOD_FILE");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  METHOD_FILE\n");
  printf ("\n");

  TEST_CCI_SCH_METHOD_FILE ("user_1st", NULL);

  TEST_CCI_SCH_METHOD_FILE ("user_1st", "table_3rd");

  TEST_CCI_SCH_METHOD_FILE ("dba", "db_user");
  TEST_CCI_SCH_METHOD_FILE ("dba", "dba.db_user");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_METHOD_FILE ("dba", "table_3rd");
  TEST_CCI_SCH_METHOD_FILE ("dba", "user_2nd.table_3rd");

#undef TEST_CCI_SCH_METHOD_FILE
}

static void
test_cci_sch_superclass ()
{
#define TEST_CCI_SCH_SUPERCLASS(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_SUPERCLASS, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_SUPERCLASS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | TYPE\n");
  printf ("\n");

  TEST_CCI_SCH_SUPERCLASS ("user_1st", NULL);

  TEST_CCI_SCH_SUPERCLASS ("user_1st", "table_5th");
  TEST_CCI_SCH_SUPERCLASS ("user_1st", "table_6th");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_SUPERCLASS ("dba", "table_5th");
  TEST_CCI_SCH_SUPERCLASS ("dba", "user_2nd.table_5th");

#undef TEST_CCI_SCH_SUPERCLASS
}

static void
test_cci_sch_subclass ()
{
#define TEST_CCI_SCH_SUBCLASS(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_SUBCLASS, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_SUBCLASS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | TYPE\n");
  printf ("\n");

  TEST_CCI_SCH_SUBCLASS ("user_1st", NULL);

  TEST_CCI_SCH_SUBCLASS ("user_1st", "table_4th");
  TEST_CCI_SCH_SUBCLASS ("user_1st", "table_5th");
  TEST_CCI_SCH_SUBCLASS ("user_1st", "table_7th");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_SUBCLASS ("dba", "table_4th");
  TEST_CCI_SCH_SUBCLASS ("dba", "user_2nd.table_4th");

#undef TEST_CCI_SCH_SUBCLASS
}

static void
test_cci_sch_constraint ()
{
#define TEST_CCI_SCH_CONSTRAINT(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CONSTRAINT, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CONSTRAINT");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  TYPE | NAME | ATTR_NAME | NUM_PAGES | NUM_KEYS | PRIMARY_KEY | KEY_ORDER | ASC_DESC\n");
  printf ("\n");

  TEST_CCI_SCH_CONSTRAINT ("user_1st", NULL);

  TEST_CCI_SCH_CONSTRAINT ("user_1st", "table_8th");
  TEST_CCI_SCH_CONSTRAINT ("user_1st", "table_9th");

  TEST_CCI_SCH_CONSTRAINT ("dba", "_db_class");
  TEST_CCI_SCH_CONSTRAINT ("dba", "dba._db_class");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CONSTRAINT ("dba", "table_8th");
  TEST_CCI_SCH_CONSTRAINT ("dba", "user_2nd.table_8th"); 
  TEST_CCI_SCH_CONSTRAINT ("dba", "user_2nd.table_9th");

#undef TEST_CCI_SCH_CONSTRAINT
}

static void
test_cci_sch_trigger ()
{
#define TEST_CCI_SCH_TRIGGER(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_TRIGGER, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_TRIGGER");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | STATUS | EVENT | TARGET_CLASS | TARGET_ATTR | ACTION_TIME | ACTION | PRIORITY | CONDITION_TIME | CONDITION | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_TRIGGER ("user_1st", NULL);

  /* If the schema is not specified, even the objects it owns cannot be found. */
  TEST_CCI_SCH_TRIGGER ("user_1st", "table_1st");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_TRIGGER ("dba", "table_1st"); 
  TEST_CCI_SCH_TRIGGER ("dba", "user_2nd.table_1st");

#undef TEST_CCI_SCH_TRIGGER
}

static void
test_cci_sch_trigger_pattern ()
{
#define TEST_CCI_SCH_TRIGGER_PATTERN(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_TRIGGER, (class_name), NULL, CCI_CLASS_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_TRIGGER (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  NAME | STATUS | EVENT | TARGET_CLASS | TARGET_ATTR | ACTION_TIME | ACTION | PRIORITY | CONDITION_TIME | CONDITION | REMARKS\n");
  printf ("\n");

  TEST_CCI_SCH_TRIGGER_PATTERN ("user_1st", NULL);

  /* If the schema is not specified, even the objects it owns cannot be found. */
  TEST_CCI_SCH_TRIGGER_PATTERN ("user_1st", "table%");
  TEST_CCI_SCH_TRIGGER_PATTERN ("user_1st", "%\\_1%");
  TEST_CCI_SCH_TRIGGER_PATTERN ("user_1st", "%1st");

  TEST_CCI_SCH_TRIGGER_PATTERN ("dba", "user_2nd%");
  TEST_CCI_SCH_TRIGGER_PATTERN ("dba", "user_2nd.%");
  TEST_CCI_SCH_TRIGGER_PATTERN ("dba", "user_2nd.table%");
  TEST_CCI_SCH_TRIGGER_PATTERN ("dba", "user_2nd.%\\_1%");
  TEST_CCI_SCH_TRIGGER_PATTERN ("dba", "user_2nd.%1st");

#undef TEST_CCI_SCH_TRIGGER_PATTERN
}

static void
test_cci_sch_class_priv ()
{
#define TEST_CCI_SCH_CLASS_PRIVILEGE(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS_PRIVILEGE, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS_PRIVILEGE");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | PRIVILEGE | GRANTABLE\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_1st", NULL);

  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_1st", "db_class");
  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_1st", "dba.db_class");

  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_1st", "table_1st");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_3rd", "table_1st");
  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_3rd", "user_1st.table_1st");
  TEST_CCI_SCH_CLASS_PRIVILEGE ("user_3rd", "user_1st.table_2nd");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CLASS_PRIVILEGE ("dba", "table_1st");
  TEST_CCI_SCH_CLASS_PRIVILEGE ("dba", "user_2nd.table_1st");

#undef TEST_CCI_SCH_CLASS_PRIVILEGE
}

static void
test_cci_sch_class_priv_pattern ()
{
#define TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CLASS_PRIVILEGE, (class_name), NULL, CCI_CLASS_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CLASS_PRIVILEGE (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | PRIVILEGE | GRANTABLE\n");
  printf ("\n");

  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_1st", NULL);

  /* If the schema is not specified, even the objects it owns cannot be found. */
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_1st", "table%");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_1st", "%\\_1%");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_1st", "%1st");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_3rd", "table_1st");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_3rd", "user_1st%");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_3rd", "user_1st.%");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_3rd", "user_1st.table%");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_3rd", "user_1st.%\\_1%");
  TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN ("user_3rd", "user_1st.%1st");

#undef TEST_CCI_SCH_CLASS_PRIVILEGE_PATTERN
}

static void
test_cci_sch_attr_priv ()
{
#define TEST_CCI_SCH_ATTR_PRIVILEGE(user_name, class_name, attr_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("   attr_name : %s\n", (attr_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_ATTR_PRIVILEGE, (class_name), (attr_name), CCI_CLASS_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_ATTR_PRIVILEGE");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  ATTR_NAME | PRIVILEGE | GRANTABLE\n");
  printf ("\n");

  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_1st", NULL, NULL);
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_1st", "table_1st", NULL);
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_1st", NULL, "column_1st");

  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_1st", "db_class", "class_name");
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_1st", "dba.db_class", "class_name");

  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_1st", "table_1st", "column_1st");
  
  /* If the schema is not specified, even the objects it owns cannot be found. */
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_3rd", "table_1st", "column_1st");
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_3rd", "user_1st.table_1st", "column_1st");
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_3rd", "user_1st.table_1st", "column_2nd");
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_3rd", "user_1st.table_2nd", "column_1st");
  TEST_CCI_SCH_ATTR_PRIVILEGE ("user_3rd", "user_1st.table_2nd", "column_2nd");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_ATTR_PRIVILEGE ("dba", "table_1st", "column_1st");
  TEST_CCI_SCH_ATTR_PRIVILEGE ("dba", "user_2nd.table_1st", "column_1st");

#undef TEST_CCI_SCH_ATTR_PRIVILEGE
}

static void
test_cci_sch_attr_priv_pattern ()
{
#define TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN(user_name, class_name, attr_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("   attr_name : %s\n", (attr_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_ATTR_PRIVILEGE, (class_name), (attr_name), CCI_ATTR_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_ATTR_PRIVILEGE (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  ATTR_NAME | PRIVILEGE | GRANTABLE\n");
  printf ("\n");

  /* CCI_CLASS_NAME_PATTERN_MATCH is not supported. */

  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_1st", NULL, NULL);
  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_1st", "table_1st", NULL);
  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_1st", NULL, "column_1st");

  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_1st", "table_1st", "column%");
  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_1st", "table_1st", "%\\_1%");
  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_1st", "table_1st", "%1st");

  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_3rd", "user_1st.table_1st", "column%");
  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_3rd", "user_1st.table_1st", "%\\_1%");
  TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN ("user_3rd", "user_1st.table_1st", "%1st");

#undef TEST_CCI_SCH_ATTR_PRIVILEGE_PATTERN
}

static void
test_cci_sch_direct_super_class ()
{
#define TEST_CCI_SCH_DIRECT_SUPER_CLASS(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_DIRECT_SUPER_CLASS, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_DIRECT_SUPER_CLASS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | SUPER_CLASS_NAME\n");
  printf ("\n");

  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("user_1st", NULL);

  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("user_1st", "table_4th");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("user_1st", "table_5th");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("user_1st", "table_6th");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("user_1st", "table_7th");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("user_1st", "table_7th__p__p0");

  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("dba", "table_5th"); /* Expect 1 result. */
  TEST_CCI_SCH_DIRECT_SUPER_CLASS ("dba", "user_2nd.table_5th");

#undef TEST_CCI_SCH_DIRECT_SUPER_CLASS
}

static void
test_cci_sch_direct_super_class_pattern ()
{
#define TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_DIRECT_SUPER_CLASS, (class_name), NULL, CCI_CLASS_NAME_PATTERN_MATCH); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_DIRECT_SUPER_CLASS (PATTERN)");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | SUPER_CLASS_NAME\n");
  printf ("\n");

  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("user_1st", NULL);

  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("user_1st", "table%");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("user_1st", "%\\_5%");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("user_1st", "%5th");

  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("dba", "table_5th"); /* Expect 1 result. */
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("dba", "user_1st%");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("dba", "user_1st.%");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("dba", "user_1st.table%");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("dba", "user_1st.%\\_5%");
  TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN ("dba", "user_1st.%5th");

#undef TEST_CCI_SCH_DIRECT_SUPER_CLASS_PATTERN
}

static void
test_cci_sch_primary_key ()
{
#define TEST_CCI_SCH_PRIMARY_KEY(user_name, class_name) \
	do \
	  { \
	    printf ("   user_name : %s\n", (user_name)); \
	    printf ("  class_name : %s\n", (class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_PRIMARY_KEY, (class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_PRIMARY_KEY");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  CLASS_NAME | ATTR_NAME | KEY_SEQ | KEY_NAME\n");
  printf ("\n");

  TEST_CCI_SCH_PRIMARY_KEY ("user_1st", NULL);

  TEST_CCI_SCH_PRIMARY_KEY ("user_1st", "db_class");
  TEST_CCI_SCH_PRIMARY_KEY ("user_1st", "dba.db_class");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_PRIMARY_KEY ("user_1st", "table_8th");

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_PRIMARY_KEY ("dba", "table_8th");
  TEST_CCI_SCH_PRIMARY_KEY ("dba", "user_2nd.table_8th");

#undef TEST_CCI_SCH_PRIMARY_KEY
}

static void
test_cci_sch_imported_keys ()
{
#define TEST_CCI_SCH_IMPORTED_KEYS(user_name, fk_class_name) \
	do \
	  { \
	    printf ("      user_name : %s\n", (user_name)); \
	    printf ("  fk_class_name : %s\n", (fk_class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_IMPORTED_KEYS, (fk_class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_IMPORTED_KEYS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  PKTABLE_NAME | PKCOLUMN_NAME | FKTABLE_NAME | FKCOLUMN_NAME | KEY_SEQ | UPDATE_ACTION | DELETE_ACTION | FK_NAME | PK_NAME\n");
  printf ("\n");

  TEST_CCI_SCH_IMPORTED_KEYS ("user_1st", NULL);

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_IMPORTED_KEYS ("user_1st", "table_9th"); /* table_9th -> user_1st.table_9th */

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_IMPORTED_KEYS ("dba", "table_9th");
  TEST_CCI_SCH_IMPORTED_KEYS ("dba", "user_2nd.table_9th");

#undef TEST_CCI_SCH_IMPORTED_KEYS
}

static void
test_cci_sch_exported_keys ()
{
#define TEST_CCI_SCH_EXPORTED_KEYS(user_name, pk_class_name) \
	do \
	  { \
	    printf ("      user_name : %s\n", (user_name)); \
	    printf ("  pk_class_name : %s\n", (pk_class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_EXPORTED_KEYS, (pk_class_name), NULL, 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_EXPORTED_KEYS");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  PKTABLE_NAME | PKCOLUMN_NAME | FKTABLE_NAME | FKCOLUMN_NAME | KEY_SEQ | UPDATE_ACTION | DELETE_ACTION | FK_NAME | PK_NAME\n");
  printf ("\n");

  TEST_CCI_SCH_EXPORTED_KEYS ("user_1st", NULL);

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_EXPORTED_KEYS ("user_1st", "table_8th"); /* table_8th -> user_1st.table_8th */

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_EXPORTED_KEYS ("dba", "table_8th");
  TEST_CCI_SCH_EXPORTED_KEYS ("dba", "user_2nd.table_8th");

#undef TEST_CCI_SCH_EXPORTED_KEYS
}

static void
test_cci_sch_cross_reference ()
{
#define TEST_CCI_SCH_CROSS_REFERENCE(user_name, pk_class_name, fk_class_name) \
	do \
	  { \
	    printf ("      user_name : %s\n", (user_name)); \
	    printf ("  pk_class_name : %s\n", (pk_class_name)); \
	    printf ("  fk_class_name : %s\n", (fk_class_name)); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    test_cci_schema_info ((user_name), CCI_SCH_CROSS_REFERENCE, (pk_class_name), (fk_class_name), 0); \
	    printf ("--------------------------------------------------------------------------------\n"); \
	    printf ("\n"); \
	  } \
	while (0)

  printf ("\n");
  printf ("################################################################################\n");
  printf ("#                                                                              #\n");
  printf ("#  %-74s  #\n", "CCI_SCH_CROSS_REFERENCE");
  printf ("#                                                                              #\n");
  printf ("################################################################################\n");
  printf ("\n");
  printf ("  PKTABLE_NAME | PKCOLUMN_NAME | FKTABLE_NAME | FKCOLUMN_NAME | KEY_SEQ | UPDATE_ACTION | DELETE_ACTION | FK_NAME | PK_NAME\n");
  printf ("\n");

  TEST_CCI_SCH_CROSS_REFERENCE ("user_1st", NULL, NULL);
  TEST_CCI_SCH_CROSS_REFERENCE ("user_1st", NULL, "table_9th");
  TEST_CCI_SCH_CROSS_REFERENCE ("user_1st", "table_8th", NULL);

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CROSS_REFERENCE ("user_1st", "table_8th", "table_9th"); /* table_8th -> user_1st.table_8th, table_9th -> user_1st.table_9th */

  /* Difference between unique_name and class_name. */
  TEST_CCI_SCH_CROSS_REFERENCE ("dba", "table_8th", "table_9th");
  TEST_CCI_SCH_CROSS_REFERENCE ("dba", "table_8th", "user_2nd.table_9th");
  TEST_CCI_SCH_CROSS_REFERENCE ("dba", "user_2nd.table_8th", "table_9th");
  TEST_CCI_SCH_CROSS_REFERENCE ("dba", "user_2nd.table_8th", "user_2nd.table_9th");

#undef TEST_CCI_SCH_CROSS_REFERENCE
}

static int
test_cci_schema_info (char *user_name, T_CCI_SCH_TYPE type, char *class_name, char *attr_name, int pattern_flag)
{
  T_CCI_ERROR cci_error;
  T_CCI_COL_INFO *cci_col_info;
  T_CCI_CUBRID_STMT cci_stmt_type;
  char *buffer;
  int con_id = 0, cci_request = 0, cci_retval = 0, cci_ind = 0;
  int col_count = 0;
  int i;

  con_id = cci_connect ("localhost", 30000, "demodb", user_name, "");
  if (con_id < 0)
    {
      printf ("%s(%d): cci_connect fail.\n", __FILE__, __LINE__);
      return -1;
    }

  cci_request = cci_schema_info (con_id, type, class_name, attr_name, pattern_flag, &cci_error);
  if (cci_request < 0)
    {
      printf ("%s(%d): cci_schema_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  cci_col_info = cci_get_result_info (cci_request, &cci_stmt_type, &col_count);
  if (!cci_col_info)
    {
      printf ("%s(%d): cci_get_result_info fail.\n", __FILE__, __LINE__);
      goto handle_error;
    }

  while (1)
    {
      cci_retval = cci_cursor (cci_request, 1, CCI_CURSOR_CURRENT, &cci_error);
      if (cci_retval == CCI_ER_NO_MORE_DATA)
	{
	  break;
	}

      if (cci_retval < 0)
	{
	  printf ("%s(%d): cci_cursor fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
	  goto handle_error;
	}

      cci_retval = cci_fetch (cci_request, &cci_error);
      if (cci_retval < 0)
	{
	  printf ("%s(%d): cci_fetch fail. (%d)\n", __FILE__, __LINE__, cci_error.err_code);
	  goto handle_error;
	}

      for (i = 1; i <= col_count; i++)
	{
	  if (i == 1)
	    {
	      printf("  ");
	    }
	  else
	    {
	      printf(" | ");
	    }

	  cci_retval = cci_get_data (cci_request, i, CCI_A_TYPE_STR, &buffer, &cci_ind);
	  if (cci_retval < 0)
	    {
	      printf( "%s(%d): cci_get_data fail.\n", __FILE__, __LINE__);
	      goto handle_error;
	    }

	  printf("%s", buffer);
	}

      printf("\n");
    }

  cci_retval = cci_close_req_handle (cci_request);
  if (cci_retval < 0)
    {
      printf ("%s(%d): cci_close_req_handle fail.", __FILE__, __LINE__);
      goto handle_error;
    }

  cci_retval = cci_disconnect (con_id, &cci_error);
  if (cci_retval < 0)
    {
      printf( "%s(%d): cci_disconnect fail. (%d)", __FILE__, __LINE__, cci_error.err_code);
      goto handle_error;
    }

  return 0;

handle_error:
  if (cci_request > 0)
    {
      cci_close_req_handle (cci_request);
    }

  if (con_id > 0)
    {
      cci_disconnect (con_id, &cci_error);
    }

  return -1;
}
