#define SOKOL_IMPL
#define SOKOL_GLCORE33

#include <stdlib.h>
#include <stdio.h>
#include "sokol/sokol_gfx.h"
#include "sokol_gp.h"

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#define STBIR_NO_SIMD
#include "stb/stb_image.h"
#include "stb/stb_image_resize.h"