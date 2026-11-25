#!/bin/sh
# Regenerate Platforms/w64devkit/openssl/generated/ from the OpenSSL source
# pinned in Misc/externals.spdx.json.  Maintainer tool; the build never runs
# it.  See README.md.
#
#   sh Platforms/w64devkit/openssl/regen.sh           replace generated/
#   sh Platforms/w64devkit/openssl/regen.sh --check   diff against generated/
#
# Environment: PERL (Perl 5.10+ executable), MAKE (GNU make), REGEN_KEEP=1
# keeps the temporary directory for inspection.
set -eu

die() { echo "regen.sh: $*" >&2; exit 1; }
usage() { echo "usage: regen.sh [--check]" >&2; exit 2; }

check=0
case $# in
    0) ;;
    1) [ "$1" = --check ] || usage; check=1 ;;
    *) usage ;;
esac

# Configure options.  All of these exist in OpenSSL 3.5.
targets="x86_64:mingw64 i686:mingw"
# no-pinshared: libcrypto is linked into python.dll, python.exe or the
# embedder's own image, which must stay unloadable (FreeLibrary).
opts="no-asm no-uplink no-shared no-module no-engine no-legacy no-quic"
opts="$opts no-pinshared no-apps no-docs no-tests no-makedepend"

# sed, not tr: MSYS shells rewrite a bare "/" argument into a Windows path.
slashes() { printf '%s\n' "$1" | sed 's,\\,/,g'; }

# Make a path usable unquoted (Makefile $(PERL), PERL5OPT): on Windows,
# fall back to its 8.3 short name via Git's cygpath.
nospace() {
    case $1 in
        *' '*)
            cp=$(dirname "$PERL")/cygpath
            if [ -x "$cp" ] || [ -x "$cp.exe" ]; then
                slashes "$("$cp" -m -s "$1")"
            else
                printf '%s\n' "$1"
            fi ;;
        *) printf '%s\n' "$1" ;;
    esac
}

here=$(slashes "$(cd "$(dirname "$0")" && pwd)")
repo=$(slashes "$(cd "$here/../../.." && pwd)")
sbom=$repo/Misc/externals.spdx.json
[ -f "$sbom" ] || die "$sbom not found"
MAKE=${MAKE:-make}

# Perl: $PERL, else perl on PATH, else Git for Windows' MSYS Perl.
if [ -z "${PERL:-}" ]; then
    if command -v perl >/dev/null 2>&1; then
        PERL=perl
    elif git=$(command -v git 2>/dev/null); then
        git=$(slashes "$git")
        for p in "${git%/*}/../usr/bin/perl.exe" "${git%/*}/../../usr/bin/perl.exe"; do
            if [ -x "$p" ]; then PERL=$p; break; fi
        done
    fi
    [ -n "${PERL:-}" ] || die "no Perl found; set PERL"
fi
PERL=$(nospace "$(slashes "$PERL")")
case $PERL in *' '*) die "PERL path contains spaces: $PERL" ;; esac
"$PERL" -e 'exit($] < 5.010)' || die "$PERL is not Perl 5.10 or later"

# The pin, from the SBOM (the single source of truth).
info=$("$PERL" -MJSON::PP -e '
    local $/;
    open my $f, "<", $ARGV[0] or die "$ARGV[0]: $!\n";
    my $d = JSON::PP->new->decode(<$f>);
    my @p = grep { $_->{name} eq "openssl" } @{$d->{packages}};
    @p == 1 or die "expected exactly one openssl package\n";
    my @s = map { $_->{checksumValue} }
            grep { $_->{algorithm} eq "SHA256" } @{$p[0]{checksums}};
    @s == 1 or die "expected exactly one SHA256 checksum\n";
    print "$p[0]{versionInfo}\n$p[0]{downloadLocation}\n$s[0]\n";
' "$sbom") || die "cannot read the openssl pin from $sbom"
version=$(printf '%s\n' "$info" | sed -n 1p)
url=$(printf '%s\n' "$info" | sed -n 2p)
sha256=$(printf '%s\n' "$info" | sed -n 3p | tr A-F a-f)
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+[a-z0-9.-]*$' ||
    die "bad version '$version'"
printf '%s\n' "$url" | grep -Eq '^https://[^ ]+$' || die "bad URL '$url'"
printf '%s\n' "$sha256" | grep -Eq '^[0-9a-f]{64}$' || die "bad SHA256 '$sha256'"
echo "regen.sh: OpenSSL $version"

tmp=$(mktemp -d)
tmp=$(nospace "$(slashes "$tmp")")
case $tmp in *' '*) die "temporary directory contains spaces: $tmp (set TMPDIR)" ;; esac
if [ "${REGEN_KEEP:-}" = 1 ]; then
    echo "regen.sh: keeping $tmp"
else
    trap 'rm -rf "$tmp"' EXIT
    trap 'exit 1' HUP INT TERM
