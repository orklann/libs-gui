/* 
   NSTextView.m

   Copyright (C) 1999 Free Software Foundation, Inc.

   Author: Fred Kiefer <FredKiefer@gmx.de>
   Date: September 2000
   Reorganised and cleaned up code

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
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/ 

#include <gnustep/gui/config.h>
#include <Foundation/NSCoder.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSException.h>
#include <Foundation/NSProcessInfo.h>
#include <Foundation/NSString.h>
#include <Foundation/NSNotification.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSWindow.h>
#include <AppKit/NSEvent.h>
#include <AppKit/NSFont.h>
#include <AppKit/NSColor.h>
#include <AppKit/NSTextView.h>
#include <AppKit/NSRulerView.h>
#include <AppKit/NSPasteboard.h>
#include <AppKit/NSSpellChecker.h>
#include <AppKit/NSControl.h>
#include <AppKit/NSLayoutManager.h>
#include <AppKit/NSTextStorage.h>
#include <AppKit/NSColorPanel.h>

#define HUGE 1e7

// not the same as NSMakeRange!
static inline
NSRange MakeRangeFromAbs (unsigned a1, unsigned a2)
{
  if (a1 < a2)
    return NSMakeRange(a1, a2 - a1);
  else
    return NSMakeRange(a2, a1 - a2);
}

#define SET_DELEGATE_NOTIFICATION(notif_name) \
  if ([_delegate respondsToSelector: @selector(text##notif_name: )]) \
    [nc addObserver: _delegate \
           selector: @selector(text##notif_name: ) \
               name: NSText##notif_name##Notification \
             object: _notifObject]

/* MINOR FIXME: The following two should really be kept in the
   NSLayoutManager object to avoid interferences between different
   sets of NSTextViews linked to different NSLayoutManagers.  But this
   bug should show very rarely. */
 
/* YES when in the process of synchronizing text view attributes.  
   It is used to avoid recursive synchronizations. */
static BOOL isSynchronizingFlags = NO;
static BOOL isSynchronizingDelegate = NO;

/* The shared notification center */
static NSNotificationCenter *nc;

@interface NSText (GNUstepPrivate)
+ (NSDictionary*) defaultTypingAttributes;
- (NSRect) rectForCharacterRange: (NSRange)aRange;
@end

@interface NSTextView (GNUstepPrivate)
- (NSTextContainer*) buildUpTextNetwork: (NSSize)aSize;
@end

@implementation NSTextView

/* Class methods */

+ (void) initialize
{
  if ([self class] == [NSTextView class])
    {
      [self setVersion: 1];
      [self registerForServices];
      nc = [NSNotificationCenter defaultCenter];
    }
}

+ (void) registerForServices
{
  NSArray *types;
      
  types  = [NSArray arrayWithObjects: NSStringPboardType, 
		    NSRTFPboardType, NSRTFDPboardType, nil];
 
  [[NSApplication sharedApplication] registerServicesMenuSendTypes: types
						       returnTypes: types];
}

/* Initializing Methods */

/* Designated initializer */
- (id) initWithFrame: (NSRect)frameRect
       textContainer: (NSTextContainer*)aTextContainer
{
  [super initWithFrame: frameRect];

  [self setMinSize: frameRect.size];
  [self setMaxSize: NSMakeSize (HUGE,HUGE)];

  _tf.is_field_editor = NO;
  _tf.is_editable = YES;
  _tf.is_selectable = YES;
  _tf.is_rich_text = NO;
  _tf.imports_graphics = NO;
  _tf.draws_background = YES;
  _tf.is_horizontally_resizable = NO;
  _tf.is_vertically_resizable = NO;
  _tf.uses_font_panel = YES;
  _tf.uses_ruler = YES;
  _tf.is_ruler_visible = NO;
  ASSIGN (_caret_color, [NSColor blackColor]); 
  [self setTypingAttributes: [isa defaultTypingAttributes]];

  [self setBackgroundColor: [NSColor textBackgroundColor]];

  //[self setSelectedRange: NSMakeRange (0, 0)];

  [aTextContainer setTextView: self];
  [aTextContainer setWidthTracksTextView: YES];
  [aTextContainer setHeightTracksTextView: YES];

  // FIXME: ?? frame was given as an argument so we shouldn't resize.
  [self sizeToFit];

  [self setEditable: YES];
  [self setUsesFontPanel: YES];
  [self setUsesRuler: YES];

  return self;
}

