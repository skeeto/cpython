#!/usr/bin/env perl
# Extract libcrypto/libssl build information from configured OpenSSL trees
# and produce the pregenerated tree used by the w64devkit CMake build.
#
#   perl extract.pl dump TREE OUT.json
#       Load TREE/configdata.pm, compute the complete source lists for
#       libcrypto and libssl (including the noinst static libraries they
#       embed), per-source include dirs and defines, the global defines,
#       system libraries and the generated files those sources need.
#       Writes OUT.json and prints the generated files that "make" must
#       build, one per line.  Dies on anything outside the allowlists.
#
#   perl extract.pl merge OUTDIR SRCDIR X64TREE X64.json X86TREE X86.json
#       Copy the generated files from both (already built) trees into
#       OUTDIR, merging the two files allowed to differ with _WIN64
#       conditionals, and write OUTDIR/openssl-sources.cmake.
#
# Only core Perl modules are used.  configdata.pm itself needs Pod::Usage,
# so run this with the same -I stub directory that regen.sh creates.

use strict;
use warnings;
use JSON::PP ();
use File::Path qw(make_path);
use File::Basename qw(dirname basename);

# ----------------------------------------------------------------------
# Allowlists.  A version bump that introduces anything new fails here,
# so a human looks at it before it lands in the CMake build.

# Defines Configure may put on every libcrypto/libssl compile line.
my %ALLOWED_DEFINE = map { $_ => 1 } qw(
    L_ENDIAN OPENSSL_PIC OPENSSL_BUILDING_OPENSSL NDEBUG
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN _MT
);
# Defines dropped here; the CMake build supplies them via a force-included
# header (ossl_dirs.h).
my %DROPPED_DEFINE = map { $_ => 1 } qw(OPENSSLDIR ENGINESDIR MODULESDIR);
# Per-object or per-library defines (none expected for libcrypto/libssl).
my %ALLOWED_OBJ_DEFINE = ();
# Compiler flags (informational only; CMake chooses its own).
my %ALLOWED_CFLAG = map { $_ => 1 } qw(-m64 -m32 -Wall -O3 -fomit-frame-pointer);
# System libraries.
my %ALLOWED_LIB = map { $_ => 1 } qw(ws2_32 gdi32 crypt32 advapi32 user32 bcrypt);
# Sources excluded from the lists.
my %EXCLUDED_SOURCE = (
    'crypto/dllmain.c' => 'the build supplies its own TLS callback',
);
# Generated files not shipped in generated/ (CMake writes them).
my %EXCLUDED_GENERATED = (
    'crypto/buildinf.h' => 'written by CMake',
);
# Generated files that may differ between x86_64 and i686.
my %MERGEABLE = map { $_ => 1 } qw(
    include/openssl/configuration.h
    include/crypto/bn_conf.h
);
# Files created by Configure itself rather than by a Makefile rule.
my @CONFIGURE_OUTPUTS = qw(include/openssl/configuration.h);

my @ROOTS = qw(libcrypto libssl);

# ----------------------------------------------------------------------

sub slurp {
    my ($f) = @_;
    open my $fh, '<:raw', $f or die "extract.pl: cannot read $f: $!\n";
    local $/;
    my $s = <$fh>;
    return $s;
}

sub spew {
    my ($f, $s) = @_;
    make_path(dirname($f));
    open my $fh, '>:raw', $f or die "extract.pl: cannot write $f: $!\n";
    print $fh $s;
    close $fh or die "extract.pl: cannot write $f: $!\n";
}

sub flag_tokens {
    map { defined($_) && length($_) ? split(' ', $_) : () }
    map { ref($_) eq 'ARRAY' ? @$_ : $_ } @_;
}

sub uniq {
    my %s;
    grep { !$s{$_}++ } @_;
}

# Turn -D tokens into define strings, dropping and validating.
sub parse_defines {
    my ($what, @tok) = @_;
    my @out;
    for my $t (@tok) {
        $t =~ /^-D(\w+)(?:=(.*))?$/
            or die "extract.pl: $what: unexpected preprocessor flag '$t'\n";
        my ($name, $val) = ($1, $2);
        next if $DROPPED_DEFINE{$name};
        $ALLOWED_DEFINE{$name}
            or die "extract.pl: $what: define '$name' is not in the allowlist\n";
        push @out, defined $val ? "$name=$val" : $name;
    }
    return uniq(@out);
}

