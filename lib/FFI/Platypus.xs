#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"

#include <ffi.h>
#include <ffi_pl.h>

typedef const char *ffi_pl_string;
typedef enum { FFI_PL_LANGUAGE_NONE, FFI_PL_LANGUAGE_C } ffi_pl_language;
typedef enum { FFI_PL_REF_NONE, FFI_PL_REF_POINTER } ffi_pl_ref_type;;

typedef struct _ffi_pl_type {
  ffi_pl_language  language;
  const char      *name;
  ffi_type        *ffi_type;
  int              refcount;
  ffi_pl_ref_type  reftype;
} ffi_pl_type;

typedef struct _ffi_pl_signature {
  ffi_pl_type  *return_type;
  int           argument_count;
  ffi_pl_type **argument_types;
  ffi_cif       ffi_cif;
  ffi_type    **ffi_type;
  int           refcount;
} ffi_pl_signature;

typedef struct _ffi_pl_lib {
  const char *path_name;
  ffi_pl_system_library_handle *handle;
  int refcount;
} ffi_pl_lib;

typedef struct _ffi_pl_sub {
  const char       *perl_name;
  const char       *lib_name;
  ffi_pl_signature *signature;
  ffi_pl_lib       *lib;
  CV               *cv;
  void             *function;
  void             *mswin32_real_library_handle;
} ffi_pl_sub;

static ffi_pl_type *ffi_pl_type_inc(ffi_pl_type *type)
{
  type->refcount++;
  return type;
}

static void ffi_pl_type_dec(ffi_pl_type *type)
{
  type->refcount--;
  if(type->refcount)
    return;
  Safefree(type);
}

static ffi_pl_signature *ffi_pl_signature_inc(ffi_pl_signature *signature)
{
  int i;
  
  ffi_pl_type_inc(signature->return_type);
  for(i=0; i<signature->argument_count; i++)
    ffi_pl_type_inc(signature->argument_types[i]);

  signature->refcount++;
  return signature;
}

static void ffi_pl_signature_dec(ffi_pl_signature *signature)
{
  int i;

  ffi_pl_type_dec(signature->return_type);
  for(i=0; i<signature->argument_count; i++)
    ffi_pl_type_dec(signature->argument_types[i]);  
  
  signature->refcount--;
  if(signature->refcount)
    return;
  Safefree(signature->argument_types);
  Safefree(signature->ffi_type);
  Safefree(signature);
}

static ffi_pl_lib *ffi_pl_lib_inc(ffi_pl_lib *lib)
{
  lib->refcount++;
  return lib;
}

static int ffi_pl_lib_dec(ffi_pl_lib *lib)
{
  int ret;
  
  lib->refcount--;
  if(lib->refcount)
    return 0;

  dlclose(lib->handle);
  
  if(lib->path_name != NULL)
    Safefree(lib->path_name);
  Safefree(lib);
  
  return ret;
}

static HV *meta = NULL;