- (id) initWithFrame: (NSRect)frameRect
{
  NSTextContainer *aTextContainer;

  aTextContainer = [self buildUpTextNetwork: frameRect.size];

  self = [self initWithFrame: frameRect  textContainer: aTextContainer];

  /* At this point the situation is as follows: 

     textView (us)  --RETAINs--> textStorage
     textStorage    --RETAINs--> layoutManager 
     layoutManager  --RETAINs--> textContainer 
     textContainter --RETAINs --> textView (us) */

  /* The text system should be destroyed when the textView (us) is
     released.  To get this result, we send a RELEASE message to us
     breaking the RETAIN cycle. */
  RELEASE (self);

  return self;
}

- (void) encodeWithCoder: (NSCoder *)aCoder
{
   BOOL flag;

  [super encodeWithCoder: aCoder];

  flag = _tvf.smart_insert_delete;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
  flag = _tvf.allows_undo;
  [aCoder encodeValueOfObjCType: @encode(BOOL) at: &flag];
}

- (id) initWithCoder: (NSCoder *)aDecoder
{
  NSTextContainer *aTextContainer; 
  BOOL flag;

  self = [super initWithCoder: aDecoder];

  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tvf.smart_insert_delete = flag;
  [aDecoder decodeValueOfObjCType: @encode(BOOL) at: &flag];
  _tvf.allows_undo = flag;
  
  /* build up the rest of the text system, which doesn't get stored 
     <doesn't even implement the Coding protocol>. */
  aTextContainer = [self buildUpTextNetwork: _frame.size];
  [aTextContainer setTextView: (NSTextView*)self];
  /* See initWithFrame: for comments on this RELEASE */
  RELEASE (self);

  return self;
}

- (void)dealloc
{
  if (_tvf.owns_text_network == YES)
    {
      /* Prevent recursive dealloc */
      if (_tvf.is_in_dealloc == YES)
	{
	  return;
	}
      _tvf.is_in_dealloc = YES;
      /* This releases all the text objects (us included) in fall */
      RELEASE (_textStorage);
    }

  RELEASE (_selectedTextAttributes);
  RELEASE (_markedTextAttributes);

  [super dealloc];
}

- (NSTextContainer*) buildUpTextNetwork: (NSSize)aSize;
{
  NSTextContainer *textContainer;
  NSLayoutManager *layoutManager;
  NSTextStorage *textStorage;

  textStorage = [[NSTextStorage alloc] init];

  layoutManager = [[NSLayoutManager alloc] init];
  /*
    [textStorage addLayoutManager: layoutManager];
    RELEASE (layoutManager);
  */

  textContainer = [[NSTextContainer alloc] initWithContainerSize: aSize];
  [layoutManager addTextContainer: textContainer];
  RELEASE (textContainer);

  /* FIXME: The following two lines should go *before* */
  [textStorage addLayoutManager: layoutManager];
  RELEASE (layoutManager);

  /* The situation at this point is as follows: 

     textView (us) --RETAINs--> textStorage 
     textStorage   --RETAINs--> layoutManager 
     layoutManager --RETAINs--> textContainer */

  /* We keep a flag to remember that we are directly responsible for 
     managing the text objects. */
  _tvf.owns_text_network = YES;

  return textContainer;
}

/* 
 * Implementation of methods declared in superclass but depending 
 * on the internals of the NSTextView
 */
- (void) replaceCharactersInRange: (NSRange)aRange
		       withString: (NSString*)aString
{
  if (aRange.location == NSNotFound)
    return;

  if ([self shouldChangeTextInRange: aRange  
	    replacementString: aString] == NO)
    return; 
 
  [_textStorage beginEditing];
  [_textStorage replaceCharactersInRange: aRange  withString: aString];
  [_textStorage endEditing];
  [self didChangeText];
}

- (NSString *) string
{
  return [_textStorage string];
}

- (NSRange) selectedRange
{
  return _selected_range;
}

- (void) setSelectedRange: (NSRange)range
{
/*
  NSLog(@"setSelectedRange (%d, %d)", charRange.location, charRange.length);
  [[NSNotificationCenter defaultCenter]
    postNotificationName: NSTextViewDidChangeSelectionNotification
    object: self];
  _selected_range = charRange;
*/
  NSRange oldRange = _selected_range;
  NSRange overlap;

  // Nothing to do, if the range is still the same
  if (NSEqualRanges(range, oldRange))
    return;

  //<!> ask delegate for selection validation

  _selected_range  = range;
  [self updateFontPanel];

#if 0
  [nc postNotificationName: NSTextViewDidChangeSelectionNotification
      object: self
      userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
				NSStringFromRange (_selected_range),
			      NSOldSelectedCharacterRange, nil]];
