#ifndef CZLIB_H
#define CZLIB_H

#include <stddef.h>
#include <stdint.h>

typedef struct cZlib_stream cZlib_stream;

cZlib_stream *cZlib_inflate_init(void);

int cZlib_inflate_process(cZlib_stream *stream,
                          const uint8_t *input, size_t input_len,
                          uint8_t *output, size_t output_len,
                          size_t *bytes_consumed, size_t *bytes_produced);

void cZlib_inflate_end(cZlib_stream *stream);

#endif