XS(ffi_pl_sub_call)
{
  char key[16];
  ffi_pl_sub *sub;
  SV **sv;
  int i;
  void **arguments;
  char *scratch;
  ffi_arg result;
  
  dVAR; dXSARGS;

  /* uncomment to send a signal 2 to debug
     this call */
  /* ffi_pl_debug_break(); */
  
  snprintf(key, sizeof(key), "%p", cv);
  sv = hv_fetch(meta, key, strlen(key), 0);
  if(sv == NULL)
  {
    croak("error finding metadata for %p", cv);
    XSRETURN_EMPTY;
  }
  else
  {
    sub = INT2PTR(ffi_pl_sub*, SvIV(*sv));
    
    if(sub->signature->argument_count != items)
      croak("Wrong number of arguments");

#ifdef HAS_ALLOCA
    arguments = alloca(sub->signature->argument_count * sizeof(void*));
    scratch   = alloca(sub->signature->argument_count * FFI_SIZEOF_ARG);
#else    
    Newx(arguments, sub->signature->argument_count, void*);
    Newx(scratch,   sub->signature->argument_count * FFI_SIZEOF_ARG, char);
#endif
#ifdef FFI_PLATYPUS_DEBUG
    memset(arguments, 0, sub->signature->argument_count * sizeof(void*));
    memset(scratch,   0, sub->signature->argument_count * FFI_SIZEOF_ARG);
#endif
      
    for(i=0; i < sub->signature->argument_count; i++)
    {
      arguments[i] = &scratch[i*FFI_SIZEOF_ARG];
      switch(sub->signature->argument_types[i]->reftype)
      {
        case FFI_PL_REF_NONE:
          ffi_pl_sv2ffi(arguments[i], ST(i), sub->signature->argument_types[i]);
          break;
        case FFI_PL_REF_POINTER:
          if(!SvOK(ST(i)))
          {
            *((void**)arguments[i]) = NULL;
          }
          else if(SvROK(ST(i)))
          {
            void *ptr;
#ifdef HAS_ALLOCA
            ptr = alloca(FFI_SIZEOF_ARG);
#else
            Newx(ptr, FFI_SIZEOF_ARG, char); /* TODO: memory leak */
#endif
            ffi_pl_sv2ffi(ptr, SvRV(ST(i)), sub->signature->argument_types[i]);
            *((void**)arguments[i]) = ptr;
          }
          else
          {
            *((void**)arguments[i]) = INT2PTR(void *, SvIV(ST(i)));
          }
        break;
      }
    }

#ifdef FFI_PLATYPUS_DEBUG
    fprintf(stderr,   "# ffi_call:\n");
    for(i=0; i < sub->signature->argument_count; i++)
    {
      fprintf(stderr, "#   arg %02d = %016lx [%p]\n", i, *((unsigned long int*)((void*)&scratch[i*FFI_SIZEOF_ARG])), &scratch[i*FFI_SIZEOF_ARG]);
    }
#endif
    
    ffi_call(&sub->signature->ffi_cif, sub->function, &result, arguments);
    
#ifdef FFI_PLATYPUS_DEBUG
    fprintf(stderr,   "#   ret =    %016lx [%p]\n", *((unsigned long int*)((void*)&result)), &result);
#endif

    for(i=0; i < sub->signature->argument_count; i++)
    {
      switch(sub->signature->argument_types[i]->reftype)
      {
        case FFI_PL_REF_NONE:
          /* do nothing */
          break;
        case FFI_PL_REF_POINTER:
          /* TODO */
          break;
      }
    }
    
#ifndef HAS_ALLOCA
    Safefree(arguments);
    Safefree(scratch);
#endif

    if(sub->signature->return_type->ffi_type->type == FFI_TYPE_VOID
    && sub->signature->return_type->reftype == FFI_PL_REF_NONE)
    {
      XSRETURN_EMPTY;
    }
    else
    {
      switch(sub->signature->return_type->reftype)
      {
        case FFI_PL_REF_NONE:
          ST(0) = sv_newmortal();
          ffi_pl_ffi2sv(ST(0), (&result), sub->signature->return_type);
          XSRETURN(1);
          break;
        case FFI_PL_REF_POINTER:
          if(sub->signature->return_type->ffi_type->type == FFI_TYPE_VOID)
          {
            void *ptr = ((void*)result);
            if(ptr == NULL)
              ST(0) = &PL_sv_undef;
            else
            {
              ST(0) = sv_2mortal(newSViv(PTR2IV(ptr)));
            }
          }
          /* TODO */
          break;
      }
    }
  }

}

MODULE = FFI::Platypus   PACKAGE = FFI::Platypus

BOOT:
     PERL_MATH_INT64_LOAD_OR_CROAK;

ffi_pl_sub *
_ffi_sub(lib, lib_name, perl_name, signature)
    ffi_pl_lib *lib
    const char *lib_name
    const char *perl_name
    ffi_pl_signature *signature
  PREINIT:
    char key[16];
    CV *new_cv;
    ffi_pl_sub *new_sub;
    void *function;
    const char *path_name;
  CODE:
    function = dlsym(lib->handle, lib_name);

    if(function != NULL)
    {
      Newx(new_sub, 1, ffi_pl_sub);

      if(dlsym_win32_meta(&path_name, &new_sub->mswin32_real_library_handle))
      {
        /* nothing */
      }
      else
      {
        /* TODO: "perl_exe" should be $ARGV[0] */
        path_name = lib->path_name != NULL ? lib->path_name : "perl_exe";
        new_sub->mswin32_real_library_handle = NULL;
      }
    
      /* TODO: hook onto the destruction of the cv to free this stuff */
      new_sub->cv        = newXS(perl_name, ffi_pl_sub_call, path_name);
      /* TODO: undef for perl_name should be anonymous sub */
      new_sub->perl_name = savepv(perl_name);
      new_sub->lib_name  = savepv(lib_name);
      new_sub->signature = ffi_pl_signature_inc(signature);
      new_sub->lib       = ffi_pl_lib_inc(lib);
      new_sub->function  = function;
    
      if(meta == NULL)
      {
        meta = get_hv("FFI::Platypus::_meta", GV_ADD);
      }
      snprintf(key, sizeof(key), "%p", new_sub->cv);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"
      hv_store(meta, key, strlen(key), newSViv(PTR2IV(new_sub)), 0);
#pragma clang diagnostic pop
      RETVAL = new_sub;
    }
    else
    {
      /* TODO: include lib name in this diagnostic */
      croak("unable to find symbol %s", lib_name);
    }
  OUTPUT:
    RETVAL

