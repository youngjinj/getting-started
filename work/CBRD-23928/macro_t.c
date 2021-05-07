#include <stdio.h>
#include <stdlib.h>

#define PT_HAS_ERROR(perser) \
  (parser && (parser->error_msgs != NULL || parser->has_internal_error))

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


int main (int argc, char *argv[])
{
  void * parser;
  parser = (PARSER_CONTEXT *) calloc (sizeof (PARSER_CONTEXT), 1);

  if (PT_HAS_ERROR(parser))
    {
      printf("[main] parser has error.\n");
      return 1;
    }

  printf("end.\n");
  return 0;
}
