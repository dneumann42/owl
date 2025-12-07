project('owl', 'c',
  version : '0.1',
  default_options : ['warning_level=3'])

exe = executable('owl', ['alloc.c', 'strings.c', 'gc.c', 'objects.c', 'code.c', 'intrinsics.c', 'evaluator.c', 'owl.c'],
  install : true)

test('basic', exe)