ffi_pl_type *
_ffi_type(language, name)
    ffi_pl_language language
    const char *name
  PREINIT:
    ffi_pl_type *new_type;
    int bad;
  CODE:
    bad = 0;
    Newx(new_type, 1, ffi_pl_type);
    new_type->reftype = FFI_PL_REF_NONE;
    if(name[0]=='*')
    {
      /* 
        TODO: the name method should return
              with the pointer prefix (?)
      */
      name++;
      new_type->reftype = FFI_PL_REF_POINTER;
    }
    
    if(language == FFI_PL_LANGUAGE_NONE)
    {
      ffi_pl_str_type2ffi_type(new_type, name);
    }
    else if(language == FFI_PL_LANGUAGE_C)
    {
      ffi_pl_str_c_type2ffi_type(new_type, name);
    }
    else
    {
      croak("Unknown language");
      bad = 1;
    }
    
    if(bad)
    {
      Safefree(new_type);
      RETVAL = NULL;
    }
    else
    {
      new_type->language = language;
      new_type->refcount = 1;
      RETVAL = new_type;
    }
  OUTPUT:
    RETVAL

ffi_pl_signature *
ffi_signature(return_type, ...)
    ffi_pl_type *return_type
  PREINIT:
    ffi_pl_signature *new_signature;
    int i;
    int bad;
    ffi_status status;
    ffi_pl_type *tmp;
    ffi_type *libffi_return_type;
  CODE:
    bad = 0;
    for(i = 1; i < items; i++)
    {
      if(!sv_isobject(ST(i)) || !sv_derived_from(ST(i), "FFI::Platypus::Type"))
      {
        croak("ffi_signature takes a list of ffi_type");
        bad = 1;
        break;
      }
      tmp = INT2PTR(ffi_pl_type*, SvIV((SV*)SvRV(ST(i))));
      if(tmp->ffi_type->type == FFI_TYPE_VOID && tmp->reftype != FFI_PL_REF_POINTER)
      {
        croak("void is an illegal argument type");
        bad = 1;
        break;
      }
    }
    
    if(!bad)
    {
      Newx(new_signature, 1, ffi_pl_signature);
      new_signature->refcount = 1;
      new_signature->return_type = ffi_pl_type_inc(return_type);
      new_signature->argument_count = items - 1;
      Newx(new_signature->argument_types, new_signature->argument_count, ffi_pl_type*);
      Newx(new_signature->ffi_type, new_signature->argument_count, ffi_type*);
      for(i=0; i < new_signature->argument_count; i++)
      {
        new_signature->argument_types[i] = ffi_pl_type_inc(INT2PTR(ffi_pl_type*, SvIV((SV*)SvRV(ST(i+1)))));
        switch(new_signature->argument_types[i]->reftype)
        {
          case FFI_PL_REF_NONE:
            new_signature->ffi_type[i] = new_signature->argument_types[i]->ffi_type;
            break;
          case FFI_PL_REF_POINTER:
            new_signature->ffi_type[i] = &ffi_type_pointer;
            break;
        }
      }
      switch(new_signature->return_type->reftype)
      {
        case FFI_PL_REF_NONE:
          libffi_return_type = new_signature->return_type->ffi_type;
          break;
        case FFI_PL_REF_POINTER:
          libffi_return_type = &ffi_type_pointer;
          break;
      }
      status = ffi_prep_cif(
        &new_signature->ffi_cif,              /* ffi_cif* */
        FFI_DEFAULT_ABI,                      /* ffi_abi */
        new_signature->argument_count,        /* unsigned int */
        libffi_return_type,                   /* ffi_type *rtype */
        new_signature->ffi_type               /* ffi_type **atype */
      );
      if(status != FFI_OK)
      {
        ffi_pl_signature_dec(new_signature);
        if(status == FFI_BAD_TYPEDEF)
          croak("bad typedef");
        else if(status == FFI_BAD_ABI)
          croak("invalid ABI");
        else
          croak("unknown error with ffi_prep_cif");
      }
      else
      {
        RETVAL = new_signature;
      }
    }
  OUTPUT:
    RETVAL

