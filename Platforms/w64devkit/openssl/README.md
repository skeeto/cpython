# Pregenerated OpenSSL build files

OpenSSL's build runs Perl to configure the tree and to generate headers and
sources.  So that the w64devkit CMake build never needs Perl, the outputs
are committed here:

- `generated/`: every generated file libcrypto and libssl need, at the same
  relative paths as in an OpenSSL tree.  `include/openssl/configuration.h`
  and `include/crypto/bn_conf.h` contain both architectures, selected with
  `#if defined(_WIN64)`.  The CMake build puts these include directories
  before the source tree's.
- `generated/openssl-sources.cmake`: plain `set()` calls (all `OSSL_*`)
  listing the sources, grouped by include directories and defines, plus the
  common defines, the system libraries and what `crypto/buildinf.h` must
  define.  Set `OSSL_SOURCE_DIR` and `OSSL_GENERATED_DIR` before including
  it.
- `generated/VERSION`: the OpenSSL version, URL and SHA256, and the
  Configure options with their hash.

The pin comes from `Misc/externals.spdx.json`.  After changing it, or the
options in `regen.sh`, regenerate from the repository root:

    sh Platforms/w64devkit/openssl/regen.sh

The script downloads and verifies the tarball, runs `Configure` for the
`mingw64` and `mingw` targets in fresh copies, builds the generated files
with `make`, and runs `extract.pl`.  `extract.pl` stops on anything
unexpected: assembly sources, compiler flags or defines outside its
allowlists, or generated files that differ between the targets (other than
the two above).

To check that `generated/` matches a fresh regeneration without changing it
(it exits non-zero on any difference):

    sh Platforms/w64devkit/openssl/regen.sh --check

## Requirements

- Perl 5.10 or later.  Under w64devkit, `regen.sh` finds Git for Windows'
  MSYS Perl next to `git`; or set `PERL`.  It stubs the modules that Perl
  lacks (Locale::Maketext::Simple, Pod::Usage, ExtUtils::MakeMaker).
- GNU make, `sha256sum`, `tar`, and `curl` or `wget`.  w64devkit has these.

If that does not work, run the same command on Linux, which needs only
`perl`, `make` and `curl`.  The output should not depend on the host; run
`--check` on Windows afterward to confirm.