#endif

  // display
  if (range.length)
    {
      // <!>disable caret timed entry
    }
  else	// no selection
    {
      if (_tf.is_rich_text)
	{
	  [self setTypingAttributes: [_textStorage attributesAtIndex: range.location
						   effectiveRange: NULL]];
	}
      // <!>enable caret timed entry
    }

  if (!_window)
    return;

  // Make the selected range visible
  [self scrollRangeToVisible: _selected_range]; 

  // Redisplay what has changed
  // This does an unhighlight of the old selected region
  overlap = NSIntersectionRange(oldRange, _selected_range);
  if (overlap.length)
    {
      // Try to optimize for overlapping ranges
      if (range.location != oldRange.location)
	  [self setNeedsDisplayInRect: 
		    [self rectForCharacterRange: 
			      MakeRangeFromAbs(MIN(range.location,
						   oldRange.location),
					       MAX(range.location,
						   oldRange.location))]];
      if (NSMaxRange(range) != NSMaxRange(oldRange))
	  [self setNeedsDisplayInRect: 
		    [self rectForCharacterRange: 
			      MakeRangeFromAbs(MIN(NSMaxRange(range),
						   NSMaxRange(oldRange)),
					       MAX(NSMaxRange(range),
						   NSMaxRange (oldRange)))]];
    }
  else
    {
      [self setNeedsDisplayInRect: [self rectForCharacterRange: range]];
      [self setNeedsDisplayInRect: [self rectForCharacterRange: oldRange]];
    }

  [self setSelectionGranularity: NSSelectByCharacter];
  // Also removes the marking from
  // marked text if the new selection is greater than the marked region.
}

/*
 * Methods which should be moved here from NSText
 * 
 */
//- (NSRect) rectForCharacterRange: (NSRange)aRange

/* 
 *  NSTextView's specific methods 
 */

- (void) _updateMultipleTextViews
{
  id oldNotifObject = _notifObject;

  if ([[_layoutManager textContainers] count] > 1)
    {
      _tvf.multiple_textviews = YES;
      _notifObject = [_layoutManager firstTextView];
    }
  else
    {
      _tvf.multiple_textviews = NO;
      _notifObject = self;
    }  

  if ((_delegate != nil) && (oldNotifObject != _notifObject))
    {
      [nc removeObserver: _delegate  name: nil  object: oldNotifObject];

      /* SET_DELEGATE_NOTIFICATION defined at the beginning of file */

      /* NSText notifications */
      SET_DELEGATE_NOTIFICATION (DidBeginEditing);
      SET_DELEGATE_NOTIFICATION (DidChange);
      SET_DELEGATE_NOTIFICATION (DidEndEditing);
      /* NSTextView notifications */
      SET_DELEGATE_NOTIFICATION (ViewDidChangeSelection);
      SET_DELEGATE_NOTIFICATION (ViewWillChangeNotifyingTextView);
    }
}

/* This should only be called by [NSTextContainer -setTextView:] */
- (void) setTextContainer: (NSTextContainer*)aTextContainer
{
  _textContainer = aTextContainer;
  _layoutManager = [aTextContainer layoutManager];
  _textStorage = [_layoutManager textStorage];

  [self _updateMultipleTextViews];

  // FIXME: Hack to get the layout change
  [_textContainer setContainerSize: _frame.size];
}

- (void) replaceTextContainer: (NSTextContainer*)aTextContainer
{
  // Notify layoutManager of change?

  /* Do not retain: text container is owning us. */
  _textContainer = aTextContainer;

  [self _updateMultipleTextViews];
}

- (NSTextContainer *) textContainer
{
  return _textContainer;
}

- (void) setTextContainerInset: (NSSize)inset
{
  _textContainerInset = inset;
  [self invalidateTextContainerOrigin];
}

- (NSSize) textContainerInset
{
  return _textContainerInset;
}

- (NSPoint) textContainerOrigin
{
  return _textContainerOrigin;
}

- (void) invalidateTextContainerOrigin
{
  // recompute the textContainerOrigin
  // use bounds, inset, and used rect.
  /*
  NSRect bRect = [self bounds];
  NSRect uRect = [[self layoutManager] usedRectForTextContainer: _textContainer];

  if ([self isFlipped])
    _textContainerOrigin = ;
  else
    _textContainerOrigin = ;
  */
}

- (NSLayoutManager*) layoutManager
{
  return _layoutManager;
}

- (NSTextStorage*) textStorage
{
  return _textStorage;
}

- (void) setAllowsUndo: (BOOL)flag
{
  _tvf.allows_undo = flag;
}

- (BOOL) allowsUndo
{
  return _tvf.allows_undo;
}

