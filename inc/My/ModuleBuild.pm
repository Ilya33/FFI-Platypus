package My::ModuleBuild;

use strict;
use warnings;
use base qw( Module::Build );
use ExtUtils::CChecker;
use Capture::Tiny qw( capture_merged );
use File::Spec;
use FindBin ();

my $cc;
my %types;

sub new
{
  my($class, %args) = @_;
  $args{c_source} = 'xs';
  
  $cc ||= ExtUtils::CChecker->new(
    quiet => 0,
    defines_to => File::Spec->catfile($FindBin::Bin, 'xs', 'ffi_pl_config.h'),
  );
  
  $cc->push_include_dirs( File::Spec->catdir($FindBin::Bin, 'xs') );
  
  $class->c_assert('basic_compiler');
  $class->c_assert('basic_int_types');
  
  foreach my $line ($class->c_output)
  {
    if($line =~ /\|(.*?)\|(.*?)\|/)
    {
      $types{$1} = $2;
    }
  }
  
  $class->c_try('int64',
    define => "HAS_INT64_T",
  );
  
  foreach my $header (qw( stdlib stdint sys/types sys/stat unistd ))
  {
    my $source = $class->c_tests->{header};
    $source =~ s/<>/<$header.h>/;
    $class->c_tests->{$header} = $source;
    
    my $define = uc $header;
    $define =~ s/\//_/g;
    
    $class->c_try($header,
      define => "HAS_$define\_H",
    );
  }
  
  my $has_system_ffi = $class->c_try('system_ffi',
    extra_linker_flags => [ '-lffi' ],
    libs => [ '', 'ffi' ],
    define => 'HAS_SYSTEM_FFI',
  );
  
  # TODO: if !$has_system_ffi then build it from source a la FFI::Raw

  $args{extra_linker_flags} = join ' ', @{ $cc->extra_linker_flags };
  
  my $self = $class->SUPER::new(%args);

  $self->add_to_cleanup(
    'build.log',
    '*.core',
    'test-*',
    'xs/ffi_pl_config.h',
  );
  
  $self;
}

sub c_assert
{
  my($class, $name, %args) = @_;
  
  $args{die_on_fail} = 1;
  
  $class->c_try($name, %args);
}

my $out;
sub c_output
{
  wantarray ? split /\n/, $out : $out;
}

sub c_try
{
  my($class, $name, %args) = @_;
  my $diag = $name;
  $diag =~ s/_/ /g;
  
  my $ok;
  
  open my $log, '>>', 'build.log';
  print $log "\n\n\n";
  
  print "check $diag ";
  print $log "check $diag ";
  
  my $source = $class->c_tests->{$name};
  
  $out = capture_merged {
  
    $ok = $cc->try_compile_run(
      diag   => $diag,
      source => $source,
      %args,
    );
  };
  
  if($ok)
  {
    print "ok\n";
    print $log "ok\n$out";
    
    $cc->push_extra_linker_flags(@{ $args{extra_linker_flags} }) if defined $args{extra_linker_flags};
    
  }
  else
  {
    print $log "fail\n$out\n\n:::\n$source\n:::\n";
    print "fail\n";
    print $out if $args{die_on_fail} || $ENV{FFI_PLATYPUS_BUILD_VERBOSE};
    die "unable to compile" if $args{die_on_fail};
  }
  
  close $log;
  
  $ok;
}

my $_tests;
sub c_tests
{
  return $_tests if $_tests;
  
  $_tests = {};

  my $code = '';
  my $name;
  my @data = <DATA>;
  foreach my $line (@data)
  {
    if($line =~ /^\|(.*)\|$/)
    {
      $_tests->{$name} = $code if defined $name;
      $name = $1;
      $code = '';
    }
    else
    {
      $code .= $line;
    }
  }
  
  $_tests->{$name} = $code;
  
  $_tests;
}

1;

__DATA__
|basic_compiler|
int
main(int argc, char *argv[])
{
  return 0;
}

|basic_int_types|
#include <ffi_pl_type_detect.h>

int
main(int argc, char *argv[])
{
  print(char);
  print(signed char);
  print(unsigned char);
  print(short);
  print(unsigned short);
  print(int);
  print(unsigned int);
  print(long);
  print(unsigned long);
  print(size_t);
  return 0;
}

|int64|
#define HAS_INT64_T
#include <ffi_pl_int64.h>
int
main(int argc, char *argv[])
{
  if(sizeof(int64_t) == 8)
    return 0;
  else
    return 1;
}

|header|
#include <>
int main(int argc, char *argv[])
{
  return 0;
}

|system_ffi|
#include <ffi.h>

int
main(int argc, char *argv[])
{
  ffi_cif cif;
  ffi_status status;
  ffi_type args[1];
  
  status = ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 0, &ffi_type_void, &args);

  if(status == FFI_OK)
    return 0;
  else
    return 2;
}
