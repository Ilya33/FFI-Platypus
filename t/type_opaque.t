use strict;
use warnings;
use Test::More tests => 10;
use FFI::CheckLib;
use FFI::Platypus::Declare qw( opaque int void string );
use FFI::Platypus::Memory qw( malloc free cast );

lib find_lib lib => 'test', symbol => 'f0', libpath => 'libtest';

function [pointer_null => 'null']           => []       => opaque;
function [pointer_is_null => 'is_null']     => [opaque] => int;
function [pointer_set_my_pointer => 'setp'] => [opaque] => void;
function [pointer_get_my_pointer => 'getp'] => []       => opaque;

is null(), undef, 'null = undef';
is is_null(undef), 1, 'is_null(undef) == 1';

my $ptr = malloc 32;
is is_null($ptr), 0, 'is_null($ptr) = 0';

setp($ptr);
is getp(), $ptr, "setp($ptr); getp() = $ptr";

free $ptr;

function [pointer_arg_array_in  => 'aa_in']  => ['opaque[3]'] => int;
function [pointer_arg_array_null_in  => 'aa_null_in']  => ['opaque[3]'] => int;
function [pointer_arg_array_out => 'aa_out'] => ['opaque[3]'] => void;
function [pointer_arg_array_null_out => 'aa_null_out'] => ['opaque[3]'] => void;

is aa_in([map { cast string => opaque, $_ } qw( one two three )]), 1, "aa_in([one two three])";
is aa_null_in([undef,undef,undef]), 1, "aa_null_in([undef,undef,undef])";

do {
  my @list = (undef,undef,undef);
  aa_out(\@list);
  is_deeply [map { cast opaque => string, $_ } @list], [qw( four five six )], 'aa_out()';
};

do {
  my @list1 = (malloc 32, malloc 32, malloc 32);
  my @list2 = @list1;
  aa_null_out(\@list2);
  is_deeply [@list2], [undef,undef,undef], 'aa_null_out()';
  free $_ for @list1;
};

function [pointer_ret_array_out => 'ra_out'] => [] => 'opaque[3]';
function [pointer_ret_array_null_out => 'ra_null_out'] => [] => 'opaque[3]';

is_deeply [map { cast opaque => string, $_ } @{ ra_out() } ], [qw( seven eight nine )], "ra_out()";
is_deeply ra_null_out(), [undef,undef,undef], 'ra_null_out';