# ----------------------------------------------------------------------
# dump

sub cmd_dump {
    my ($tree, $out) = @_;
    my $cd = "$tree/configdata.pm";
    -f $cd or die "extract.pl: $cd not found\n";
    require $cd;
    no warnings 'once';
    my %config = %configdata::config;
    my %target = %configdata::target;
    my %ui = %configdata::unified_info;

    # Global flags, mirroring Configurations/unix-Makefile.tmpl
    # (CNF_CPPFLAGS, LIB_CPPFLAGS, CPPFLAGS).
    my @cpp = flag_tokens(
        $target{lib_cppflags}, $target{shared_cppflag},
        (map { "-D$_" } @{$target{lib_defines} // []},
                        @{$target{shared_defines} // []},
                        @{$config{lib_defines} // []},
                        @{$config{shared_defines} // []}),
        (map { "-I$_" } @{$target{lib_includes} // []},
                        @{$target{shared_includes} // []},
                        @{$config{lib_includes} // []},
                        @{$config{shared_includes} // []}),
        $config{lib_cppflags}, $config{shared_cppflag},
        # CNF_CPPFLAGS
        $target{cppflags},
        (map { "-D$_" } @{$target{defines} // []}, @{$config{defines} // []}),
        (map { "-I$_" } @{$target{includes} // []}, @{$config{includes} // []}),
        $config{cppflags},
        # CPPFLAGS
        (map { "-D$_" } @{$config{CPPDEFINES} // []}),
        (map { "-I$_" } @{$config{CPPINCLUDES} // []}),
        $config{CPPFLAGS},
    );
    my @defines = parse_defines('global flags', @cpp);

    my @cflags = flag_tokens(
        $target{lib_cflags}, $target{shared_cflag},
        $config{lib_cflags}, $config{shared_cflag},
        $target{cflags}, $config{cflags}, $config{CFLAGS},
    );
    for (@cflags) {
        $ALLOWED_CFLAG{$_}
            or die "extract.pl: compiler flag '$_' is not in the allowlist\n";
    }

    my @libs;
    for (flag_tokens($target{ex_libs}, $config{ex_libs})) {
        /^-l(\w+)$/ or die "extract.pl: unexpected ex_libs entry '$_'\n";
        $ALLOWED_LIB{$1}
            or die "extract.pl: system library '$1' is not in the allowlist\n";
        push @libs, $1;
    }
    @libs = uniq(@libs);

    # Walk the libraries.  Sources of a library are objects or noinst
    # static libraries (embedded); depends that are noinst libraries are
    # embedded too.  Installed libraries (libcrypto for libssl) are not.
    my %noinst = map { $_ => 1 }
        grep { ($ui{attributes}{libraries}{$_} // {})->{noinst} }
        @{$ui{libraries}};
    my (@objs, %seenlib, %seenobj);
    my $walk;
    $walk = sub {
        my ($root, $lib) = @_;
        return if $seenlib{$lib}++;
        for my $s (@{$ui{sources}{$lib} // []}) {
            if ($noinst{$s}) {
                $walk->($root, $s);
            } elsif ($s =~ /\.o$/ && $ui{sources}{$s}) {
                die "extract.pl: object $s appears twice\n" if $seenobj{$s}++;
                push @objs, [$root, $lib, $s];
            } else {
                die "extract.pl: unexpected source '$s' of $lib\n";
            }
        }
        for my $d (@{$ui{depends}{$lib} // []}) {
            $walk->($root, $d) if $noinst{$d};
        }
    };
    $walk->($_, $_) for @ROOTS;
    for my $r (@ROOTS) {
        for (@{$ui{shared_sources}{$r} // []}) {
            warn "extract.pl: note: ignoring shared source $_ of $r\n";
        }
    }

    my (%want, @buildinf);
    my $want;
    $want = sub {
        my ($f) = @_;
        return unless $ui{generate}{$f} && $f =~ /\.[ch]$/;
        return if $want{$f}++;
        $want->($_) for @{$ui{depends}{$f} // []};
    };

    my @sources;
    for my $o (@objs) {
        my ($root, $lib, $obj) = @$o;
        my @src = @{$ui{sources}{$obj}};
        @src == 1 or die "extract.pl: $obj has sources @src\n";
        my $src = $src[0];
        if ($src =~ /\.(S|s|asm)$/i || ($ui{generate}{$src} // [''])->[0] =~ /\.pl$/) {
            die "extract.pl: $src is assembly/perlasm; no-asm must give pure C\n";
        }
        $src =~ /\.c$/ or die "extract.pl: unexpected source type $src\n";
        next if $EXCLUDED_SOURCE{$src};
        my @incs = (@{$ui{includes}{$obj} // []}, @{$ui{includes}{$lib} // []});
        my @odefs = (@{$ui{defines}{$obj} // []}, @{$ui{defines}{$lib} // []});
        for (@odefs) {
            my ($n) = /^(\w+)/;
            $ALLOWED_OBJ_DEFINE{$n}
                or die "extract.pl: $src: per-object define '$_' is not in the allowlist\n";
        }
        my $gen = $ui{generate}{$src} ? JSON::PP::true : JSON::PP::false;
        if ($gen) {
            $ui{generate}{$src}[0] =~ /\.c\.in$/
                or die "extract.pl: generated source $src is not made from a .c.in\n";
            $want->($src);
        }
        for my $d (@{$ui{depends}{$obj} // []}) {
            if ($EXCLUDED_GENERATED{$d}) {
                push @buildinf, { source => $src, header => $d, includes => [@incs] };
                next;
            }
            $want->($d);
        }
        push @sources, {
            src => $src, library => $root, owner => $lib, object => $obj,
            generated => $gen, includes => [@incs], defines => [@odefs],
        };
    }
    # CMake keys source properties by file, so each source must appear once.
    my %once;
    $once{$_->{src}}++ and die "extract.pl: $_->{src} is compiled more than once\n"
        for @sources;
    $want->($_) for grep { /\.[ch]$/ } @{$ui{depends}{''} // []};
    delete $want{$_} for keys %EXCLUDED_GENERATED;
    my @make = sort keys %want;
    my @generated = sort(uniq(@make, @CONFIGURE_OUTPUTS));

    makefile_check($tree, \@sources, \@defines, \@cflags, \@objs);

    my %data = (
        target => $target{target} // $config{target},
        platform => $config{target},
        sys_id => $target{sys_id},
        defines => [@defines],
        cflags => [@cflags],
        ex_libs => [@libs],
        sources => [@sources],
        generated => [@generated],
        make => [@make],
        buildinf => [@buildinf],
        tree => $tree,
    );
    spew($out, JSON::PP->new->canonical->pretty->encode(\%data));
    print "$_\n" for @make;
}

# Cross-check the computed information against the generated Makefile,
# which is what OpenSSL itself would build with.
sub makefile_check {
    my ($tree, $sources, $defines, $cflags, $objs) = @_;
    my $mk = slurp("$tree/Makefile");
    $mk =~ s/\r//g;
    $mk =~ s/\\\n/ /g;
    my %var;
    for (split /\n/, $mk) {
        $var{$1} = $2 if /^([A-Z_][A-Z0-9_]*)=(.*)$/;
    }
    my $expand;
    $expand = sub {
        my ($s, $depth) = @_;
        die "extract.pl: Makefile variable recursion\n" if $depth > 20;
        $s =~ s/-D(OPENSSLDIR|ENGINESDIR|MODULESDIR)=\S+//g;
        $s =~ s/\$\((\w+)\)/$expand->($var{$1} \/\/ '', $depth + 1)/ge;
        return $s;
    };
    my @mkdef = parse_defines('Makefile LIB_CPPFLAGS',
                              split(' ', $expand->($var{LIB_CPPFLAGS}, 0)));
    "@{[sort @mkdef]}" eq "@{[sort @$defines]}"
        or die "extract.pl: Makefile defines (@mkdef) differ from computed (@$defines)\n";
    my @mkcf = split(' ', $expand->($var{LIB_CFLAGS}, 0));
    "@{[sort @mkcf]}" eq "@{[sort @$cflags]}"
        or die "extract.pl: Makefile LIB_CFLAGS (@mkcf) differ from computed (@$cflags)\n";

    # Static library contents.
    for my $root (@ROOTS) {
        $mk =~ /^\Q$root\E\.a:\s*(.*)$/m
            or die "extract.pl: no rule for $root.a in Makefile\n";
        my %mkobj = map { $_ => 1 } grep { /\.o(bj)?$/ } split(' ', $1);
        my %ours = map { (my $o = $_->[2]) =~ s/\.o$//; ($o => 1) }
                   grep { $_->[0] eq $root } @$objs;
        my %mko = map { (my $o = $_) =~ s/\.o(bj)?$//; ($o => 1) } keys %mkobj;
        for (sort keys %mko) {
            $ours{$_} or die "extract.pl: Makefile puts $_ in $root.a but extract.pl does not\n";
        }
        for (sort keys %ours) {
            $mko{$_} or die "extract.pl: extract.pl puts $_ in $root.a but the Makefile does not\n";
        }
    }

    # Per-object compile lines.
    for my $s (@$sources) {
        (my $o = $s->{object}) =~ s/\.o$//;
        $mk =~ /^\Q$o\E\.o(?:bj)?:[^\n]*\n\t(.*)$/m
            or die "extract.pl: no Makefile rule for $o\n";
        my $line = $1;
        $line =~ /^\$\(CC\)\s+(.*?)\s*\$\(LIB_CFLAGS\) \$\(LIB_CPPFLAGS\)\s+-c -o \$\@ (\S+)$/
            or die "extract.pl: unexpected compile rule for $o: $line\n";
        my ($flags, $src) = ($1, $2);
        $src eq $s->{src} or die "extract.pl: Makefile compiles $src for $o\n";
        my (@i, @d);
        for (split ' ', $flags) {
            if (/^-I(.*)$/) { push @i, $1 }
            elsif (/^-D(.*)$/) { push @d, $1 }
            else { die "extract.pl: $s->{src}: special compile flag '$_'\n" }
        }
        "@i" eq "@{$s->{includes}}"
            or die "extract.pl: $s->{src}: Makefile includes (@i) differ from (@{$s->{includes}})\n";
        "@d" eq "@{$s->{defines}}"
            or die "extract.pl: $s->{src}: Makefile defines (@d) differ from (@{$s->{defines}})\n";
    }
}

# ----------------------------------------------------------------------
# merge

sub merge_guarded {
    my ($f, $a, $b) = @_;
    my @a = split /^/, $a;
    my @b = split /^/, $b;
    my $guard_end = sub {
        my ($l) = @_;
        for my $i (0 .. $#$l - 1) {
            if ($l->[$i] =~ /^#\s*ifndef\s+(\w+)/) {
                my $g = $1;
                return $i + 1 if $l->[$i + 1] =~ /^#\s*define\s+\Q$g\E\b/;
                die "extract.pl: $f: first #ifndef is not an include guard\n";
            }
        }
        die "extract.pl: $f: no include guard\n";
    };
    my $last_endif = sub {
        my ($l) = @_;
        for (my $i = $#$l; $i >= 0; $i--) {
            return $i if $l->[$i] =~ /^#\s*endif/;
        }
        die "extract.pl: $f: no final #endif\n";
    };
    my ($ha, $hb) = ($guard_end->(\@a), $guard_end->(\@b));
    my ($ea, $eb) = ($last_endif->(\@a), $last_endif->(\@b));
    my $head = join '', @a[0 .. $ha];
    $head eq join('', @b[0 .. $hb])
        or die "extract.pl: $f: headers differ outside the include guard\n";
    my $foot = join '', @a[$ea .. $#a];
    $foot eq join('', @b[$eb .. $#b])
        or die "extract.pl: $f: trailers differ outside the include guard\n";
    return $head
        . "\n/* Merged by extract.pl: x86_64 (mingw64) and i686 (mingw) bodies. */\n"
        . "#if defined(_WIN64)\n"
        . join('', @a[$ha + 1 .. $ea - 1])
        . "#else\n"
        . join('', @b[$hb + 1 .. $eb - 1])
        . "#endif /* _WIN64 */\n\n"
        . $foot;
}

sub cmake_list {
    my ($name, @items) = @_;
    return "set($name)\n" unless @items;
    return "set($name\n" . join('', map { "    $_\n" } @items) . ")\n";
}

sub cmake_quote {
    my ($s) = @_;
    $s =~ s/([\\"\$;])/\\$1/g;
    return $s =~ /[\s()#]/ ? "\"$s\"" : $s;
}

sub cmd_merge {
    my ($outdir, $srcroot, $t64, $j64, $t32, $j32) = @_;
    my $json = JSON::PP->new;
    my $A = $json->decode(slurp($j64));
    my $B = $json->decode(slurp($j32));
    $A->{platform} eq 'mingw64' or die "extract.pl: $j64 is $A->{platform}, not mingw64\n";
    $B->{platform} eq 'mingw' or die "extract.pl: $j32 is $B->{platform}, not mingw\n";

    # Generated files.
    "@{$A->{generated}}" eq "@{$B->{generated}}"
        or die "extract.pl: the targets need different generated files\n";
    my @gen = @{$A->{generated}};
    for my $f (@gen) {
        my $a = slurp("$t64/$f");
        my $b = slurp("$t32/$f");
        for ([$t64, $a], [$t32, $b]) {
            my ($t, $s) = @$_;
            # The last three components of the tree path, which may
            # appear with any prefix (C:/..., /c/..., /tmp/...).
            my @c = grep { length } split m{[/\\]}, $t;
            my $tag = join '/', @c[-3 .. -1];
            index($s, $tag) < 0
                or die "extract.pl: $f contains the build path ($tag)\n";
        }
        if ($a ne $b) {
            $MERGEABLE{$f}
                or die "extract.pl: $f differs between x86_64 and i686\n";
            $a = merge_guarded($f, $a, $b);
        }
        spew("$outdir/$f", $a);
    }
    my %isgen = map { $_ => 1 } @gen;

    # Sources and groups.
    my %grp;     # key -> { library, includes, defines, src => {x64=>[..], x86=>[..]} }
    for ([$A, 'x86_64'], [$B, 'i686']) {
        my ($d, $arch) = @$_;
        for my $s (@{$d->{sources}}) {
            !$s->{generated} || $isgen{$s->{src}}
                or die "extract.pl: $s->{src}: generated source missing from list\n";
            my $key = join "\0", $s->{library}, "@{$s->{includes}}", "@{$s->{defines}}";
            my $g = $grp{$key} //= {
                library => $s->{library}, includes => $s->{includes},
                defines => $s->{defines}, src => {},
            };
            push @{$g->{src}{$arch}}, $s->{src};
        }
    }

    my $src_ref = sub {
        my ($f) = @_;
        return $isgen{$f} ? "\${OSSL_GENERATED_DIR}/$f" : "\${OSSL_SOURCE_DIR}/$f";
    };
    my $inc_refs = sub {
        my ($g) = @_;
        my @dirs = uniq(@{$g->{includes}});    # first occurrence wins anyway
        my (@gd, @sd);
        for my $i (0 .. $#dirs) {
            my $d = $dirs[$i];
            my $pre = $d eq '.' ? '' : "$d/";
            my @under = grep { $pre eq '' || index($_, $pre) == 0 } @gen;
            # A generated file reached through this dir must not be
            # shadowed by, or shadow, a source file reached through this
            # or an earlier dir.
            for my $f (@under) {
                my $rel = substr($f, length $pre);
                for my $j (0 .. $i) {
                    my $p = $dirs[$j] eq '.' ? $rel : "$dirs[$j]/$rel";
                    next if $isgen{$p};
                    -e "$srcroot/$p"
                        and die "extract.pl: generated $f collides with source $p\n";
                }
            }
            push @gd, $d eq '.' ? '${OSSL_GENERATED_DIR}' : "\${OSSL_GENERATED_DIR}/$d" if @under;
            push @sd, $d eq '.' ? '${OSSL_SOURCE_DIR}' : "\${OSSL_SOURCE_DIR}/$d";
        }
        return (@gd, @sd);
    };

    my $o = '';
    $o .= "# Generated by Platforms/w64devkit/openssl/extract.pl.  Do not edit;\n";
    $o .= "# run Platforms/w64devkit/openssl/regen.sh instead.\n";
    $o .= "#\n";
    $o .= "# Before include(), set OSSL_SOURCE_DIR to the pristine OpenSSL source\n";
    $o .= "# root and OSSL_GENERATED_DIR to this directory.  Every group's include\n";
    $o .= "# list already puts the generated dirs before the source dirs.\n\n";

    $o .= "# Configure targets.\n";
    $o .= "set(OSSL_CONFIGURE_TARGET_X86_64 $A->{platform})\n";
    $o .= "set(OSSL_CONFIGURE_TARGET_I686 $B->{platform})\n\n";

    my %bd = map { $_ => 1 } @{$B->{defines}};
    my @cdef = grep { $bd{$_} } @{$A->{defines}};
    my %cd = map { $_ => 1 } @cdef;
    $o .= "# Defines for every libcrypto and libssl source.  OPENSSLDIR,\n";
    $o .= "# ENGINESDIR and MODULESDIR are deliberately absent: supply them through\n";
    $o .= "# a force-included header.\n";
    $o .= cmake_list('OSSL_DEFINES', map { cmake_quote($_) } @cdef);
    $o .= cmake_list('OSSL_DEFINES_X86_64', map { cmake_quote($_) } grep { !$cd{$_} } @{$A->{defines}});
    $o .= cmake_list('OSSL_DEFINES_I686', map { cmake_quote($_) } grep { !$cd{$_} } @{$B->{defines}});
    $o .= cmake_list('OSSL_DROPPED_DEFINES', sort keys %DROPPED_DEFINE);
    $o .= "\n# System libraries from Configure's ex_libs.\n";
    my %bl = map { $_ => 1 } @{$B->{ex_libs}};
    my @clib = grep { $bl{$_} } @{$A->{ex_libs}};
    my %cl = map { $_ => 1 } @clib;
    $o .= cmake_list('OSSL_SYSTEM_LIBS', @clib);
    $o .= cmake_list('OSSL_SYSTEM_LIBS_X86_64', grep { !$cl{$_} } @{$A->{ex_libs}});
    $o .= cmake_list('OSSL_SYSTEM_LIBS_I686', grep { !$cl{$_} } @{$B->{ex_libs}});
    $o .= "# Also required (CryptGenRandom, ReportEventW, MessageBoxW, ...), but\n";
    $o .= "# Configure relies on the gcc driver's default libraries for them.\n";
    $o .= cmake_list('OSSL_SYSTEM_LIBS_IMPLICIT', qw(advapi32 user32));
    $o .= "\n# Configure's compiler flags, for reference only (not for use).\n";
    $o .= cmake_list('OSSL_CONFIGURE_CFLAGS_X86_64', @{$A->{cflags}});
    $o .= cmake_list('OSSL_CONFIGURE_CFLAGS_I686', @{$B->{cflags}});

    $o .= "\n# crypto/buildinf.h is not shipped; CMake must write it.  It must define\n";
    $o .= "# PLATFORM (\"platform: <target>\"), DATE (\"built on: <date>\") and\n";
    $o .= "# static const char compiler_flags[] (\"compiler: <flags>\").\n";
    my %bs;
    for my $b (@{$A->{buildinf}}, @{$B->{buildinf}}) { $bs{$b->{source}} = 1 }
    $o .= cmake_list('OSSL_BUILDINF_SOURCES', map { $src_ref->($_) } sort keys %bs);
    $o .= cmake_list('OSSL_BUILDINF_MACROS', qw(PLATFORM DATE compiler_flags));
    $o .= "set(OSSL_BUILDINF_PLATFORM_X86_64 \"platform: $A->{platform}\")\n";
    $o .= "set(OSSL_BUILDINF_PLATFORM_I686 \"platform: $B->{platform}\")\n";

    $o .= "\n# Generated files shipped in this directory.\n";
    $o .= cmake_list('OSSL_GENERATED_FILES', map { "\${OSSL_GENERATED_DIR}/$_" } @gen);

    # Groups, in a stable order.
    my @keys = sort {
        $grp{$a}{library} cmp $grp{$b}{library}
            || (($grp{$b}{src}{x86_64} ? @{$grp{$b}{src}{x86_64}} : 0)
                <=> ($grp{$a}{src}{x86_64} ? @{$grp{$a}{src}{x86_64}} : 0))
            || $a cmp $b
    } keys %grp;
    my (@names, %bylib);
    my %count = (libcrypto => 0, libssl => 0);
    my $body = '';
    for my $k (@keys) {
        my $g = $grp{$k};
        my $lib = $g->{library};
        my $name = sprintf 'OSSL_%s_G%02d', uc($lib =~ s/^lib//r), ++$count{$lib};
        push @names, $name;
        my @x = sort @{$g->{src}{x86_64} // []};
        my @y = sort @{$g->{src}{i686} // []};
        my %ys = map { $_ => 1 } @y;
        my %xs = map { $_ => 1 } @x;
        my @common = grep { $ys{$_} } @x;
        my @xonly = grep { !$ys{$_} } @x;
        my @yonly = grep { !$xs{$_} } @y;
        push @{$bylib{$lib}{common}}, @common;
        push @{$bylib{$lib}{x86_64}}, @xonly;
        push @{$bylib{$lib}{i686}}, @yonly;
        $body .= "\n# $name: " . scalar(@common) . " common, " . scalar(@xonly)
               . " x86_64-only, " . scalar(@yonly) . " i686-only sources\n";
        $body .= "set(${name}_LIBRARY $lib)\n";
        $body .= cmake_list("${name}_INCLUDES", $inc_refs->($g));
        $body .= cmake_list("${name}_DEFINES", map { cmake_quote($_) } @{$g->{defines}});
        $body .= cmake_list("${name}_SOURCES", map { $src_ref->($_) } @common);
        $body .= cmake_list("${name}_SOURCES_X86_64", map { $src_ref->($_) } @xonly);
        $body .= cmake_list("${name}_SOURCES_I686", map { $src_ref->($_) } @yonly);
    }
    $o .= "\n# Source groups: sources in a group share include dirs and defines.\n";
    $o .= "# Each group has _LIBRARY, _INCLUDES, _DEFINES, _SOURCES (both\n";
    $o .= "# targets), _SOURCES_X86_64 and _SOURCES_I686.\n";
    $o .= cmake_list('OSSL_GROUPS', @names);
    $o .= $body;
    $o .= "\n# Complete source lists.\n";
    for my $lib (@ROOTS) {
        my $L = uc $lib;
        $o .= cmake_list("OSSL_${L}_SOURCES", map { $src_ref->($_) } sort @{$bylib{$lib}{common} // []});
        $o .= cmake_list("OSSL_${L}_SOURCES_X86_64", map { $src_ref->($_) } sort @{$bylib{$lib}{x86_64} // []});
        $o .= cmake_list("OSSL_${L}_SOURCES_I686", map { $src_ref->($_) } sort @{$bylib{$lib}{i686} // []});
    }
    spew("$outdir/openssl-sources.cmake", $o);

    for my $lib (@ROOTS) {
        my $n = @{$bylib{$lib}{common} // []};
        printf "%s: %d common, %d x86_64-only, %d i686-only sources\n", $lib, $n,
            scalar(@{$bylib{$lib}{x86_64} // []}), scalar(@{$bylib{$lib}{i686} // []});
    }
    printf "%d groups, %d generated files\n", scalar(@names), scalar(@gen);
}

# ----------------------------------------------------------------------

my $cmd = shift // '';
if ($cmd eq 'dump' && @ARGV == 2) {
    cmd_dump(@ARGV);
} elsif ($cmd eq 'merge' && @ARGV == 6) {
    cmd_merge(@ARGV);
} else {
    die "usage: extract.pl dump TREE OUT.json\n"
      . "       extract.pl merge OUTDIR SRCDIR X64TREE X64.json X86TREE X86.json\n";
}