- (void) setNeedsDisplayInRect: (NSRect)aRect
	 avoidAdditionalLayout: (BOOL)flag
{
  // FIXME: This is here until the layout manager is working
  [super setNeedsDisplayInRect: aRect];
}

/* We override NSView's setNeedsDisplayInRect: */

- (void) setNeedsDisplayInRect: (NSRect)aRect
{
  [self setNeedsDisplayInRect: aRect  avoidAdditionalLayout: NO];
}

- (BOOL) shouldDrawInsertionPoint
{
  return [super shouldDrawInsertionPoint];
}

- (void) drawInsertionPointInRect: (NSRect)aRect
			    color: (NSColor*)aColor
			 turnedOn: (BOOL)flag
{
  [super drawInsertionPointInRect: aRect
	 color: aColor
	 turnedOn: flag];
}

- (void) setConstrainedFrameSize: (NSSize)desiredSize
{
  // some black magic here.
  [self setFrameSize: desiredSize];
}

- (void) cleanUpAfterDragOperation
{
  // release drag information
}

- (unsigned int) dragOperationForDraggingInfo: (id <NSDraggingInfo>)dragInfo 
					 type: (NSString *)type
{
  //FIXME
  return NSDragOperationNone;
}

/* 
 * Code to share settings between multiple textviews
 *
 */

/* 
   _syncTextViewsCalling:withFlag: calls a set method on all text
   views sharing the same layout manager as this one.  It sets the
   isSynchronizingFlags flag to YES to prevent recursive calls; calls the
   specified action on all the textviews (this one included) with the
   specified flag; sets back the isSynchronizingFlags flag to NO; then
   returns.

   We need to explicitly call the methods - we can't copy the flags
   directly from one textview to another, to allow subclasses to
   override eg setEditable: to take some particular action when
   editing is turned on or off. */
- (void) _syncTextViewsByCalling: (SEL)action  withFlag: (BOOL)flag
{
  NSArray *array;
  int i, count;
  void (*msg)(id, SEL, BOOL);

  if (isSynchronizingFlags == YES)
    {
      [NSException raise: NSGenericException
		   format: @"_syncTextViewsCalling:withFlag: "
		   @"called recursively"];
    }

  array = [_layoutManager textContainers];
  count = [array count];

  msg = (void (*)(id, SEL, BOOL))[self methodForSelector: action];

  if (!msg)
    {
      [NSException raise: NSGenericException
		   format: @"invalid selector in "
		   @"_syncTextViewsCalling:withFlag:"];
    }

  isSynchronizingFlags = YES;

  for (i = 0; i < count; i++)
    {
      NSTextView *tv; 

      tv = [(NSTextContainer *)[array objectAtIndex: i] textView];
      (*msg) (tv, action, flag);
    }

  isSynchronizingFlags = NO;
}

#define NSTEXTVIEW_SYNC(X) \
  if (_tvf.multiple_textviews && (isSynchronizingFlags == NO)) \
    {  [self _syncTextViewsByCalling: @selector(##X##)  withFlag: flag]; \
    return; }

/*
 * NB: You might override these methods in subclasses, as in the 
 * following example: 
 * - (void) setEditable: (BOOL)flag
 * {
 *   [super setEditable: flag];
 *   XXX your custom code here XXX
 * }
 * 
 * If you override them in this way, they are automatically
 * synchronized between multiple textviews - ie, when it is called on
 * one, it will be automatically called on all related textviews.
 * */

- (void) setEditable: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setEditable:);
  [super setEditable: flag];
  /* FIXME/TODO: Update/show the insertion point */
}

- (void) setFieldEditor: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setFieldEditor:);
  [super setFieldEditor: flag];
}

- (void) setSelectable: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setSelectable:);
  [super setSelectable: flag];
}

- (void) setRichText: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setRichText:);

  [super setRichText: flag];
  [self updateDragTypeRegistration];
  /* FIXME/TODO: Also convert text to plain text or to rich text */
}

- (void) setImportsGraphics: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setImportsGraphics:);

  [super setImportsGraphics: flag];
  [self updateDragTypeRegistration];
}

- (void) setUsesRuler: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setUsesRuler:);
  _tf.uses_ruler = flag;
}

- (BOOL) usesRuler
{
  return _tf.uses_ruler;
}

- (void) setUsesFontPanel: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setUsesFontPanel:);
  [super setUsesFontPanel: flag];
}

- (void) setRulerVisible: (BOOL)flag
{
  NSTEXTVIEW_SYNC (setRulerVisible:);
  [super setRulerVisible: flag];
}

#undef NSTEXTVIEW_SYNC

