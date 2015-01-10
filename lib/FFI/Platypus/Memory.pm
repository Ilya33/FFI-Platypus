package FFI::Platypus::Memory;

use strict;
use warnings;
use FFI::Platypus;
use base qw( Exporter );

our @EXPORT_OK = qw( malloc free calloc realloc memcpy memset sizeof );

my $ffi = FFI::Platypus->new;
$ffi->lib(undef);
$ffi->type($_) foreach qw( pointer size_t void int );

$ffi->attach(malloc  => ['size_t']                       => 'pointer' => '$');
$ffi->attach(free    => ['pointer']                      => 'void'    => '$');
$ffi->attach(calloc  => ['size_t', 'size_t']             => 'pointer' => '$$');
$ffi->attach(realloc => ['pointer', 'size_t']            => 'pointer' => '$$');
$ffi->attach(memcpy  => ['pointer', 'pointer', 'size_t'] => 'pointer' => '$$$');
$ffi->attach(memset  => ['pointer', 'int', 'size_t']     => 'pointer' => '$$$');

sub sizeof ($)
{
  $ffi->type($_[0]);
  $ffi->type_meta($_[0])->{size};
}

1;
