project('owl', 'c',
  version : '0.1',
  default_options : ['warning_level=3'])

inc = include_directories('.')
owl_sources = [
  'alloc.c',
  'strings.c',
  'gc.c',
  'objects.c',
  'code.c',
  'intrinsics.c',
  'evaluator.c',
]

owl_lib = static_library('owllib', owl_sources, include_directories : inc)

exe = executable('owl', ['owl.c'],
  include_directories : inc,
  link_with : owl_lib,
  install : true)

test_strings = executable('test_strings', ['tests/test_strings.c'],
  include_directories : inc,
  link_with : owl_lib)
test('strings', test_strings)

test_objects = executable('test_objects', ['tests/test_objects.c'],
  include_directories : inc,
  link_with : owl_lib)
test('objects', test_objects)

test_gc = executable('test_gc', ['tests/test_gc.c'],
  include_directories : inc,
  link_with : owl_lib)
test('gc', test_gc)

test_eval = executable('test_eval', ['tests/test_eval.c'],
  include_directories : inc,
  link_with : owl_lib)
test('eval', test_eval)