- (void) setSelectedRange: (NSRange)charRange
		 affinity: (NSSelectionAffinity)affinity
	   stillSelecting: (BOOL)flag
{
  // Use affinity to determine the insertion point

  if (flag)
    {
      _selected_range = charRange;
      [self setSelectionGranularity: NSSelectByCharacter];
    }
  else
      [self setSelectedRange: charRange];
}

- (NSSelectionAffinity) selectionAffinity
{
  return _selectionAffinity;
}

- (void) setSelectionGranularity: (NSSelectionGranularity)granularity
{
  _selectionGranularity = granularity;
}

- (NSSelectionGranularity) selectionGranularity
{
  return _selectionGranularity;
}

- (void) setInsertionPointColor: (NSColor*)aColor
{
  ASSIGN(_caret_color, aColor);
}

- (NSColor*) insertionPointColor
{
  return _caret_color;
}

- (void) updateInsertionPointStateAndRestartTimer: (BOOL)flag
{
  // _caretLocation =

  // restart blinking timer.
}

- (void) setSelectedTextAttributes: (NSDictionary*)attributes
{
  ASSIGN(_selectedTextAttributes, attributes);
}

- (NSDictionary*) selectedTextAttributes
{
  return _selectedTextAttributes;
}

- (NSRange) markedRange
{
  // calculate

  return NSMakeRange(NSNotFound, 0);
}

- (void) setMarkedTextAttributes: (NSDictionary*)attributes
{
  ASSIGN(_markedTextAttributes, attributes);
}

- (NSDictionary*) markedTextAttributes
{
  return _markedTextAttributes;
}

- (NSString*) preferredPasteboardTypeFromArray: (NSArray*)availableTypes
		    restrictedToTypesFromArray: (NSArray*)allowedTypes
{
  return [super preferredPasteboardTypeFromArray: availableTypes
		restrictedToTypesFromArray: allowedTypes];
}

- (BOOL) readSelectionFromPasteboard: (NSPasteboard*)pboard
{
/*
Reads the text view's preferred type of data from the pasteboard specified
by the pboard parameter. This method
invokes the preferredPasteboardTypeFromArray: restrictedToTypesFromArray: 
method to determine the text view's
preferred type of data and then reads the data using the
readSelectionFromPasteboard: type: method. Returns YES if the
data was successfully read.
*/
  return [super readSelectionFromPasteboard: pboard];
}

- (BOOL) readSelectionFromPasteboard: (NSPasteboard*)pboard
				type: (NSString*)type 
{
/*
Reads data of the given type from pboard. The new data is placed at the
current insertion point, replacing the current selection if one exists.
Returns YES if the data was successfully read.

You should override this method to read pasteboard types other than the
default types. Use the rangeForUserTextChange method to obtain the range
of characters (if any) to be replaced by the new data.
*/

  return [super readSelectionFromPasteboard: pboard
		type: type];
}

- (NSArray*) readablePasteboardTypes
{
  // get default types, what are they?
  return [super readablePasteboardTypes];
}

- (NSArray*) writablePasteboardTypes
{
  // the selected text can be written to the pasteboard with which types.
  return [super writablePasteboardTypes];
}

- (BOOL) writeSelectionToPasteboard: (NSPasteboard*)pboard
			       type: (NSString*)type
{
/*
Writes the current selection to pboard using the given type. Returns YES
if the data was successfully written. You can override this method to add
support for writing new types of data to the pasteboard. You should invoke
super's implementation of the method to handle any types of data your
overridden version does not.
*/

  return [super writeSelectionToPasteboard: pboard
		type: type];
}

- (BOOL) writeSelectionToPasteboard: (NSPasteboard*)pboard
			      types: (NSArray*)types
{
/* Writes the current selection to pboard under each type in the types
array. Returns YES if the data for any single type was written
successfully.

You should not need to override this method. You might need to invoke this
method if you are implementing a new type of pasteboard to handle services
other than copy/paste or dragging. */
  return [super writeSelectionToPasteboard: pboard
		types: types];
}

- (void) alignJustified: (id)sender
{
  [self setAlignment: NSJustifiedTextAlignment
	range: [self rangeForUserParagraphAttributeChange]];   
}

- (void) changeColor: (id)sender
{
  NSColor *aColor = (NSColor*)[sender color];
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  // sets the color for the selected range.
  [self setTextColor: aColor
	range: aRange];
}

- (void) setAlignment: (NSTextAlignment)alignment
		range: (NSRange)aRange
{ 
  [super setAlignment: alignment
	 range: aRange];
}

- (void) setTypingAttributes: (NSDictionary*)attributes
{
  [super setTypingAttributes: attributes];
}

- (NSDictionary*) typingAttributes
{
  return [super typingAttributes];
}

