#include <stdio.h>
#include <stdlib.h>

typedef struct parser_context PARSER_CONTEXT;
typedef struct parser_node PT_NODE;

struct parser_context
{
  PT_NODE *error_msgs;
  unsigned has_internal_error:1;
};

struct parser_node
{
  int parser_id;
};


inline int pt_has_error (const PARSER_CONTEXT * parser);

int main(int argc, char *argv[])
{
  PARSER_CONTEXT * parser;
  parser = (PARSER_CONTEXT *) calloc (sizeof (PARSER_CONTEXT), 1);
  
  if (argc > 1)
    {
      parser->has_internal_error = atoi(argv[1]);
      printf("[main] parser->has_internal_error : %d\n", parser->has_internal_error);
    }
  
  if (pt_has_error(parser))
    {
      printf("[main] parser has error.\n");
      return 1;
    }

  printf("[main] end.\n");
  return 0;
}

int
pt_has_error (const PARSER_CONTEXT * parser)
{
  if (parser && (parser->error_msgs != NULL || parser->has_internal_error))
    {
      return 1;
    }

  return 0;
}
