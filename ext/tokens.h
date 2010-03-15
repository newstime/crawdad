#ifndef _TOKENS_H_
#define _TOKENS_H_

enum token_type { BOX, GLUE, PENALTY };

struct box {
  enum token_type type;
  float width;
  char * content;
};

struct glue {
  enum token_type type;
  float width;
  float stretch;
  float shrink;
};

struct penalty {
  enum token_type type;
  float width;
  float penalty;
  int flagged;
};

typedef union {
  struct box box;
  struct glue glue;
  struct penalty penalty;
} token;

#endif

