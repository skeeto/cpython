/* mkzip: write a deterministic zip of the embedded stdlib (Archive.cmake).

     mkzip MEMBERS OUT

   Each line of MEMBERS (UTF-8) is "<archive path><TAB><file>".  Members are
   written in list order with a fixed timestamp (2000-01-01 00:00), no extra
   fields and no attributes, deflated when that is smaller (stored without
   zlib), so the bytes depend only on the contents.  OUT is replaced only
   when its bytes change. */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef HAVE_ZLIB
#  include <zlib.h>
#endif

#define DOS_TIME 0
#define DOS_DATE (((2000 - 1980) << 9) | (1 << 5) | 1)

typedef struct {
    unsigned char *data;
    size_t len, cap;
} buf;

static void
die(const char *msg, const char *arg)
{
    fprintf(stderr, "mkzip: %s%s%s\n", msg, arg ? ": " : "", arg ? arg : "");
    exit(1);
}

static void
put(buf *b, const void *p, size_t n)
{
    if (b->len + n > b->cap) {
        size_t cap = b->cap ? b->cap : 1 << 16;
        while (cap < b->len + n) {
            cap *= 2;
        }
        b->data = realloc(b->data, cap);
        if (b->data == NULL) {
            die("out of memory", NULL);
        }
        b->cap = cap;
    }
    memcpy(b->data + b->len, p, n);
    b->len += n;
}

static void
put16(buf *b, unsigned v)
{
    unsigned char s[2] = {v & 0xff, v >> 8 & 0xff};
    put(b, s, 2);
}

static void
put32(buf *b, uint32_t v)
{
    unsigned char s[4] = {v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24};
    put(b, s, 4);
}

static wchar_t *
widen(const char *s)
{
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
    wchar_t *w = n ? malloc(n * sizeof(*w)) : NULL;
    if (w == NULL ||
        !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, w, n)) {
        die("bad path", s);
    }
    return w;
}

static buf
slurp(const char *path, int must)
{
    buf b = {0};
    wchar_t *w = widen(path);
    FILE *f = _wfopen(w, L"rb");
    free(w);
    if (f == NULL) {
        if (must) {
            die("cannot open", path);
        }
        return b;
    }
    unsigned char tmp[1 << 16];
    size_t n;
    while ((n = fread(tmp, 1, sizeof(tmp), f)) > 0) {
        put(&b, tmp, n);
    }
    if (ferror(f)) {
        die("cannot read", path);
    }
    fclose(f);
    return b;
}

static uint32_t
crc32_of(const unsigned char *p, size_t n)
{
#ifdef HAVE_ZLIB
    uLong crc = crc32(0, Z_NULL, 0);
    while (n > 0) {
        uInt k = n > 0x40000000 ? 0x40000000 : (uInt)n;
        crc = crc32(crc, p, k);
        p += k;
        n -= k;
    }
    return (uint32_t)crc;
#else
    uint32_t crc = 0xffffffff;
    for (size_t i = 0; i < n; i++) {
        crc ^= p[i];
        for (int k = 0; k < 8; k++) {
            crc = crc >> 1 ^ (0xedb88320 & -(crc & 1));
        }
    }
    return ~crc;
#endif
}

/* Deflate src into out; return 0 if that would not be smaller. */
static int
deflate_to(buf *out, const buf *src)
{
#ifdef HAVE_ZLIB
    z_stream z = {0};
    if (src->len > 0x40000000 ||
        deflateInit2(&z, 9, Z_DEFLATED, -15, 9, Z_DEFAULT_STRATEGY) != Z_OK) {
        return 0;
    }
    uLong bound = deflateBound(&z, (uLong)src->len);
    out->len = 0;
    if (out->cap < bound) {
        out->data = realloc(out->data, bound);
        if (out->data == NULL) {
            die("out of memory", NULL);
        }
        out->cap = bound;
    }
    z.next_in = src->data;
    z.avail_in = (uInt)src->len;
    z.next_out = out->data;
    z.avail_out = (uInt)bound;
    int rc = deflate(&z, Z_FINISH);
    out->len = z.total_out;
    deflateEnd(&z);
    return rc == Z_STREAM_END && out->len < src->len;
#else
    (void)out; (void)src;
    return 0;
#endif
}

