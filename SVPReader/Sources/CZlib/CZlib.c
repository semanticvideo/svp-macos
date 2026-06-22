#include "CZlib.h"
#include <zlib.h>
#include <stdlib.h>

struct cZlib_stream {
    z_stream zs;
    int initialized;
};

cZlib_stream *cZlib_inflate_init(void) {
    cZlib_stream *s = calloc(1, sizeof(cZlib_stream));
    if (!s) return NULL;
    s->zs.zalloc = Z_NULL;
    s->zs.zfree = Z_NULL;
    s->zs.opaque = Z_NULL;
    s->zs.next_in = Z_NULL;
    s->zs.avail_in = 0;
    if (inflateInit2(&s->zs, -15) != Z_OK) {
        free(s);
        return NULL;
    }
    s->initialized = 1;
    return s;
}

int cZlib_inflate_process(cZlib_stream *s,
                          const uint8_t *input, size_t input_len,
                          uint8_t *output, size_t output_len,
                          size_t *bytes_consumed, size_t *bytes_produced) {
    if (!s || !s->initialized) return -1;

    s->zs.next_in = (Bytef *)input;
    s->zs.avail_in = (uInt)input_len;
    s->zs.next_out = (Bytef *)output;
    s->zs.avail_out = (uInt)output_len;

    int ret = inflate(&s->zs, Z_NO_FLUSH);

    *bytes_consumed = input_len - s->zs.avail_in;
    *bytes_produced = output_len - s->zs.avail_out;

    if (ret == Z_STREAM_END) return 1;
    if (ret == Z_OK || ret == Z_BUF_ERROR) return 0;
    return -1;
}

void cZlib_inflate_end(cZlib_stream *s) {
    if (s) {
        if (s->initialized) inflateEnd(&s->zs);
        free(s);
    }
}
