#ifndef DEEPSLATE_PNG_MEMORY_H
#define DEEPSLATE_PNG_MEMORY_H
unsigned char *stbi_write_png_to_mem(const unsigned char *pixels, int stride_bytes,
                                     int width, int height, int channels, int *out_len);
#endif