int
main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: mkzip MEMBERS OUT\n");
        return 2;
    }
    buf list = slurp(argv[1], 1);
    put(&list, "", 1);                          /* terminate */

    buf zip = {0}, central = {0}, packed = {0};
    unsigned count = 0;
    char *line = (char *)list.data;
    while (*line) {
        char *end = strchr(line, '\n');
        char *next = end ? end + 1 : line + strlen(line);
        if (end) {
            *end = 0;
            if (end > line && end[-1] == '\r') {
                end[-1] = 0;
            }
        }
        if (*line == 0) {
            line = next;
            continue;
        }
        char *tab = strchr(line, '\t');
        if (tab == NULL || tab == line) {
            die("malformed member line", line);
        }
        *tab = 0;
        const char *name = line, *path = tab + 1;
        size_t nlen = strlen(name);
        if (nlen > 0xffff) {
            die("name too long", name);
        }

        buf data = slurp(path, 1);
        if (data.len > 0xfffffffe) {
            die("file too large", path);
        }
        uint32_t crc = crc32_of(data.data, data.len);
        int deflated = deflate_to(&packed, &data);
        const buf *body = deflated ? &packed : &data;
        unsigned method = deflated ? 8 : 0;
        int utf8 = 0;
        for (const char *p = name; *p; p++) {
            utf8 |= (unsigned char)*p >= 0x80;
        }
        unsigned flags = utf8 ? 0x0800 : 0;
        if (zip.len > 0xfffffffe) {
            die("archive too large", NULL);
        }
        uint32_t offset = (uint32_t)zip.len;

        put32(&zip, 0x04034b50);
        put16(&zip, 20);                        /* version needed */
        put16(&zip, flags);
        put16(&zip, method);
        put16(&zip, DOS_TIME);
        put16(&zip, DOS_DATE);
        put32(&zip, crc);
        put32(&zip, (uint32_t)body->len);
        put32(&zip, (uint32_t)data.len);
        put16(&zip, (unsigned)nlen);
        put16(&zip, 0);                         /* extra */
        put(&zip, name, nlen);
        put(&zip, body->data, body->len);

        put32(&central, 0x02014b50);
        put16(&central, 20);                    /* made by: MS-DOS, 2.0 */
        put16(&central, 20);
        put16(&central, flags);
        put16(&central, method);
        put16(&central, DOS_TIME);
        put16(&central, DOS_DATE);
        put32(&central, crc);
        put32(&central, (uint32_t)body->len);
        put32(&central, (uint32_t)data.len);
        put16(&central, (unsigned)nlen);
        put16(&central, 0);                     /* extra */
        put16(&central, 0);                     /* comment */
        put16(&central, 0);                     /* disk */
        put16(&central, 0);                     /* internal attributes */
        put32(&central, 0);                     /* external attributes */
        put32(&central, offset);
        put(&central, name, nlen);

        free(data.data);
        if (++count > 0xffff) {
            die("too many members", NULL);
        }
        line = next;
    }

    if (zip.len + central.len > 0xfffffffe) {
        die("archive too large", NULL);
    }
    uint32_t cdoffset = (uint32_t)zip.len;
    put(&zip, central.data, central.len);
    put32(&zip, 0x06054b50);
    put16(&zip, 0);
    put16(&zip, 0);
    put16(&zip, count);
    put16(&zip, count);
    put32(&zip, (uint32_t)central.len);
    put32(&zip, cdoffset);
    put16(&zip, 0);                             /* comment */

    buf old = slurp(argv[2], 0);
    if (old.len == zip.len && memcmp(old.data, zip.data, zip.len) == 0) {
        return 0;
    }
    size_t olen = strlen(argv[2]);
    char *tmp = malloc(olen + 5);
    memcpy(tmp, argv[2], olen);
    memcpy(tmp + olen, ".tmp", 5);
    wchar_t *wtmp = widen(tmp), *wout = widen(argv[2]);
    FILE *f = _wfopen(wtmp, L"wb");
    if (f == NULL || fwrite(zip.data, 1, zip.len, f) != zip.len ||
        fclose(f) != 0) {
        die("cannot write", tmp);
    }
    if (!MoveFileExW(wtmp, wout, MOVEFILE_REPLACE_EXISTING)) {
        die("cannot replace", argv[2]);
    }
    return 0;
}
