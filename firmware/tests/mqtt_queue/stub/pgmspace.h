#pragma once
#include <string.h>
#define PROGMEM
#define PGM_P const char*
#define PSTR(s) (s)
#define pgm_read_byte(a) (*(const unsigned char*)(a))
#define strlen_P strlen
#define strcpy_P strcpy
#define strncpy_P strncpy
#define memcpy_P memcpy
#define strcmp_P strcmp
