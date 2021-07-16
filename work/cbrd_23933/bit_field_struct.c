#include <stdio.h>

struct parser_context_test
{
  unsigned has_internal_error;
  unsigned abort;
  unsigned set_host_var;
  unsigned dont_prt_long_string;
  unsigned long_string_skipped;
  unsigned print_type_ambiguity;
  unsigned strings_have_no_escapes;
  unsigned is_in_and_list;
  unsigned is_holdable;
  unsigned is_xasl_pinned_reference;
  unsigned recompile_xasl_pinned;
  unsigned dont_collect_exec_stats;
  unsigned return_generated_keys;
  unsigned is_system_generated_stmt;
  unsigned is_auto_commit;
};
typedef struct parser_context_test PARSER_CONTEXT_TEST;

struct parser_context
{
  unsigned has_internal_error:1;
  unsigned abort:1;
  unsigned set_host_var:1;
  unsigned dont_prt_long_string:1;
  unsigned long_string_skipped:1;
  unsigned print_type_ambiguity:1;
  unsigned strings_have_no_escapes:1;
  unsigned is_in_and_list:1;
  unsigned is_holdable:1;
  unsigned is_xasl_pinned_reference:1;
  unsigned recompile_xasl_pinned:1;
  unsigned dont_collect_exec_stats:1;
  unsigned return_generated_keys:1;
  unsigned is_system_generated_stmt:1;
  unsigned is_auto_commit:1;
};
typedef struct parser_context PARSER_CONTEXT;

struct parser_context_new
{
  struct
  {
    unsigned has_internal_error:1;
    unsigned abort:1;
    unsigned set_host_var:1;
    unsigned dont_prt_long_string:1;
    unsigned long_string_skipped:1;
    unsigned print_type_ambiguity:1;
    unsigned strings_have_no_escapes:1;
    unsigned is_in_and_list:1;
    unsigned is_holdable:1;
    unsigned is_xasl_pinned_reference:1;
    unsigned recompile_xasl_pinned:1;
    unsigned dont_collect_exec_stats:1;
    unsigned return_generated_keys:1;
    unsigned is_system_generated_stmt:1;
    unsigned is_auto_commit:1;
  } bs;
};
typedef struct parser_context_new PARSER_CONTEXT_NEW;

int main()
{
  printf( "PARSER_CONTEXT_TEST: %d\n", sizeof(PARSER_CONTEXT_TEST));
  printf( "PARSER_CONTEXT: %d\n", sizeof(PARSER_CONTEXT));
  printf( "PARSER_CONTEXT_NEW: %d\n", sizeof(PARSER_CONTEXT_NEW));

  return 0;
}
