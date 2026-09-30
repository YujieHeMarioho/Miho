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
// BeatNet recurrent inference. Input is a trailing 1411-sample mono Hann
// window at 22050 Hz every 441 samples. Output: beat/downbeat/neither.
// Optional features[272] is for independent export parity verification.
typedef struct MihoBeatTracker MihoBeatTracker;
MihoBeatTracker *miho_beat_create(const char *model_path,char *error,size_t error_capacity);
void miho_beat_destroy(MihoBeatTracker *tracker);
void miho_beat_reset(MihoBeatTracker *tracker);
int miho_beat_process(MihoBeatTracker *tracker,const float *audio,float *probabilities,float *features);
const char *miho_beat_error(MihoBeatTracker *tracker);
#ifdef __cplusplus
}
#endif
