// newVMConfig.inc for redistributable builds (release/build-release.sh
// copies it over newVM/newVMConfig.inc in its staging copy, never in the
// working tree).
//
// A normal newVMConfig.inc describes the build machine's libraries, and with
// HAVE_MKL or HAVE_IPP the newVM units link MKL and IPP at build time
// ({$Linklib}), so the program will not even start on a machine without
// Intel oneAPI. Here nothing is linked: every newVM routine runs its
// plain-Pascal body (PUREPASCAL, PUREPASCAL_BLAS), and no HAVE_* backend is
// defined. Programs that need a GPU load OpenCL at run time through
// OpenCLAPI, which needs no define. The platform defines come from FPC's own
// macros, so one file serves Windows, Linux and macOS.

{$IFDEF WINDOWS}{$DEFINE PLATFORM_WINDOWS}{$ENDIF}
{$IFDEF DARWIN}{$DEFINE PLATFORM_DARWIN}{$ENDIF}
{$IFDEF LINUX}{$DEFINE PLATFORM_LINUX}{$ENDIF}
{$IFDEF CPUX86_64}{$DEFINE PLATFORM_X86_64}{$ENDIF}
{$IFDEF CPUAARCH64}{$DEFINE PLATFORM_AARCH64}{$ENDIF}

{$DEFINE PUREPASCAL}
{$DEFINE PUREPASCAL_BLAS}
