# SQLite amalgamation, mirroring PCbuild/sqlite3.vcxproj.  The MSVC build
# defines SQLITE_API=__declspec(dllexport) for its sqlite3.dll; here it is
# linked statically, so SQLITE_API keeps sqlite3.h's empty default.
#
# None of these options change sqlite3.h, so consumers (Modules/_sqlite)
# need only the include directory.  SQLITE_OMIT_AUTOINIT is safe because
# the module calls sqlite3_initialize() itself.  The same sources build
# for x64 and x86 (also at _WIN32_WINNT=0x0501 for PY_TARGET_XP: sqlite's
# os_win.c checks the WINNT level and avoids newer APIs).

add_library(pydep_sqlite3 OBJECT "${SQLITE_SRC}/sqlite3.c")
add_library(pydep::sqlite3 ALIAS pydep_sqlite3)
py_third_party_target(pydep_sqlite3)

target_include_directories(pydep_sqlite3 INTERFACE "${SQLITE_SRC}")
target_include_directories(pydep_sqlite3 PRIVATE "${SQLITE_SRC}")
target_compile_definitions(pydep_sqlite3 PRIVATE
  SQLITE_ENABLE_MATH_FUNCTIONS
  SQLITE_ENABLE_FTS4
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_PERCENTILE
  SQLITE_ENABLE_RTREE
  SQLITE_OMIT_AUTOINIT)

# Only kernel32 (linked by default) and the CRT: nothing extra to record.
set_property(TARGET pydep_sqlite3 PROPERTY PY_SYSTEM_LIBS "")
