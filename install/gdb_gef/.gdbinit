# source /home/youngjinj/github/gef/gef.py

# createdb (cub_admin) debug
set follow-fork-mode child

# execute query (csql) debug
set follow-fork-mode parent

# set detach-on-fork off 

# handle all nostop print
# handle SIGPIPE nostop

# set print array on
set print elements 0
# set print null-stop
set print pretty on
# set print sevenbit-strings off
set print union on
# set print demangle on
# set print object on
# set print static-members on
# set print vtbl on
# set pagination off

# set print repeats 0

# set logging overwrite on

# Could not load shared library symbols ...
# set solib-search-path /home/youngjinj/CUBRID/lib
# set substitute-path /nlwp/CUBRID1102 /home/youngjinj/CUBRID
# set substitute-path /nlwp/CUBRID /home/youngjinj/CUBRID
# set substitute-path /home/jenkins/workspace/cubrid_release_11.0 /home/youngjinj/github/develop
# set pagination on
# set listsize 20

# set substitute-path /home/perl/CUBRID /home/youngjinj/CUBRID

macro define offsetof(t, f) &((t *) 0)->f
macro define pgptr_bcb_latch_mode(pgptr) ((PGBUF_BCB *) ((PGBUF_IOPAGE_BUFFER *) ((char *) pgptr - offsetof (PGBUF_IOPAGE_BUFFER, iopage.page)))->bcb)->latch_mode

macro define PT_NAME_ORIGINAL(n)        ((((n) != 0) & ((n)->node_type == PT_NAME)) ? (n)->info.name.original : 0)
macro define PT_SPEC_ENTITY_NAME(n)     ((((n) != 0) & ((n)->node_type == PT_SPEC)) ? (n)->info.spec.entity_name : 0)
macro define PT_SPEC_LOCATION(n)        ((((n) != 0) & ((n)->node_type == PT_SPEC)) ? (n)->info.spec.location : -1)

macro define QO_NODE_LOCATION(n)        (((n) != 0) ? (n)->entity_spec->info.spec.location : -1)
macro define QO_NODE_NAME(n)            (((n) != 0) ? (n)->class_name : 0)
macro define QO_TERM_LOCATION(n)        (((n) != 0) ? (n)->location : -1)
macro define QO_TERM_PT_EXPR(n)         (((n) != 0) ? parser_print_tree ((n)->env->parser, (n)->pt_expr) : 0)

macro define OR_GET_INT(p)              ((int) ntohl (*(int *) ((char *) (p))))

macro define QFILE_TUPLE_LENGTH_SIZE            8
macro define QFILE_TUPLE_LENGTH_OFFSET          0

macro define QFILE_TUPLE_VALUE_HEADER_SIZE      8

macro define QFILE_TUPLE_VALUE_FLAG_OFFSET      0
macro define QFILE_TUPLE_VALUE_LENGTH_OFFSET    4

macro define QFILE_GET_TUPLE_LENGTH(t)                  (((t) != 0) ? (OR_GET_INT ((t) + QFILE_TUPLE_LENGTH_OFFSET)) : -1)
macro define QFILE_GET_TUPLE_VALUE_FLAG(t)              (((t) != 0) ? ((QFILE_TUPLE_VALUE_FLAG) OR_GET_INT ((t) + QFILE_TUPLE_VALUE_FLAG_OFFSET)) : -1)
macro define QFILE_GET_TUPLE_VALUE_LENGTH(t)            (((t) != 0) ? ((int) OR_GET_INT ((t) + QFILE_TUPLE_VALUE_LENGTH_OFFSET)) : -1)

define pt_node_trace
  set $pt_node = $arg0
  
  if $pt_node != ((void *) 0)
    set $parser_id = $pt_node->parser_id
  end
  
  while ($pt_node != ((void *) 0) && $pt_node->parser_id == $parser_id)
    printf "0x%08x: ", $pt_node->parser_id
    printf "0x%08x: ", $pt_node
    output $pt_node->node_type
    printf ", next(0x%08x)\n", $pt_node->next
    
    set $pt_node = $pt_node->next
  end
end

define next_trace
  set $ptr = $arg0
  
  while $ptr != ((void *) 0)
    printf "0x%08x: ", $ptr
    printf "%8s", $ptr->spec_name
    printf ", %s", $ptr->attr_name
    printf ", next(0x%08x)\n", $ptr->next
    
    set $ptr = $ptr->next
  end
end

# gef> pt_dot_info_trace col
define pt_dot_info_trace
  set $pt_node = $arg0

  while $pt_node != ((void *) 0)
    printf "[0x%08x] ", $pt_node
    printf "node_type: "
    output $pt_node->node_type
    
    printf " "

    if $pt_node->node_type == PT_DOT_
      printf "/ arg1: "
      output $pt_node->info.dot.arg1.node_type
      printf "("
      output $pt_node->info.dot.arg1.info.name.original
      printf ")"
      
      printf " "
      
      printf "/ arg2: "
      output $pt_node->info.dot.arg2.node_type
      printf "("
      output $pt_node->info.dot.arg2.info.name.original
      printf ")"
    end

    printf "/ next: 0x%08x\n", $pt_node->next
    set $pt_node = $pt_node->next
  end
end

# gef> parser_String_blocks_trace parser_String_blocks
define parser_String_blocks_trace
  set $pt_node = $arg0

  set $i = 0
  while $i < 128
    set $curr_pt_node = *($pt_node + $i)

    if $curr_pt_node == ((void *) 0)
#     printf "[0x%08x] %d\n", $curr_pt_node, $i
    end

    while $curr_pt_node != ((void *) 0)
      printf "[0x%08x] ", $curr_pt_node
      printf "%d ", $i
      printf "/ parser_id: "
      output/d $curr_pt_node->parser_id

      printf " "

      printf "/ last_string_start: "
      output/d $curr_pt_node->last_string_start

      printf " "

      printf "/ last_string_end: "
      output/d $curr_pt_node->last_string_end

      printf " "

      printf "/ block_end: "
      output/d $curr_pt_node->block_end

      printf "\n"
      set $curr_pt_node = $curr_pt_node->next
    end

    set $i = $i + 1
  end
end

define lc_names_print_all
  set $i = 0
  while $i < locator_Mht_classnames->size
    set $he = locator_Mht_classnames->table[$i]
      while $he != 0
        p (char *) $he->key
        p (LOCATOR_CLASSNAME_ENTRY *) $he->data
        p *(LOCATOR_CLASSNAME_ENTRY *) $he->data
        set $he = $he->next
        end
    set $i = $i + 1
    end
  end
