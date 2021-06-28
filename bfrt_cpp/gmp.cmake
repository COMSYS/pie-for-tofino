# Mostly copied from CADO-NFS (https://gitlab.inria.fr/cado-nfs/cado-nfs/-/tree/master)

# You can force a path to gmp.h using the environment variables GMP, or
# GMP_INCDIR and GMP_LIBDIR
string(COMPARE NOTEQUAL "$ENV{GMP}" "" HAS_GMP_OVERRIDE)
if (HAS_GMP_OVERRIDE)
  message(STATUS "Adding $ENV{GMP} to the search path for Gnu MP")
  set(GMP_INCDIR_HINTS "$ENV{GMP}/include" ${GMP_INCDIR_HINTS})
  set(GMP_INCDIR_HINTS "$ENV{GMP}"         ${GMP_INCDIR_HINTS})
  set(GMP_LIBDIR_HINTS "$ENV{GMP}/lib"     ${GMP_LIBDIR_HINTS})
  set(GMP_LIBDIR_HINTS "$ENV{GMP}/.libs"   ${GMP_LIBDIR_HINTS})
endif()
string(COMPARE NOTEQUAL "$ENV{GMP_INCDIR}" "" HAS_GMP_INCDIR_OVERRIDE)
if (HAS_GMP_INCDIR_OVERRIDE)
  message(STATUS "Adding $ENV{GMP_INCDIR} to the search path for Gnu MP")
  set(GMP_INCDIR_HINTS "$ENV{GMP_INCDIR}" ${GMP_INCDIR_HINTS})
endif()
string(COMPARE NOTEQUAL "$ENV{GMP_LIBDIR}" "" HAS_GMP_LIBDIR_OVERRIDE)
if (HAS_GMP_LIBDIR_OVERRIDE)
  message(STATUS "Adding $ENV{GMP_LIBDIR} to the search path for Gnu MP")
  set(GMP_LIBDIR_HINTS "$ENV{GMP_LIBDIR}"     ${GMP_LIBDIR_HINTS})
endif()

# First try overrides, really. We want cmake to shut up.
if (NOT GMP_INCDIR)
  find_path (GMP_INCDIR gmp.h PATHS ${GMP_INCDIR_HINTS} DOC "Gnu MP headers"
             NO_DEFAULT_PATH NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_PATH
             NO_CMAKE_ENVIRONMENT_PATH NO_CMAKE_SYSTEM_PATH
             NO_CMAKE_FIND_ROOT_PATH)
endif()
if (NOT GMP_INCDIR)
  find_path (GMP_INCDIR gmp.h HINTS ${GMP_INCDIR_HINTS} DOC "Gnu MP headers"
             NO_DEFAULT_PATH)
endif()
if (NOT GMP_INCDIR)
  find_path (GMP_INCDIR gmp.h HINTS ${GMP_INCDIR_HINTS} DOC "Gnu MP headers")
endif()

find_library(GMP_LIB gmp HINTS ${GMP_LIBDIR_HINTS} DOC "Gnu MP library"
             NO_DEFAULT_PATH)
if(NOT GMP_LIBDIR)
  find_library(GMP_LIB gmp HINTS ${GMP_LIBDIR_HINTS} DOC "Gnu MP library")
endif()

# Check that everything was found
set (README_MSG "See the README for more information.")
if (GMP_INCDIR)
  message(STATUS "Using gmp.h from ${GMP_INCDIR}")
else()
  message(FATAL_ERROR "gmp.h cannot be found. ${README_MSG}")
endif()

if(GMP_LIB)
  get_filename_component(GMP_LIBDIR ${GMP_LIB} DIRECTORY)
  get_filename_component(GMP_LIBNAME ${GMP_LIB} NAME)
  message(STATUS "Using Gnu MP library ${GMP_LIBNAME} from ${GMP_LIBDIR}")
else()
  message(FATAL_ERROR "Gnu MP library cannot be found. ${README_MSG}")
endif()
