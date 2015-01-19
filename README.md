# FFI::Platypus

Write Perl bindings to foreign language libraries without XS

# SYNOPSIS

    use FFI::Platypus;
    
    my $ffi = FFI::Platypus->new;
    $ffi->lib(undef); # search libc
    
    # call dynamically
    $ffi->function( puts => ['string'] => 'int' )->call("hello world");
    
    # attach as a xsub and call (much faster)
    $ffi->attach( puts => ['string'] => 'int' );
    puts("hello world");

# DESCRIPTION

Platypus provides an interface for creating FFI based modules in
Perl that call machine code via `libffi`.  This is an alternative
to XS that does not require a compiler.

The declarative interface [FFI::Platypus::Declare](https://metacpan.org/pod/FFI::Platypus::Declare) may be more
suitable, if you do not need the extra power of the OO interface
and you do not mind the namespace pollution.

# CONSTRUCTORS

## new

    my $ffi = FFI::Platypus->new(%options);

Create a new instance of [FFI::Platypus](https://metacpan.org/pod/FFI::Platypus).

Any types defined with this instance will be valid for this
instance only, so you do not need to worry about stepping on
the toes of other CPAN FFI Authors.

Any functions found will be out of the list of libraries
specified with the [lib](https://metacpan.org/pod/FFI::Platypus#lib) attribute.

### options

- lib

    Either a pathname (string) or a list of pathnames (array ref of strings)
    to pre-populate the [lib](https://metacpan.org/pod/FFI::Platypus#lib) attribute.

# ATTRIBUTES

## lib

    $ffi->lib($path1, $path2, ...);
    my @paths = $ffi->lib;

The list of libraries to search for symbols in.

The most portable and reliable way to find dynamic libraries is by using
[FFI::CheckLib](https://metacpan.org/pod/FFI::CheckLib), like this:

    use FFI::CheckLib 0.06;
    $ffi->lib(find_lib_or_die lib => 'archive'); 
      # finds libarchive.so on Linux
      #       libarchive.bundle on OS X
      #       libarchive.dll (or archive.dll) on Windows
      #       cygarchive-13.dll on Cygwin
      #       ...
      # and will die if it isn't found

[FFI::CheckLib](https://metacpan.org/pod/FFI::CheckLib) has a number of options, such as checking for specific
symbols, etc.  You should consult the documentation for that module.

As a special case, if you add `undef` as a "library" to be searched,
[FFI::Platypus](https://metacpan.org/pod/FFI::Platypus) will also search the current process for symbols.
This is mostly useful for finding functions in the standard C library,
without having to know the name of libc for your platform (as it turns
out it is different just about everywhere!).

# METHODS

## type

    $ffi->type($typename);
    $ffi->type($typename => $alias);

Define a type.  The first argument is the native or C name of the type.  The second argument (optional) is an alias name
that you can use to refer to this new type.  See [FFI:Platypus::Type](FFI:Platypus::Type) for legal type definitions.

Examples:

    $ffi->type('sint32'); # oly checks to see that sint32 is a valid type
    $ffi->type('sint32' => 'myint'); # creates an alias myint for sint32
    $ffi->type('bogus'); # dies with appropriate diagnostic

## custom\_type

    $ffi->custom_type($alias => {
      native_type         => $native_type,
      native_to_perl      => $coderef,
      perl_to_native      => $coderef,
      perl_to_native_post => $coderef,
    });

Define a custom type.  See ["FFI::Platypus::Type#Custom Types"](#ffi-platypus-type-custom-types) for details.

## types

    my @types = $ffi->types;
    my @types = FFI::Platypus->types;

Returns the list of types that FFI knows about.  This may be either built in FFI types (example: _sint32_) or
detected C types (example: _signed int_), or types that you have defined using the [type](https://metacpan.org/pod/FFI::Platypus#type) method.

It can also be called as a class method, in which case, no user defined types will be included.

## type\_meta

    my $meta = $ffi->type_meta($type_name);
    my $meta = FFI::Platypus->type_meta($type_name);

Returns a hash reference with the meta information for the given type.

It can also be called as a class method, in which case, you won't be able to get meta data on user defined types.

Examples:

    my $meta = $ffi->type_meta('int');        # standard int type
    my $meta = $ffi->type_meta('int[64]');    # array of 64 ints
    $ffi->type('int[128]' => 'myintarray');
    my $meta = $ffi->type_meta('myintarray'); # array of 128 ints

## function

    my $function = $ffi->function($name => \@argument_types => $return_type);
    my $function = $ffi->function($address => \@argument_types => $return_type);

Returns an object that is similar to a code reference in that it can be called like one.

Caveat: many situations require a real code reference, at the price of a performance
penalty you can get one like this:

    my $function = $ffi->function(...);
    my $coderef = sub { $function->(@_) };

It may be better, and faster to create a real Perl function using the [attach](https://metacpan.org/pod/FFI::Platypus#attach) method.

In addition to looking up a function by name you can provide the address of the symbol
yourself:

    my $address = $ffi->find_symbol('my_functon');
    my $function = $ffi->function($address => ...);

Under the covers this function uses [find\_symbol](https://metacpan.org/pod/FFI::Platypus#find_symbol) when you provide it
with a name rather than an address, but you may have alternative ways of obtaining a function's
address, such as it could be returned as an `opaque` pointer.

Examples:

    my $function = $ffi->function('my_function_name', ['int', 'string'] => 'string');
    my $return_string = $function->(1, "hi there");

## attach

    $ffi->attach($name => \@argument_types => $return_type);
    $ffi->attach([$c_name => $perl_name] => \@argument_types => $return_type);
    $ffi->attach([$address => $perl_name] => \@argument_types => $return_type);

Find and attach a C function as a Perl function as a real live xsub.  The advantage of
attaching a function over using the [function](https://metacpan.org/pod/FFI::Platypus#function) method is that
it is much much much faster since no object resolution needs to be done.  The disadvantage
is that it locks the function and the [FFI::Platypus](https://metacpan.org/pod/FFI::Platypus) instance into memory permanently,
since there is no way to deallocate an xsub.

If just one _$name_ is given, then the function will be attached in Perl with the same
name as it has in C.  The second form allows you to give the Perl function a different
name.  You can also provide an address (the third form), just like with the 
[function](https://metacpan.org/pod/FFI::Platypus#function) method.

Examples:

    $ffi->attach('my_functon_name', ['int', 'string'] => 'string');
    $ffi->attach(['my_c_functon_name' => 'my_perl_function_name'], ['int', 'string'] => 'string');
    my $string1 = my_function_name($int);
    my $string2 = my_perl_function_name($int);

## closure

    my $closure = $ffi->closure($coderef);

Prepares a code reference so that it can be used as a FFI closure (a Perl subroutine that can be called
from C code).  For details on closures, see [FFI::Platypus::Type#Closures](https://metacpan.org/pod/FFI::Platypus::Type#Closures).

## cast

    my $converted_value = $ffi->cast($original_type, $converted_type, $original_value);

The `cast` function converts an existing _$original\_value_ of type
_$original\_type_ into one of type _$converted\_type_.  Not all types are
supported, so care must be taken.  For example, to get the address of a
string, you can do this:

    my $address = $ffi->cast('string' => 'opaque', $string_value);

## attach\_cast

    $ffi->attach_cast("cast_name", $original_type, $converted_type);
    my $converted_value = cast_name($original_value);

This function attaches a cast as a permanent xsub.  This will make it faster
and may be useful if you are calling a particular cast a lot.

## sizeof

    my $size = $ffi->sizeof($type);

Returns the total size of the given type.  For example to get the size of
an integer:

    my $intsize = $ffi->sizeof('int'); # usually 4 or 8 depending on platform

You can also get the size of arrays

    my $intarraysize = $ffi->sizeof('int[64]');

Keep in mind that "pointer" types will always be the pointer / word size
for the platform that you are using.  This includes strings, opaque and
pointers to other types.

This function is not very fast, so you might want to save this value as a
constant, particularly if you need the size in a loop with many
iterations.

## find\_symbol

    my $address = $ffi->find_symbol($name);

Return the address of the given symbol (usually function).  Usually you
can use the [function](https://metacpan.org/pod/FFI::Platypus#function) method or the 
[attach](https://metacpan.org/pod/FFI::Platypus#attach) function directly and will not need
to use this.

# SUPPORT

If something does not work the way you think it should, or if you have a feature
request, please open an issue on this project's GitHub Issue tracker:

[https://github.com/plicease/FFI-Platypus/issues](https://github.com/plicease/FFI-Platypus/issues)

# CONTRIBUTING

If you have implemented a new feature or fixed a bug then you may make a pull request on
this project's GitHub repository:

[https://github.com/plicease/FFI-Platypus/pulls](https://github.com/plicease/FFI-Platypus/pulls)

This project is developed using [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla).  The project's git repository also
comes with `Build.PL` and `cpanfile` files necessary for building, testing 
(and even installing if necessary) without [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla).  Please keep in mind
though that these files are generated so if changes need to be made to those files
they should be done through the project's `dist.ini` file.  If you do use [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla)
and already have the necessary plugins installed, then I encourage you to run
`dzil test` before making any pull requests.  This is not a requirement, however,
I am happy to integrate especially smaller patches that need tweaking to fit the project
standards.  I may push back and ask you to write a test case or alter the formatting of 
a patch depending on the amount of time I have and the amount of code that your patch 
touches.

This project's GitHub repository listed above is not Write-Only.  If you want to
contribute then feel free to browse through the existing issues and see if there is
something you feel you might be good at and tack a whack at the problem.  I frequently
open issues myself that I hope will be accomplished by someone in the future but do
not have time for immediately.

Another good area to help out in is documentation.  I try to make sure that there is
good document coverage, that is there should be documentation describing all the public
features and warnings about common pitfalls, but an outsider's or alternate view point
on such things would be welcome; if you see something confusing or lacks sufficient
detail I encourage documentation only pull requests to improve things.

# SEE ALSO

- [FFI::Platypus::Declare](https://metacpan.org/pod/FFI::Platypus::Declare)

    Declarative interface to [FFI::Platypus](https://metacpan.org/pod/FFI::Platypus).

- [FFI::Platypus::Type](https://metacpan.org/pod/FFI::Platypus::Type)

    Type definitions for [FFI::Platypus](https://metacpan.org/pod/FFI::Platypus).

- [FFI::Platypus::Memory](https://metacpan.org/pod/FFI::Platypus::Memory)

    memory functions for FFI.

- [FFI::CheckLib](https://metacpan.org/pod/FFI::CheckLib)

    Find dynamic libraries in a portable way.

- [FFI::TinyCC](https://metacpan.org/pod/FFI::TinyCC)

    JIT compiler for FFI.

- [Convert::Binary::C](https://metacpan.org/pod/Convert::Binary::C)

    An interface for interacting with C `struct` types.  Unfortunately it appears to
    be unmaintained, and has a failing pod test, so I cannot recommend it for use 
    by CPAN modules.

- [pack](https://metacpan.org/pod/perlfunc#pack) and [unpack](https://metacpan.org/pod/perlfunc#unpack)

    Native to Perl functions that can be used to decode C `struct` types.

- [FFI::Raw](https://metacpan.org/pod/FFI::Raw)

    Alternate interface to libffi with fewer features.  It notably lacks the ability to
    create real xsubs, which may make [FFI::Platypus](https://metacpan.org/pod/FFI::Platypus) much faster.  Also lacking are
    pointers to native types, arrays and custom types.  In its favor, it has been around
    for longer that Platypus, and has been battle tested to some success.

- [Win32::API](https://metacpan.org/pod/Win32::API)

    Microsoft Windows specific FFI style interface.

- [Ctypes](https://gitorious.org/perl-ctypes)

    Ctypes was intended as a FFI style interface for Perl, but was never part of CPAN,
    and at least the last time I tried it did not work with recent versions of Perl.

- [FFI](https://metacpan.org/pod/FFI)

    Foreign function interface based on (nomenclature is everything) FSF's `ffcall`.
    It hasn't worked for quite some time, and `ffcall` is no longer supported or
    distributed.

- [C::DynaLib](https://metacpan.org/pod/C::DynaLib)

    Another FFI for Perl that doesn't appear to have worked for a long time.

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