- (void) useStandardKerning: (id)sender
{
  // rekern for selected range if rich text, else rekern entire document.
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;
  
  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  [_textStorage removeAttribute: NSKernAttributeName
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) lowerBaseline: (id)sender
{
  id value;
  float sValue;
  NSRange effRange;
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  // We take the value form the first character and use it for the whole range
  value = [_textStorage attribute: NSBaselineOffsetAttributeName
			atIndex: aRange.location
			effectiveRange: &effRange];

  if (value != nil)
    sValue = [value floatValue] + 1.0;
  else
    sValue = 1.0;

  [_textStorage addAttribute: NSBaselineOffsetAttributeName
		value: [NSNumber numberWithFloat: sValue]
		range: aRange];
}

- (void) raiseBaseline: (id)sender
{
  id value;
  float sValue;
  NSRange effRange;
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  // We take the value form the first character and use it for the whole range
  value = [_textStorage attribute: NSBaselineOffsetAttributeName
			atIndex: aRange.location
			effectiveRange: &effRange];

  if (value != nil)
    sValue = [value floatValue] - 1.0;
  else
    sValue = -1.0;

  [_textStorage addAttribute: NSBaselineOffsetAttributeName
		value: [NSNumber numberWithFloat: sValue]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) turnOffKerning: (id)sender
{
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;
  
  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  [_textStorage addAttribute: NSKernAttributeName
		value: [NSNumber numberWithFloat: 0.0]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) loosenKerning: (id)sender
{
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  // FIXME: Should use the current kerning and work relative to point size
  [_textStorage addAttribute: NSKernAttributeName
		value: [NSNumber numberWithFloat: 1.0]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) tightenKerning: (id)sender
{
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  // FIXME: Should use the current kerning and work relative to point size
  [_textStorage addAttribute: NSKernAttributeName
		value: [NSNumber numberWithFloat: -1.0]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) useStandardLigatures: (id)sender
{
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  [_textStorage addAttribute: NSLigatureAttributeName
		value: [NSNumber numberWithInt: 1]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) turnOffLigatures: (id)sender
{
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  [_textStorage addAttribute: NSLigatureAttributeName
		value: [NSNumber numberWithInt: 0]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) useAllLigatures: (id)sender
{
  NSRange aRange = [self rangeForUserCharacterAttributeChange];

  if (aRange.location == NSNotFound)
    return;

  if (![self shouldChangeTextInRange: aRange
	    replacementString: nil])
    return;
  [_textStorage beginEditing];
  [_textStorage addAttribute: NSLigatureAttributeName
		value: [NSNumber numberWithInt: 2]
		range: aRange];
  [_textStorage endEditing];
  [self didChangeText];
}

- (void) clickedOnLink: (id)link
	       atIndex: (unsigned int)charIndex
{

/* Notifies the delegate that the user clicked in a link at the specified
charIndex. The delegate may take any appropriate actions to handle the
click in its textView: clickedOnLink: atIndex: method. */
  if (_delegate != nil && 
      [_delegate respondsToSelector: 
		   @selector(textView:clickedOnLink:atIndex:)])
      [_delegate textView: self clickedOnLink: link atIndex: charIndex];
}

/*
The text is inserted at the insertion point if there is one, otherwise
replacing the selection.
*/

- (void) pasteAsPlainText: (id)sender
{
  [self readSelectionFromPasteboard: [NSPasteboard generalPasteboard]
				type: NSStringPboardType];
}

- (void) pasteAsRichText: (id)sender
{
  [self readSelectionFromPasteboard: [NSPasteboard generalPasteboard]
				type: NSRTFPboardType];
}

- (void) updateFontPanel
{
  [super updateFontPanel];
}

- (void) updateRuler
{
  // ruler!
}

- (NSArray*) acceptableDragTypes
{
  return [self readablePasteboardTypes];
}

- (void) updateDragTypeRegistration
{
  // FIXME: Should change registration for all our text views
  if (_tf.is_editable && _tf.is_rich_text)
    [self registerForDraggedTypes: [self acceptableDragTypes]];
  else
    [self unregisterDraggedTypes];
}

- (NSRange) selectionRangeForProposedRange: (NSRange)proposedSelRange
			       granularity: (NSSelectionGranularity)gr
{
  return [super selectionRangeForProposedRange: proposedSelRange
		granularity: gr];
}

- (NSRange) rangeForUserCharacterAttributeChange
{
  return [super rangeForUserCharacterAttributeChange];
}

- (NSRange) rangeForUserParagraphAttributeChange
{
  return [super rangeForUserParagraphAttributeChange];
}

- (NSRange) rangeForUserTextChange
{
  return [super rangeForUserTextChange];
}


- (id) validRequestorForSendType: (NSString*)sendType
		      returnType: (NSString*)returnType
{
/*
Returns self if sendType specifies a type of data the text view can put on
the pasteboard and returnType contains a type of data the text view can
read from the pasteboard; otherwise returns nil.
*/

 return [super validRequestorForSendType: sendType
		returnType: returnType];
}

- (int) spellCheckerDocumentTag
{
  return [super spellCheckerDocumentTag];
}

- (void) insertText: (NSString*)aString
{
  [super insertText: aString];
}

- (void) sizeToFit
{
  [super sizeToFit];
}

- (BOOL) shouldChangeTextInRange: (NSRange)affectedCharRange
	       replacementString: (NSString*)replacementString
{
/*
This method checks with the delegate as needed using
textShouldBeginEditing: and
textView: shouldChangeTextInRange: replacementString: , returning YES to
allow the change, and NO to prohibit it.

This method must be invoked at the start of any sequence of user-initiated
editing changes. If your subclass of NSTextView implements new methods
that modify the text, make sure to invoke this method to determine whether
the change should be made. If the change is allowed, complete the change
by invoking the didChangeText method. See Notifying About Changes to the
Text in the class description for more information. If you can't determine
the affected range or replacement string before beginning changes, pass
(NSNotFound, 0) and nil for these values. */

  return YES;
}

- (void) didChangeText
{
  [nc postNotificationName: NSTextDidChangeNotification  
      object: _notifObject];
}

- (void) setSmartInsertDeleteEnabled: (BOOL)flag
{
  _tvf.smart_insert_delete = flag;
}

- (BOOL) smartInsertDeleteEnabled
{
  return _tvf.smart_insert_delete;
}

- (NSRange) smartDeleteRangeForProposedRange: (NSRange)proposedCharRange
{
  // FIXME.
  return proposedCharRange;
}

- (NSString *)smartInsertAfterStringForString: (NSString *)aString 
			       replacingRange: (NSRange)charRange
{
  // FIXME.
  return nil;
}

- (NSString *)smartInsertBeforeStringForString: (NSString *)aString 
				replacingRange: (NSRange)charRange
{
  // FIXME.
  return nil;
}

- (void) smartInsertForString: (NSString*)aString
	       replacingRange: (NSRange)charRange
		 beforeString: (NSString**)beforeString 
		  afterString: (NSString**)afterString
{

/* Determines whether whitespace needs to be added around aString to
preserve proper spacing and punctuation when it's inserted into the
receiver's text over charRange. Returns by reference in beforeString and
afterString any whitespace that should be added, unless either or both is
nil. Both are returned as nil if aString is nil or if smart insertion and
deletion is disabled.

As part of its implementation, this method calls
smartInsertAfterStringForString: replacingRange: and
smartInsertBeforeStringForString: replacingRange: .To change this method's
behavior, override those two methods instead of this one.

NSTextView uses this method as necessary. You can also use it in
implementing your own methods that insert text. To do so, invoke this
method with the proper arguments, then insert beforeString, aString, and
afterString in order over charRange. */
  if (beforeString)
    *beforeString = [self smartInsertBeforeStringForString: aString 
			  replacingRange: charRange];

  if (afterString)
    *afterString = [self smartInsertAfterStringForString: aString 
			 replacingRange: charRange];
}

- (BOOL) resignFirstResponder
{
/*
  if (nextRsponder == NSTextView_in_NSLayoutManager)
    return YES;
  else
    {
      if (![self textShouldEndEditing])
	return NO;
      else
	{
  	  [[NSNotificationCenter defaultCenter]
    	    postNotificationName: NSTextDidEndEditingNotification object: self];
	  // [self hideSelection];
	  return YES;
	}
    }
*/
  return [super resignFirstResponder];
}

- (BOOL) becomeFirstResponder
{
/*
  if (!nextRsponder == NSTextView_in_NSLayoutManager)
    {
      //draw selection
      //update the insertion point
    }
*/
  return [super becomeFirstResponder];
}

- (void) rulerView: (NSRulerView*)aRulerView
     didMoveMarker: (NSRulerMarker*)aMarker
{
/*
NSTextView checks for permission to make the change in its
rulerView: shouldMoveMarker: method, which invokes
shouldChangeTextInRange: replacementString: to send out the proper request
and notifications, and only invokes this
method if permission is granted.

  [self didChangeText];
*/
}

- (void) rulerView: (NSRulerView*)aRulerView
   didRemoveMarker: (NSRulerMarker*)aMarker
{
/*
NSTextView checks for permission to move or remove a tab stop in its
rulerView: shouldMoveMarker: method, which invokes
shouldChangeTextInRange: replacementString: to send out the proper request
and notifications, and only invokes this method if permission is granted.
*/
}

- (void)rulerView:(NSRulerView *)ruler 
     didAddMarker:(NSRulerMarker *)marker
{
}

- (void) rulerView: (NSRulerView*)aRulerView
   handleMouseDown: (NSEvent*)theEvent
{
/*
This NSRulerView client method adds a left tab marker to the ruler, but a
subclass can override this method to provide other behavior, such as
creating guidelines. This method is invoked once with theEvent when the
user first clicks in the aRulerView's ruler area, as described in the
NSRulerView class specification.
*/
}

- (BOOL) rulerView: (NSRulerView*)aRulerView
   shouldAddMarker: (NSRulerMarker*)aMarker
{

/* This NSRulerView client method controls whether a new tab stop can be
added. The receiver checks for permission to make the change by invoking
shouldChangeTextInRange: replacementString: and returning the return value
of that message. If the change is allowed, the receiver is then sent a
rulerView: didAddMarker: message. */

  return NO;
}

- (BOOL) rulerView: (NSRulerView*)aRulerView
  shouldMoveMarker: (NSRulerMarker*)aMarker
{

/* This NSRulerView client method controls whether an existing tab stop
can be moved. The receiver checks for permission to make the change by
invoking shouldChangeTextInRange: replacementString: and returning the
return value of that message. If the change is allowed, the receiver is
then sent a rulerView: didAddMarker: message. */

  return NO;
}

- (BOOL) rulerView: (NSRulerView*)aRulerView
shouldRemoveMarker: (NSRulerMarker*)aMarker
{

/* This NSRulerView client method controls whether an existing tab stop
can be removed. Returns YES if aMarker represents an NSTextTab, NO
otherwise. Because this method can be invoked repeatedly as the user drags
a ruler marker, it returns that value immediately. If the change is allows
and the user actually removes the marker, the receiver is also sent a
rulerView: didRemoveMarker: message. */

  return NO;
}

- (float) rulerView: (NSRulerView*)aRulerView
      willAddMarker: (NSRulerMarker*)aMarker 
	 atLocation: (float)location
{

/* This NSRulerView client method ensures that the proposed location of
aMarker lies within the appropriate bounds for the receiver's text
container, returning the modified location. */

  return 0.0;
}

- (float) rulerView: (NSRulerView*)aRulerView
     willMoveMarker: (NSRulerMarker*)aMarker 
	 toLocation: (float)location
{

/* This NSRulerView client method ensures that the proposed location of
aMarker lies within the appropriate bounds for the receiver's text
container, returning the modified location. */

  return 0.0;
}

- (void) setDelegate: (id)anObject
{
  /* Code to allow sharing the delegate */
  if (_tvf.multiple_textviews && (isSynchronizingDelegate == NO))
    {
      /* Invoke setDelegate: on all the textviews which share this
         delegate. */
      NSArray *array;
      int i, count;

      isSynchronizingDelegate = YES;

      array = [_layoutManager textContainers];
      count = [array count];

      for (i = 0; i < count; i++)
	{
	  NSTextView *view;

	  view = [(NSTextContainer *)[array objectAtIndex: i] textView];
	  [view setDelegate: anObject];
	}
      
      isSynchronizingDelegate = NO;
    }

  /* Now the real code to set the delegate */

  if (_delegate != nil)
    {
      [nc removeObserver: _delegate  name: nil  object: _notifObject];
    }

  [super setDelegate: anObject];

  /* SET_DELEGATE_NOTIFICATION defined at the beginning of file */

  /* NSText notifications */
  SET_DELEGATE_NOTIFICATION (DidBeginEditing);
  SET_DELEGATE_NOTIFICATION (DidChange);
  SET_DELEGATE_NOTIFICATION (DidEndEditing);

  /* NSTextView notifications */
  SET_DELEGATE_NOTIFICATION (ViewDidChangeSelection);
  SET_DELEGATE_NOTIFICATION (ViewWillChangeNotifyingTextView);
}

@end

@implementation NSTextView(NSTextInput)
// This are all the NSTextInput methods that are not implemented on NSTextView
// or one of its super classes.

- (void)setMarkedText:(NSString *)aString selectedRange:(NSRange)selRange
{
}

- (BOOL)hasMarkedText
{
  return NO;
}

- (void)unmarkText
{
}

- (NSArray*)validAttributesForMarkedText
{
  return nil;
}

- (long)conversationIdentifier
{
  return 0;
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange
{
  return NSZeroRect;
}
@end

