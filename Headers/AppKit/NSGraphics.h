/*
   NSGraphics.h

   Copyright (C) 1996, 2005 Free Software Foundation, Inc.

   Author: Ovidiu Predescu <ovidiu@net-community.com>
   Date: February 1997
   
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/
#ifndef __NSGraphics_h__
#define __NSGraphics_h__

#include <Foundation/NSObject.h>
#include <Foundation/NSGeometry.h>

#include <AppKit/NSGraphicsContext.h>
#include <AppKit/AppKitDefines.h>

@class NSString;
@class NSColor;
@class NSGraphicsContext;

/*
 * Colorspace Names 
 */
APPKIT_EXPORT NSString *NSCalibratedWhiteColorSpace; 
APPKIT_EXPORT NSString *NSCalibratedBlackColorSpace; 
APPKIT_EXPORT NSString *NSCalibratedRGBColorSpace;
APPKIT_EXPORT NSString *NSDeviceWhiteColorSpace;
APPKIT_EXPORT NSString *NSDeviceBlackColorSpace;
APPKIT_EXPORT NSString *NSDeviceRGBColorSpace;
APPKIT_EXPORT NSString *NSDeviceCMYKColorSpace;
APPKIT_EXPORT NSString *NSNamedColorSpace;
#ifndef	STRICT_OPENSTEP
APPKIT_EXPORT NSString *NSPatternColorSpace;
#endif
APPKIT_EXPORT NSString *NSCustomColorSpace;


/*
 * Color function APPKIT_EXPORTs
 */
APPKIT_EXPORT const NSWindowDepth _GSGrayBitValue;
APPKIT_EXPORT const NSWindowDepth _GSRGBBitValue;
APPKIT_EXPORT const NSWindowDepth _GSCMYKBitValue;
APPKIT_EXPORT const NSWindowDepth _GSCustomBitValue;
APPKIT_EXPORT const NSWindowDepth _GSNamedBitValue;
APPKIT_EXPORT const NSWindowDepth *_GSWindowDepths[7];
APPKIT_EXPORT const NSWindowDepth NSDefaultDepth;
APPKIT_EXPORT const NSWindowDepth NSTwoBitGrayDepth;
APPKIT_EXPORT const NSWindowDepth NSEightBitGrayDepth;
APPKIT_EXPORT const NSWindowDepth NSEightBitRGBDepth;
APPKIT_EXPORT const NSWindowDepth NSTwelveBitRGBDepth;
APPKIT_EXPORT const NSWindowDepth GSSixteenBitRGBDepth;
APPKIT_EXPORT const NSWindowDepth NSTwentyFourBitRGBDepth;

/*
 * Gray Values 
 */
APPKIT_EXPORT const float NSBlack;
APPKIT_EXPORT const float NSDarkGray;
APPKIT_EXPORT const float NSWhite;
APPKIT_EXPORT const float NSLightGray;
APPKIT_EXPORT const float NSGray;

/*
 * Device Dictionary Keys 
 */
APPKIT_EXPORT NSString *NSDeviceResolution;
APPKIT_EXPORT NSString *NSDeviceColorSpaceName;
APPKIT_EXPORT NSString *NSDeviceBitsPerSample;
APPKIT_EXPORT NSString *NSDeviceIsScreen;
APPKIT_EXPORT NSString *NSDeviceIsPrinter;
APPKIT_EXPORT NSString *NSDeviceSize;

/*
 * Get Information About Color Space and Window Depth
 */
APPKIT_EXPORT const NSWindowDepth *NSAvailableWindowDepths(void);
APPKIT_EXPORT NSWindowDepth NSBestDepth(NSString *colorSpace, 
			  int bitsPerSample, int bitsPerPixel, 
			  BOOL planar, BOOL *exactMatch);
APPKIT_EXPORT int NSBitsPerPixelFromDepth(NSWindowDepth depth);
APPKIT_EXPORT int NSBitsPerSampleFromDepth(NSWindowDepth depth);
APPKIT_EXPORT NSString *NSColorSpaceFromDepth(NSWindowDepth depth);
APPKIT_EXPORT int NSNumberOfColorComponents(NSString *colorSpaceName);
APPKIT_EXPORT BOOL NSPlanarFromDepth(NSWindowDepth depth);


/*
 * Functions for getting information about windows.
 */
APPKIT_EXPORT void NSCountWindows(int *count);
APPKIT_EXPORT void NSWindowList(int size, int list[]);

APPKIT_EXPORT void NSEraseRect(NSRect aRect);
APPKIT_EXPORT void NSHighlightRect(NSRect aRect);
APPKIT_EXPORT void NSRectClip(NSRect aRect);
APPKIT_EXPORT void NSRectClipList(const NSRect *rects, int count);
APPKIT_EXPORT void NSRectFill(NSRect aRect);
APPKIT_EXPORT void NSRectFillList(const NSRect *rects, int count);
APPKIT_EXPORT void NSRectFillListWithGrays(const NSRect *rects,
					   const float *grays,int count);

/** Draws a set of edges of aRect.  The sides array should contain
    count edges, and grays the corresponding color.  Edges are drawn
    in the order given in the array, and subsequent edges are drawn
    inside previous edges (thus, they will never overlap).  */
APPKIT_EXPORT NSRect NSDrawTiledRects(NSRect aRect, const NSRect clipRect,
			const NSRectEdge *sides,
			const float *grays, int count);

