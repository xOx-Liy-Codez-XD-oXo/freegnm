#ifndef _GNM_CONTROLS_H_
#define _GNM_CONTROLS_H_

#include <stdbool.h>

#include "types.h"

typedef struct {
	bool blendenabled;
	GnmCombFunc colorfunc;
	GnmBlendOp colorsrcmult;
	GnmBlendOp colordstmult;
	GnmCombFunc alphafunc;
	GnmBlendOp alphasrcmult;
	GnmBlendOp alphadstmult;
	bool separatealphaenable;
} GnmBlendControl;

typedef struct {
	bool depthclearenable;
	bool stencilclearenable;
	bool htileresummarizeenable;
	bool depthwritebackpol;
	bool stencilwritebackpol;
	bool forcedepthdecompress;
	bool copycentroidenable;
	uint8_t copysampleindex;
	bool copydepthtocolorenable;
	bool copystenciltocolorenable;
} GnmDbRenderControl;

typedef struct {
	bool zwrite;
	GnmDepthCompare zfunc;
	GnmDepthCompare stencilfunc;
	GnmDepthCompare stencilbackfunc;
	bool separatestencilenable;
	bool depthenable;
	bool stencilenable;
	bool depthboundsenable;
} GnmDepthStencilControl;

typedef struct {
	bool cull_front;
	bool cull_back;
	GnmFaceOrientation front_face;
	GnmFillMode front_mode;
	GnmFillMode back_mode;
	bool front_offset_mode;
	bool back_offset_mode;
	bool vertex_window_offset_enable;
	bool provoking_vtx_last;
	bool perspective_correction_disable;
} GnmPrimitiveSetup;

typedef struct {
	bool scale_x;
	bool offset_x;
	bool scale_y;
	bool offset_y;
	bool scale_z;
	bool offset_z;
	bool perspective_divide_xy;
	bool perspective_divide_z;
	bool invert_w;
} GnmViewportTransformControl;


#endif	// _GNM_CONTROLS_H_
