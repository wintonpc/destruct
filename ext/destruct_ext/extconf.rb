require 'mkmf'
extension_name = 'destruct_ext'
dir_config(extension_name)
$CFLAGS = ' -Wall -Wno-format-security -O3 -fno-strict-aliasing -flto'

create_makefile(extension_name)