APPKIT_EXPORT void NSDrawButton(const NSRect aRect, const NSRect clipRect);
APPKIT_EXPORT void NSDrawGrayBezel(const NSRect aRect, const NSRect clipRect);
APPKIT_EXPORT void NSDrawGroove(const NSRect aRect, const NSRect clipRect);
APPKIT_EXPORT void NSDrawWhiteBezel(const NSRect aRect, const NSRect clipRect);
APPKIT_EXPORT void NSDrawFramePhoto(const NSRect aRect, const NSRect clipRect);

// This is from an old version of the specification 
static inline void
NSDrawBezel(const NSRect aRect, const NSRect clipRect)
{
  NSDrawGrayBezel(aRect, clipRect);
}


/** Draws a rectangle along the inside of aRect.  The rectangle will be
    black, dotted (using 1 point dashes), and will have a line width
    of 1 point.  */
APPKIT_EXPORT void NSDottedFrameRect(NSRect aRect);
/** <p>Draws a rectangle using the current color along the inside of aRect.
    NSFrameRectWithWidth uses the frameWidth as the line width, while
    NSFrameRect always uses 1 point wide lines.  The functions do not
    change the line width of the current graphics context.
    </p><p>
    'Inside' here means that no part of the stroked rectangle will extend
    outside the given rectangle.
    </p>  */
APPKIT_EXPORT void NSFrameRect(const NSRect aRect); 
APPKIT_EXPORT void NSFrameRectWithWidth(const NSRect aRect, float frameWidth);

APPKIT_EXPORT NSColor* NSReadPixel(NSPoint location);

APPKIT_EXPORT void NSCopyBitmapFromGState(int srcGstate, NSRect srcRect, 
					  NSRect destRect);
APPKIT_EXPORT void NSCopyBits(int srcGstate, NSRect srcRect, 
			      NSPoint destPoint);

static inline void 
NSDrawBitmap(NSRect rect,
	     int pixelsWide,
	     int pixelsHigh,
	     int bitsPerSample,
	     int samplesPerPixel,
	     int bitsPerPixel,
	     int bytesPerRow,
	     BOOL isPlanar,
	     BOOL hasAlpha,
	     NSString *colorSpaceName,
	     const unsigned char *const data[5])
{
  NSGraphicsContext *ctxt = GSCurrentContext();
  (ctxt->methods->NSDrawBitmap___________)
    (ctxt, @selector(NSDrawBitmap: : : : : : : : : : :),  rect,
     pixelsWide,
     pixelsHigh,
     bitsPerSample,
     samplesPerPixel,
     bitsPerPixel,
     bytesPerRow,
     isPlanar,
     hasAlpha,
     colorSpaceName,
     data);
    }

static inline void
NSBeep(void)
{
  NSGraphicsContext *ctxt = GSCurrentContext();
  (ctxt->methods->NSBeep)
    (ctxt, @selector(NSBeep));
}

static inline void
GSWSetViewIsFlipped(NSGraphicsContext *ctxt, BOOL flipped)
{
  (ctxt->methods->GSWSetViewIsFlipped_)
    (ctxt, @selector(GSWSetViewIsFlipped:), flipped);
}

static inline BOOL
GSWViewIsFlipped(NSGraphicsContext *ctxt)
{
  return (ctxt->methods->GSWViewIsFlipped)
    (ctxt, @selector(GSWViewIsFlipped));
}

#ifndef	NO_GNUSTEP
@class	NSArray;
@class	NSWindow;

APPKIT_EXPORT NSArray* GSAllWindows(void);
APPKIT_EXPORT NSWindow* GSWindowWithNumber(int num);
#endif

#ifndef	STRICT_OPENSTEP
// Window operations
APPKIT_EXPORT void NSConvertGlobalToWindowNumber(int globalNum, unsigned int *winNum);
APPKIT_EXPORT void NSConvertWindowNumberToGlobal(int winNum, unsigned int *globalNum);

// Rectangle drawing
APPKIT_EXPORT NSRect NSDrawColorTiledRects(NSRect boundsRect, NSRect clipRect, 
					    const NSRectEdge *sides, 
					    NSColor **colors, 
					    int count);
APPKIT_EXPORT void NSDrawDarkBezel(NSRect aRect, NSRect clipRect);
APPKIT_EXPORT void NSDrawLightBezel(NSRect aRect, NSRect clipRect);
APPKIT_EXPORT void NSRectFillListWithColors(const NSRect *rects, 
					     NSColor **colors, int count);

APPKIT_EXPORT void NSRectFillUsingOperation(NSRect aRect, 
					     NSCompositingOperation op);
APPKIT_EXPORT void NSRectFillListUsingOperation(const NSRect *rects, 
						 int count, 
						 NSCompositingOperation op);
APPKIT_EXPORT void NSRectFillListWithColorsUsingOperation(const NSRect *rects,
							   NSColor **colors, 
							   int num, 
							   NSCompositingOperation op);

APPKIT_EXPORT void NSDrawWindowBackground(NSRect aRect);

// Context information
APPKIT_EXPORT void NSCountWindowsForContext(int context, int *count);
APPKIT_EXPORT void NSWindowListForContext(int context, int size, int **list);
APPKIT_EXPORT int NSGetWindowServerMemory(int context, int *virtualMemory, 
					   int *windowBackingMemory, 
					   NSString **windowDumpStream);

#endif

#endif /* __NSGraphics_h__ */