ffi_pl_lib *
ffi_lib(filename, ...)
    ffi_pl_string filename;
  PREINIT:
    int flags;
    void *handle;
    ffi_pl_lib *new_lib;
  CODE:
#if defined(_WIN32) || defined (__CYGWIN__)
    flags = 0;
#else
    flags = RTLD_LAZY; /* TODO: additional arguments can specify flags */
#endif
    handle = dlopen(filename, flags);
    if(handle == NULL)
    {
      croak("error in dlopen(%s,%d): %s", filename != NULL ? filename : "undef", flags, dlerror()); 
    }
    else
    {
      Newx(new_lib, 1, ffi_pl_lib);
      new_lib->refcount = 1;
      new_lib->path_name = filename != NULL ? savepv(filename) : NULL;
      new_lib->handle = handle;
      RETVAL = new_lib;
    }
  OUTPUT:
    RETVAL
    

MODULE = FFI::Platypus   PACKAGE = FFI::Platypus::Type

size_t
size(self)
    ffi_pl_type *self
  CODE:
    RETVAL = self->ffi_type->size;
  OUTPUT:
    RETVAL

ffi_pl_language
language(self)
    ffi_pl_type *self
  CODE:
    RETVAL = self->language;
  OUTPUT:
    RETVAL

const char *
name(self)
    ffi_pl_type *self
  CODE:
    RETVAL = self->name;
  OUTPUT:
    RETVAL

int
_libffi_type(self)
    ffi_pl_type *self
  CODE:
    RETVAL = self->ffi_type->type;
  OUTPUT:
    RETVAL

int
_refcount(self)
    ffi_pl_type *self
  CODE:
    RETVAL = self->refcount;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    ffi_pl_type *self
  CODE:
    ffi_pl_type_dec(self);

MODULE = FFI::Platypus   PACKAGE = FFI::Platypus::Signature

ffi_pl_type *
return_type(self)
    ffi_pl_signature *self
  CODE:
    RETVAL = ffi_pl_type_inc(self->return_type);
  OUTPUT:
    RETVAL

int
argument_count(self)
    ffi_pl_signature *self
  CODE:
    RETVAL = self->argument_count;
  OUTPUT:
    RETVAL

ffi_pl_type *
argument_type(self, index)
    ffi_pl_signature *self
    unsigned int index
  CODE:
    if(index >= self->argument_count)
      croak("no such argument index %d (max is %d)", index, self->argument_count-1);
    else
      RETVAL = ffi_pl_type_inc(self->argument_types[index]);
  OUTPUT:
    RETVAL

int
_refcount(self)
    ffi_pl_signature *self
  CODE:
    RETVAL = self->refcount;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    ffi_pl_signature *self
  CODE:
    ffi_pl_signature_dec(self);

MODULE = FFI::Platypus   PACKAGE = FFI::Platypus::Lib

ffi_pl_string
path_name(self)
    ffi_pl_lib *self
  CODE:
    RETVAL = self->path_name;
  OUTPUT:
    RETVAL

void *
has_symbol(self, name)
    ffi_pl_lib *self
    const char *name
  CODE:
    RETVAL = dlsym(self->handle, name);
    dlsym_win32_meta(NULL,NULL);
  OUTPUT:
    RETVAL

int
_refcount(self)
    ffi_pl_lib *self
  CODE:
    RETVAL = self->refcount;
  OUTPUT:
    RETVAL

void *
_handle(self)
    ffi_pl_lib *self
  CODE:
    dlclose(self->handle);
    RETVAL = self->handle;
  OUTPUT:
    RETVAL

void
DESTROY(self)
    ffi_pl_lib *self
  CODE:
    /* TODO: check return value */
    ffi_pl_lib_dec(self);

MODULE = FFI::Platypus   PACKAGE = FFI::Platypus::Sub
