#include <stdio.h>
#include <ruby.h>
#include "ruby_internals.h"

VALUE method_source_location_id(VALUE self);
VALUE method_source_region(VALUE self);
unsigned long hash(unsigned char *str);

void Init_destruct_ext() {
  rb_define_method(rb_define_class("Proc", rb_cObject), "source_location_id", method_source_location_id, 0);
  rb_define_method(rb_define_class("Proc", rb_cObject), "source_region", method_source_region, 0);
}

// Proc#source_location_id
// Similar in purpose to Proc#source_location, except that it returns an integer hash
// of the source location. Unlike source_location, this hash also includes the starting
// character, ending line number, and ending character of the proc expression.
// Also unlike source_location, this method does not allocate any heap memory
// (source_location allocates a Ruby array).
VALUE method_source_location_id(VALUE self) {
  struct rb_iseq_location_struct location = rb_proc_get_iseq(self, 0)->body->location;
  const char * path = RSTRING_PTR(location.pathobj);
  int start_line = location.code_range.first_loc.lineno;
  int start_col  = location.code_range.first_loc.column;
  int end_line = location.code_range.last_loc.lineno;
  int end_col  = location.code_range.last_loc.column;

  unsigned char result[1024];
  sprintf((char*)result, "%s|%d|%d|%d|%d", path, start_line, start_col, end_line, end_col);

//  printf("source_location_id = %ld\n", hash(result));
  return LONG2FIX(hash(result));
}

// http://www.cse.yorku.ca/~oz/hash.html
unsigned long hash(unsigned char *str) {
  unsigned long hash = 5381;
  int c;

  while ((c = *str++))
    hash = ((hash << 5) + hash) + c; /* hash * 33 + c */

  return hash;
}

// Proc#source_range
// Similar to Proc#Source_location, but includes extra values.
// returns [file, starting_line_number, starting_line_column, ending_line_number, ending_line_column]
VALUE method_source_region(VALUE self) {
  struct rb_iseq_location_struct location = rb_proc_get_iseq(self, 0)->body->location;
  VALUE result = rb_ary_new2(5);
  rb_ary_push(result, location.pathobj);
  rb_ary_push(result, INT2FIX(location.code_range.first_loc.lineno));
  rb_ary_push(result, INT2FIX(location.code_range.first_loc.column));
  rb_ary_push(result, INT2FIX(location.code_range.last_loc.lineno));
  rb_ary_push(result, INT2FIX(location.code_range.last_loc.column));
  return result;
}