fi

# Download into a new empty directory and verify before extracting.
mkdir "$tmp/download" "$tmp/source" "$tmp/work" "$tmp/stubs"
tarball=$tmp/download/openssl.tar.gz
if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$tarball" "$url" || die "download failed: $url"
else
    wget -q -O "$tarball" "$url" || die "download failed: $url"
fi
got=$(sha256sum "$tarball" | cut -d' ' -f1)
[ "$got" = "$sha256" ] || die "SHA256 mismatch: got $got, expected $sha256"
tar -xzf "$tarball" -C "$tmp/source"
set -- "$tmp/source"/*
[ $# -eq 1 ] && [ -d "$1" ] || die "unexpected tarball layout"
top=$1
[ -f "$top/Configure" ] && [ -f "$top/VERSION.dat" ] || die "not an OpenSSL tree"

# Stubs for modules OpenSSL's scripts use that a minimal Perl (such as Git
# for Windows' MSYS Perl) lacks.  Only missing modules are stubbed.  They
# are passed with -I, and with PERL5OPT for the Perls that Configure and
# make spawn; PERL5LIB is not used because MSYS Perl splits it on ':'.
stub() {
    if ! "$PERL" "-M$1" -e 1 >/dev/null 2>&1; then
        f=$tmp/stubs/$(printf '%s\n' "$1" | sed 's|::|/|g').pm
        mkdir -p "$(dirname "$f")"
        cat >"$f"
        echo "regen.sh: stubbing $1"
    else
        cat >/dev/null
    fi
}
stub Locale::Maketext::Simple <<'EOF'
package Locale::Maketext::Simple;    # stub for IPC::Cmd
sub import {
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::loc"} = sub {
        my $s = shift; my @a = @_;
        $s =~ s/\[_(\d+)\]/$a[$1-1]/g;
        $s;
    };
    *{"${caller}::loc_lang"} = sub {};
}
1;
EOF
stub Pod::Usage <<'EOF'
package Pod::Usage;    # stub for configdata.pm
use Exporter 'import';
our @EXPORT = ('pod2usage');
sub pod2usage {
    my %a = @_ == 1 ? (-exitval => $_[0]) : @_;
    exit($a{-exitval} // 2);
}
1;
EOF
stub ExtUtils::MakeMaker <<'EOF'
package ExtUtils::MakeMaker;    # stub for IPC::Cmd::can_run
our $VERSION = '0';
package MM;
sub maybe_command {
    my ($self, $file) = @_;
    for my $f ($file, "$file.exe") {
        return $f if -f $f && -x _;
    }
    return;
}
1;
EOF
stubs=$tmp/stubs
PERL5OPT="-I$stubs${PERL5OPT:+ $PERL5OPT}"
export PERL5OPT

# Configure each target in a fresh copy of the source and build the
# generated files that extract.pl says libcrypto and libssl need.
work=$tmp/work
for t in $targets; do
    arch=${t%%:*}
    target=${t#*:}
    echo "regen.sh: configuring $target"
    cp -R "$top" "$work/$arch"
    (cd "$work/$arch" && PERL=$PERL "$PERL" -I"$stubs" Configure $target $opts) \
        >"$work/$arch.configure.log" 2>&1 ||
        { cat "$work/$arch.configure.log" >&2; die "Configure $target failed"; }
    "$PERL" -I"$stubs" "$here/extract.pl" dump "$work/$arch" "$work/$arch.json" \
        >"$work/$arch.gen"
    # shellcheck disable=SC2046
    (cd "$work/$arch" && "$MAKE" PERL="$PERL" $(cat "$work/$arch.gen")) \
        >"$work/$arch.make.log" 2>&1 ||
        { cat "$work/$arch.make.log" >&2; die "make failed for $target"; }
done

out=$work/generated
"$PERL" -I"$stubs" "$here/extract.pl" merge "$out" "$top" \
    "$work/x86_64" "$work/x86_64.json" "$work/i686" "$work/i686.json"

optsha=$(printf '%s' "$opts" | sha256sum | cut -d' ' -f1)
{
    echo "version=$version"
    echo "url=$url"
    echo "sha256=$sha256"
    echo "configure_targets=mingw64 mingw"
    echo "configure_options=$opts"
    echo "configure_options_sha256=$optsha"
} >"$out/VERSION"

if [ $check = 1 ]; then
    [ -d "$here/generated" ] || die "$here/generated does not exist"
    if diff -r "$here/generated" "$out"; then
        echo "regen.sh: generated/ is up to date"
    else
        die "generated/ differs from a fresh regeneration"
    fi
else
    rm -rf "$here/generated.new"
    cp -R "$out" "$here/generated.new"
    rm -rf "$here/generated"
    mv "$here/generated.new" "$here/generated"
    echo "regen.sh: wrote $here/generated"
fi
