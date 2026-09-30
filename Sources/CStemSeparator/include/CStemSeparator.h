#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct MihoSeparator MihoSeparator;
MihoSeparator *miho_separator_create(const char *model_path,char *error,size_t error_capacity);
void miho_separator_destroy(MihoSeparator *separator);
void miho_separator_reset(MihoSeparator *separator);
// Planar stereo 128-sample input at 44.1 kHz. 1 = valid, 2 = initial hop, 0 = error.
int miho_separator_process(MihoSeparator *separator,const float *left,const float *right,
                           float *vocals,float *drums,float *bass);
const char *miho_separator_error(MihoSeparator *separator);
#ifdef __cplusplus
}
#endif
