/*
 * Copyright (c) 1999-2007 Apple Inc.  All Rights Reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

#include <TargetConditionals.h>
#if defined(__i386__)  &&  !TARGET_IPHONE_SIMULATOR

/********************************************************************
 ********************************************************************
 **
 **  objc-msg-i386.s - i386 code to support objc messaging.
 **
 ********************************************************************
 ********************************************************************/

// for kIgnore
#include "objc-config.h"


/********************************************************************
* Data used by the ObjC runtime.
*
********************************************************************/

.data
// Substitute receiver for messages sent to nil (usually also nil)
// id _objc_nilReceiver
.align 4
.globl __objc_nilReceiver
__objc_nilReceiver:
    .long   0

// _objc_entryPoints and _objc_exitPoints are used by objc
// to get the critical regions for which method caches 
// cannot be garbage collected.

.long _objc_entryPoints
_objc_entryPoints:
    .long   _cache_getImp
    .long   _cache_getMethod
    .long   objc_msgSend
    .long   objc_msgSend_fpret
    .long   objc_msgSend_stret
    .long   objc_msgSendSuper
    .long   objc_msgSendSuper2
    .long   objc_msgSendSuper_stret
    .long   objc_msgSendSuper2_stret
    .long   0

.long _objc_exitPoints
_objc_exitPoints:
    .long   LGetImpExit
    .long   LGetMethodExit
    .long   LMsgSendExit
    .long   LMsgSendFpretExit
    .long   LMsgSendStretExit
    .long   LMsgSendSuperExit
    .long   LMsgSendSuper2Exit
    .long   LMsgSendSuperStretExit
    .long   LMsgSendSuper2StretExit
    .long   0


/********************************************************************
 *
 * Common offsets.
 *
 ********************************************************************/

    self            = 4
    super           = 4
    selector        = 8
    marg_size       = 12
    marg_list       = 16
    first_arg       = 12

    struct_addr     = 4

    self_stret      = 8
    super_stret     = 8
    selector_stret  = 12
    marg_size_stret = 16
    marg_list_stret = 20


/********************************************************************
 *
 * Structure definitions.
 *
 ********************************************************************/

// objc_super parameter to sendSuper
    receiver        = 0
    class           = 4

// Selected field offsets in class structure
    isa             = 0
    superclass      = 4
//#if __OBJC2__
    cache           = 8
//#else
//  cache           = 32
//#endif

// Method descriptor
    method_name     = 0
    method_imp      = 8

// Cache header
    mask            = 0
    occupied        = 4
    buckets         = 8     // variable length array

#if defined(OBJC_INSTRUMENTED)
// Cache instrumentation data, follows buckets
    hitCount        = 0
    hitProbes       = hitCount + 4
    maxHitProbes    = hitProbes + 4
    missCount       = maxHitProbes + 4
    missProbes      = missCount + 4
    maxMissProbes   = missProbes + 4
    flushCount      = maxMissProbes + 4
    flushedEntries  = flushCount + 4

// Buckets in CacheHitHistogram and CacheMissHistogram
    CACHE_HISTOGRAM_SIZE = 512
#endif


//////////////////////////////////////////////////////////////////////
//
// LOAD_STATIC_WORD targetReg, symbolName, LOCAL_SYMBOL | EXTERNAL_SYMBOL
//
// Load the value of the named static data word.
//
// Takes: targetReg       - the register, other than r0, to load
//        symbolName      - the name of the symbol
//        LOCAL_SYMBOL    - symbol name used as-is
//        EXTERNAL_SYMBOL - symbol name gets nonlazy treatment
//
// Eats: edx and targetReg
//////////////////////////////////////////////////////////////////////

// Values to specify whether the symbol is plain or nonlazy
LOCAL_SYMBOL    = 0
EXTERNAL_SYMBOL = 1

.macro  LOAD_STATIC_WORD targetReg, symbolName, symbol

#if defined(__DYNAMIC__)
    call    1f
1:  popl    %edx
.if symbol == EXTERNAL_SYMBOL
    movl    L\symbolName-1b(%edx),\targetReg
    movl    0(\targetReg),\targetReg
.elseif symbol == LOCAL_SYMBOL
    movl    \symbolName-1b(%edx),\targetReg
.else
    // !!! Unknown symbol type !!!
.endif
#else
    movl    \symbolName,\targetReg
#endif

.endm

//////////////////////////////////////////////////////////////////////
//
// LEA_STATIC_DATA  targetReg, symbolName, LOCAL_SYMBOL | EXTERNAL_SYMBOL
//
// Load the address of the named static data.
//
// Takes: targetReg       - the register, other than edx, to load
//        symbolName      - the name of the symbol
//        LOCAL_SYMBOL    - symbol is local to this module
//        EXTERNAL_SYMBOL - symbol is imported from another module
//
// Eats: edx and targetReg
//////////////////////////////////////////////////////////////////////

.macro  LEA_STATIC_DATA targetReg, symbolName, symbol
#if defined(__DYNAMIC__)
    call    1f
1:  popl    %edx
.if symbol == EXTERNAL_SYMBOL
    movl    L\symbolName-1b(%edx),\targetReg
.elseif symbol == LOCAL_SYMBOL
    leal    \symbolName-1b(%edx),\targetReg
.else
    // !!! Unknown symbol type !!!
.endif
#else
    leal    \symbolName,\targetReg
#endif

.endm

//////////////////////////////////////////////////////////////////////
//
// ENTRY        functionName
//
// Assembly directives to begin an exported function.
//
// Takes: functionName - name of the exported function
//////////////////////////////////////////////////////////////////////

.macro ENTRY name
    .text
    .globl  \name
    .align  2, 0x90
\name:
.endm

.macro STATIC_ENTRY name
    .text
    .globl  \name
    .align  4, 0x90
\name:
.endm

//////////////////////////////////////////////////////////////////////
//
// END_ENTRY    functionName
//
// Assembly directives to end an exported function.  Just a placeholder,
// a close-parenthesis for ENTRY, until it is needed for something.
//
// Takes: functionName - name of the exported function
//////////////////////////////////////////////////////////////////////

.macro END_ENTRY name
.endm

//////////////////////////////////////////////////////////////////////
//
// CALL_MCOUNTER
//
// Calls mcount() profiling routine. Must be called immediately on
// function entry, before any prologue executes.
//
//////////////////////////////////////////////////////////////////////

.macro CALL_MCOUNTER
#ifdef PROFILE
    // Current stack contents: ret
    pushl   %ebp
    movl    %esp,%ebp
    subl    $8,%esp
    // Current stack contents: ret, ebp, pad, pad
    call    mcount
    movl    %ebp,%esp
    popl    %ebp
#endif
.endm


/////////////////////////////////////////////////////////////////////
//
//
// CacheLookup  WORD_RETURN | STRUCT_RETURN, MSG_SEND | MSG_SENDSUPER | MSG_SENDSUPER2 | CACHE_GET, cacheMissLabel
//
// Locate the implementation for a selector in a class method cache.
//
// Takes: WORD_RETURN      (first parameter is at sp+4)
//        STRUCT_RETURN    (struct address is at sp+4, first parameter at sp+8)
//        MSG_SEND     (first parameter is receiver)
//        MSG_SENDSUPER[2] (first parameter is address of objc_super structure)
//        CACHE_GET    (first parameter is class; return method triplet)
//        selector in %ecx
//        class to search in %edx
//
//    cacheMissLabel = label to branch to iff method is not cached
//
// On exit: (found) MSG_SEND and MSG_SENDSUPER[2]: return imp in eax
//          (found) CACHE_GET: return method triplet in eax
//          (not found) jumps to cacheMissLabel
//  
/////////////////////////////////////////////////////////////////////


// Values to specify to method lookup macros whether the return type of
// the method is word or structure.
WORD_RETURN   = 0
STRUCT_RETURN = 1

// Values to specify to method lookup macros whether the first argument
// is an object/class reference or a 'objc_super' structure.
MSG_SEND       = 0  // first argument is receiver, search the isa
MSG_SENDSUPER  = 1  // first argument is objc_super, search the class
MSG_SENDSUPER2 = 2  // first argument is objc_super, search the class
CACHE_GET      = 3  // first argument is class, search that class

.macro  CacheLookup retType, msgType, cacheMissLabel

// load variables and save caller registers.

    pushl   %edi            // save scratch register
    movl    cache(%edx), %edi   // cache = class->cache
    pushl   %esi            // save scratch register

    movl    mask(%edi), %esi        // mask = cache->mask
    movl    %ecx, %edx      // index = selector
    shrl    $2, %edx        // index = selector >> 2

// search the receiver's cache
// ecx = selector
// edi = cache
// esi = mask
// edx = index
// eax = method (soon)
LMsgSendProbeCache_\retType\()_\msgType\()_\cacheMissLabel\():
    andl    %esi, %edx      // index &= mask
    movl    buckets(%edi, %edx, 4), %eax    // meth = cache->buckets[index]

    testl   %eax, %eax      // check for end of bucket
    je  LMsgSendCacheMiss_\retType\()_\msgType\()_\cacheMissLabel // go to cache miss code
    cmpl    method_name(%eax), %ecx // check for method name match
    je  LMsgSendCacheHit_\retType\()_\msgType\()_\cacheMissLabel  // go handle cache hit
    addl    $1, %edx            // bump index ...
    jmp LMsgSendProbeCache_\retType\()_\msgType\()_\cacheMissLabel // ... and loop

// not found in cache: restore state and go to callers handler
LMsgSendCacheMiss_\retType\()_\msgType\()_\cacheMissLabel:

.if \retType == WORD_RETURN          // Regular word return
.if \msgType == MSG_SEND         // MSG_SEND
    popl    %esi            //  restore callers register
    popl    %edi            //  restore callers register
    movl    self(%esp), %edx    //  get messaged object
    movl    isa(%edx), %eax     //  get objects class
.elseif \msgType == MSG_SENDSUPER || \msgType == MSG_SENDSUPER2  // MSG_SENDSUPER[2]
    // replace "super" arg with "receiver"
    movl    super+8(%esp), %edi //  get super structure
    movl    receiver(%edi), %edx    //  get messaged object
    movl    %edx, super+8(%esp) //  make it the first argument
    movl    class(%edi), %eax   //  get messaged class
    .if \msgType == MSG_SENDSUPER2
    movl    superclass(%eax), %eax  //  get messaged class
    .endif
    popl    %esi            //  restore callers register
    popl    %edi            //  restore callers register
.else                   // CACHE_GET
    popl    %esi            //  restore callers register
    popl    %edi            //  restore callers register
.endif
.else                   // Struct return
.if \msgType == MSG_SEND         // MSG_SEND (stret)
    popl    %esi            //  restore callers register
    popl    %edi            //  restore callers register
    movl    self_stret(%esp), %edx  //  get messaged object
    movl    isa(%edx), %eax     //  get objects class
.elseif \msgType == MSG_SENDSUPER || \msgType == MSG_SENDSUPER2 // MSG_SENDSUPER[2] (stret)
    // replace "super" arg with "receiver"
    movl    super_stret+8(%esp), %edi//  get super structure
    movl    receiver(%edi), %edx    //  get messaged object
    movl    %edx, super_stret+8(%esp)//  make it the first argument
    movl    class(%edi), %eax   //  get messaged class
    .if \msgType == MSG_SENDSUPER2
    movl    superclass(%eax), %eax  //  get messaged class
    .endif
    popl    %esi            //  restore callers register
    popl    %edi            //  restore callers register
.else                   // CACHE_GET
    // !! This should not happen.
.endif
.endif

                    // edx = receiver
                    // ecx = selector
                    // eax = class
    jmp \cacheMissLabel         // go to callers handler

// eax points to matching cache entry
    .align  4, 0x90
LMsgSendCacheHit_\retType\()_\msgType\()_\cacheMissLabel:

// load implementation address, restore state, and we're done
.if \msgType == CACHE_GET
    // method triplet is already in eax
.else
    movl    method_imp(%eax), %eax  // imp = method->method_imp
.endif

.if \retType == WORD_RETURN          // Regular word return
.if \msgType == MSG_SENDSUPER || \msgType == MSG_SENDSUPER2
    // replace "super" arg with "self"
    movl    super+8(%esp), %edi
    movl    receiver(%edi), %esi
    movl    %esi, super+8(%esp)
.endif
.else                   // Struct return
.if \msgType == MSG_SENDSUPER || \msgType == MSG_SENDSUPER2
    // replace "super" arg with "self"
    movl    super_stret+8(%esp), %edi
    movl    receiver(%edi), %esi
    movl    %esi, super_stret+8(%esp)
.endif
.endif

    // restore caller registers
    popl    %esi
    popl    %edi
.endm


/////////////////////////////////////////////////////////////////////
//
// MethodTableLookup WORD_RETURN | STRUCT_RETURN, MSG_SEND | MSG_SENDSUPER
//
// Takes: WORD_RETURN   (first parameter is at sp+4)
//    STRUCT_RETURN (struct address is at sp+4, first parameter at sp+8)
//    MSG_SEND  (first parameter is receiver)
//    MSG_SENDSUPER (first parameter is address of objc_super structure)
//
//    edx = receiver
//    ecx = selector
//    eax = class
//        (all set by CacheLookup's miss case)
// 
// Stack must be at 0xXXXXXXXc on entrance.
//
// On exit:  esp unchanged
//           imp in eax
//
/////////////////////////////////////////////////////////////////////

.macro MethodTableLookup retType, sendType
    // stack is already aligned
    pushl   %eax            // class
    pushl   %ecx            // selector
    pushl   %edx            // receiver
    call    _class_lookupMethodAndLoadCache3
    addl    $12, %esp       // pop parameters
.endm


/********************************************************************
 * Method _cache_getMethod(Class cls, SEL sel, IMP msgForward_internal_imp)
 *
 * If found, returns method triplet pointer.
 * If not found, returns NULL.
 *
 * NOTE: _cache_getMethod never returns any cache entry whose implementation
 * is _objc_msgForward_internal. It returns 1 instead. This prevents thread-
 * safety and memory management bugs in _class_lookupMethodAndLoadCache. 
 * See _class_lookupMethodAndLoadCache for details.
 *
 * _objc_msgForward_internal is passed as a parameter because it's more 
 * efficient to do the (PIC) lookup once in the caller than repeatedly here.
 ********************************************************************/
        
    STATIC_ENTRY _cache_getMethod

// load the class and selector
    movl    selector(%esp), %ecx
    movl    self(%esp), %edx

// do lookup
    CacheLookup WORD_RETURN, CACHE_GET, LGetMethodMiss

// cache hit, method triplet in %eax
    movl    first_arg(%esp), %ecx   // check for _objc_msgForward_internal
    cmpl    method_imp(%eax), %ecx  // if (imp==_objc_msgForward_internal)
    je      1f                      //     return (Method)1
    ret                             // else return method triplet address
1:  movl    $1, %eax
    ret

LGetMethodMiss:
// cache miss, return nil
    xorl    %eax, %eax      // zero %eax
    ret

LGetMethodExit:
    END_ENTRY _cache_getMethod


/********************************************************************
 * IMP _cache_getImp(Class cls, SEL sel)
 *
 * If found, returns method implementation.
 * If not found, returns NULL.
 ********************************************************************/

    STATIC_ENTRY _cache_getImp

// load the class and selector
    movl    selector(%esp), %ecx
    movl    self(%esp), %edx

// do lookup
    CacheLookup WORD_RETURN, CACHE_GET, LGetImpMiss

// cache hit, method triplet in %eax
    movl    method_imp(%eax), %eax  // return method imp
    ret

LGetImpMiss:
// cache miss, return nil
    xorl    %eax, %eax      // zero %eax
    ret

LGetImpExit:
    END_ENTRY _cache_getImp


/********************************************************************
 *
 * id objc_msgSend(id self, SEL _cmd,...);
 *
 ********************************************************************/

    ENTRY   objc_msgSend
    CALL_MCOUNTER

// load receiver and selector
    movl    selector(%esp), %ecx
    movl    self(%esp), %eax

// check whether selector is ignored
    cmpl    $ kIgnore, %ecx
    je      LMsgSendDone        // return self from %eax

// check whether receiver is nil 
    testl   %eax, %eax
    je  LMsgSendNilSelf

// receiver (in %eax) is non-nil: search the cache
LMsgSendReceiverOk:
    movl    isa(%eax), %edx     // class = self->isa
    CacheLookup WORD_RETURN, MSG_SEND, LMsgSendCacheMiss
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax

// cache miss: go search the method lists
LMsgSendCacheMiss:
    MethodTableLookup WORD_RETURN, MSG_SEND
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// message sent to nil: redirect to nil receiver, if any
LMsgSendNilSelf:
    call    1f          // load new receiver
1:  popl    %edx
    movl    __objc_nilReceiver-1b(%edx),%eax
    testl   %eax, %eax      // return nil if no new receiver
    je  LMsgSendReturnZero
    movl    %eax, self(%esp)    // send to new receiver
    jmp LMsgSendReceiverOk  // receiver must be in %eax
LMsgSendReturnZero:
    // %eax is already zero
    movl    $0,%edx
LMsgSendDone:
    ret

// guaranteed non-nil entry point (disabled for now)
// .globl _objc_msgSendNonNil
// _objc_msgSendNonNil:
//  movl    self(%esp), %eax
//  jmp     LMsgSendReceiverOk

LMsgSendExit:
    END_ENTRY   objc_msgSend

/********************************************************************
 *
 * id objc_msgSendSuper(struct objc_super *super, SEL _cmd,...);
 *
 * struct objc_super {
 *      id  receiver;
 *      Class   class;
 * };
 ********************************************************************/

    ENTRY   objc_msgSendSuper
    CALL_MCOUNTER

// load selector and class to search
    movl    super(%esp), %eax   // struct objc_super
    movl    selector(%esp), %ecx
    movl    class(%eax), %edx   // struct objc_super->class

// check whether selector is ignored
    cmpl    $ kIgnore, %ecx
    je      LMsgSendSuperIgnored    // return self from %eax

// search the cache (class in %edx)
    CacheLookup WORD_RETURN, MSG_SENDSUPER, LMsgSendSuperCacheMiss
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// cache miss: go search the method lists
LMsgSendSuperCacheMiss:
    MethodTableLookup WORD_RETURN, MSG_SENDSUPER
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// ignored selector: return self
LMsgSendSuperIgnored:
    movl    super(%esp), %eax
    movl    receiver(%eax), %eax
    ret
    
LMsgSendSuperExit:
    END_ENTRY   objc_msgSendSuper

    ENTRY   objc_msgSendSuper2

// load selector and class to search
    movl    super(%esp), %eax   // struct objc_super
    movl    selector(%esp), %ecx
    movl    class(%eax), %eax   // struct objc_super->class
    mov superclass(%eax), %edx  // edx = objc_super->class->super_class

#if SUPPORT_IGNORED_SELECTOR_CONSTANT
// check whether selector is ignored
    cmpl    $ kIgnore, %ecx
    je      LMsgSendSuperIgnored    // return self from %eax
#endif

// search the cache (class in %edx)
    CacheLookup WORD_RETURN, MSG_SENDSUPER2, LMsgSendSuper2CacheMiss
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// cache miss: go search the method lists
LMsgSendSuper2CacheMiss:
    MethodTableLookup WORD_RETURN, MSG_SENDSUPER2
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// ignored selector: return self
LMsgSendSuper2Ignored:
    movl    super(%esp), %eax
    movl    receiver(%eax), %eax
    ret
    
LMsgSendSuper2Exit:
    END_ENTRY   objc_msgSendSuper2



    ENTRY   objc_msgSendSuper2_stret

// load selector and class to search
    movl    super_stret(%esp), %eax // struct objc_super
    movl    (selector_stret)(%esp), %ecx    //   get selector
    movl    class(%eax), %eax   // struct objc_super->class
    mov superclass(%eax), %edx  // edx = objc_super->class->super_class

// search the cache (class in %edx)
    CacheLookup STRUCT_RETURN, MSG_SENDSUPER2, LMsgSendSuper2StretCacheMiss
    movl    $1, %edx        // set stret for objc_msgForward
    jmp *%eax           // goto *imp

// cache miss: go search the method lists
LMsgSendSuper2StretCacheMiss:
    MethodTableLookup STRUCT_RETURN, MSG_SENDSUPER2
    movl    $1, %edx        // set stret for objc_msgForward
    jmp *%eax           // goto *imp

LMsgSendSuper2StretExit:
    END_ENTRY   objc_msgSendSuper2_stret


/********************************************************************
 * id objc_msgSendv(id self, SEL _cmd, unsigned size, marg_list frame);
 *
 * On entry:
 *      (sp+4)  is the message receiver,
 *      (sp+8)  is the selector,
 *      (sp+12) is the size of the marg_list, in bytes,
 *      (sp+16) is the address of the marg_list
 *
 ********************************************************************/

    ENTRY   _objc_msgSendv

#if defined(KERNEL)
    trap                // _objc_msgSendv is not for the kernel
#else
    pushl   %ebp
    movl    %esp, %ebp
    // stack is currently aligned assuming no extra arguments
    movl    (marg_list+4)(%ebp), %edx
    addl    $8, %edx            // skip self & selector
    movl    (marg_size+4)(%ebp), %ecx
    subl    $8, %ecx            // skip self & selector
    shrl    $2, %ecx
    je      LMsgSendvArgsOK

    // %esp = %esp - (16 - ((numVariableArguments & 3) << 2))
    movl    %ecx, %eax          // 16-byte align stack
    andl    $3, %eax
    shll    $2, %eax
    subl    $16, %esp
    addl    %eax, %esp

LMsgSendvArgLoop:
    decl    %ecx
    movl    0(%edx, %ecx, 4), %eax
    pushl   %eax
    jg  LMsgSendvArgLoop

LMsgSendvArgsOK:
    movl    (selector+4)(%ebp), %ecx
    pushl   %ecx
    movl    (self+4)(%ebp),%ecx
    pushl   %ecx
    call    objc_msgSend
    movl    %ebp,%esp
    popl    %ebp

    ret
#endif
    END_ENTRY   _objc_msgSendv

/********************************************************************
 *
 * double objc_msgSend_fpret(id self, SEL _cmd,...);
 *
 ********************************************************************/

    ENTRY   objc_msgSend_fpret
    CALL_MCOUNTER

// load receiver and selector
    movl    selector(%esp), %ecx
    movl    self(%esp), %eax

// check whether selector is ignored
    cmpl    $ kIgnore, %ecx
    je      LMsgSendFpretDone   // return self from %eax

// check whether receiver is nil 
    testl   %eax, %eax
    je  LMsgSendFpretNilSelf

// receiver (in %eax) is non-nil: search the cache
LMsgSendFpretReceiverOk:
    movl    isa(%eax), %edx     // class = self->isa
    CacheLookup WORD_RETURN, MSG_SEND, LMsgSendFpretCacheMiss
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// cache miss: go search the method lists
LMsgSendFpretCacheMiss:
    MethodTableLookup WORD_RETURN, MSG_SEND
    xor %edx, %edx      // set nonstret for msgForward_internal
    jmp *%eax           // goto *imp

// message sent to nil: redirect to nil receiver, if any
LMsgSendFpretNilSelf:
    call    1f          // load new receiver
1:  popl    %edx
    movl    __objc_nilReceiver-1b(%edx),%eax
    testl   %eax, %eax      // return zero if no new receiver
    je  LMsgSendFpretReturnZero
    movl    %eax, self(%esp)    // send to new receiver
    jmp LMsgSendFpretReceiverOk // receiver must be in %eax
LMsgSendFpretReturnZero:
    fldz
LMsgSendFpretDone:
    ret

LMsgSendFpretExit:
    END_ENTRY   objc_msgSend_fpret
    
/********************************************************************
 * double objc_msgSendv_fpret(id self, SEL _cmd, unsigned size, marg_list frame);
 *
 * On entry:
 *      (sp+4)  is the message receiver,
 *      (sp+8)  is the selector,
 *      (sp+12) is the size of the marg_list, in bytes,
 *      (sp+16) is the address of the marg_list
 *
 ********************************************************************/

    ENTRY   _objc_msgSendv_fpret

#if defined(KERNEL)
    trap                // _objc_msgSendv is not for the kernel
#else
    pushl   %ebp
    movl    %esp, %ebp
    // stack is currently aligned assuming no extra arguments
    movl    (marg_list+4)(%ebp), %edx
    addl    $8, %edx            // skip self & selector
    movl    (marg_size+4)(%ebp), %ecx
    subl    $8, %ecx            // skip self & selector
    shrl    $2, %ecx
    je      LMsgSendvFpretArgsOK

    // %esp = %esp - (16 - ((numVariableArguments & 3) << 2))
    movl    %ecx, %eax          // 16-byte align stack
    andl    $3, %eax
    shll    $2, %eax
    subl    $16, %esp
    addl    %eax, %esp

LMsgSendvFpretArgLoop:
    decl    %ecx
    movl    0(%edx, %ecx, 4), %eax
    pushl   %eax
    jg  LMsgSendvFpretArgLoop

LMsgSendvFpretArgsOK:
    movl    (selector+4)(%ebp), %ecx
    pushl   %ecx
    movl    (self+4)(%ebp),%ecx
    pushl   %ecx
    call    objc_msgSend_fpret
    movl    %ebp,%esp
    popl    %ebp

    ret
#endif
    END_ENTRY   _objc_msgSendv_fpret

/********************************************************************
 *
 * void objc_msgSend_stret(void *st_addr    , id self, SEL _cmd, ...);
 *
 *
 * objc_msgSend_stret is the struct-return form of msgSend.
 * The ABI calls for (sp+4) to be used as the address of the structure
 * being returned, with the parameters in the succeeding locations.
 *
 * On entry:    (sp+4)is the address where the structure is returned,
 *      (sp+8) is the message receiver,
 *      (sp+12) is the selector
 ********************************************************************/

    ENTRY   objc_msgSend_stret
    CALL_MCOUNTER

// load receiver and selector
    movl    self_stret(%esp), %eax
    movl    (selector_stret)(%esp), %ecx

// check whether receiver is nil 
    testl   %eax, %eax
    je  LMsgSendStretNilSelf

// receiver (in %eax) is non-nil: search the cache
LMsgSendStretReceiverOk:
    movl    isa(%eax), %edx     //   class = self->isa
    CacheLookup STRUCT_RETURN, MSG_SEND, LMsgSendStretCacheMiss
    movl    $1, %edx        // set stret for objc_msgForward
    jmp *%eax           // goto *imp

// cache miss: go search the method lists
LMsgSendStretCacheMiss:
    MethodTableLookup STRUCT_RETURN, MSG_SEND
    movl    $1, %edx        // set stret for objc_msgForward
    jmp *%eax           // goto *imp

// message sent to nil: redirect to nil receiver, if any
LMsgSendStretNilSelf:
    call    1f          // load new receiver
1:  popl    %edx
    movl    __objc_nilReceiver-1b(%edx),%eax
    testl   %eax, %eax      // return nil if no new receiver
    je  LMsgSendStretDone
    movl    %eax, self_stret(%esp)  // send to new receiver
    jmp LMsgSendStretReceiverOk // receiver must be in %eax
LMsgSendStretDone:
    ret $4          // pop struct return address (#2995932)

// guaranteed non-nil entry point (disabled for now)
// .globl _objc_msgSendNonNil_stret
// _objc_msgSendNonNil_stret:
//  CALL_MCOUNTER
//  movl    self_stret(%esp), %eax
//  jmp     LMsgSendStretReceiverOk

LMsgSendStretExit:
    END_ENTRY   objc_msgSend_stret

/********************************************************************
 *
 * void objc_msgSendSuper_stret(void *st_addr, struct objc_super *super, SEL _cmd, ...);
 *
 * struct objc_super {
 *      id  receiver;
 *      Class   class;
 * };
 *
 * objc_msgSendSuper_stret is the struct-return form of msgSendSuper.
 * The ABI calls for (sp+4) to be used as the address of the structure
 * being returned, with the parameters in the succeeding registers.
 *
 * On entry:    (sp+4)is the address where the structure is returned,
 *      (sp+8) is the address of the objc_super structure,
 *      (sp+12) is the selector
 *
 ********************************************************************/

    ENTRY   objc_msgSendSuper_stret
    CALL_MCOUNTER

// load selector and class to search
    movl    super_stret(%esp), %eax // struct objc_super
    movl    (selector_stret)(%esp), %ecx    //   get selector
    movl    class(%eax), %edx   // struct objc_super->class

// search the cache (class in %edx)
    CacheLookup STRUCT_RETURN, MSG_SENDSUPER, LMsgSendSuperStretCacheMiss
    movl    $1, %edx        // set stret for objc_msgForward
    jmp *%eax           // goto *imp

// cache miss: go search the method lists
LMsgSendSuperStretCacheMiss:
    MethodTableLookup STRUCT_RETURN, MSG_SENDSUPER
    movl    $1, %edx        // set stret for objc_msgForward
    jmp *%eax           // goto *imp

LMsgSendSuperStretExit:
    END_ENTRY   objc_msgSendSuper_stret


/********************************************************************
 * void objc_msgSendv_stret(void *st_addr, id self, SEL _cmd, unsigned size, marg_list frame);
 *
 * objc_msgSendv_stret is the struct-return form of msgSendv.
 * This function does not use the struct-return ABI; instead, the
 * structure return address is passed as a normal parameter.
 * 
 * On entry:    (sp+4)  is the address in which the returned struct is put,
 *      (sp+8)  is the message receiver,
 *      (sp+12) is the selector,
 *      (sp+16) is the size of the marg_list, in bytes,
 *      (sp+20) is the address of the marg_list
 *
 ********************************************************************/

    ENTRY   _objc_msgSendv_stret

#if defined(KERNEL)
    trap                // _objc_msgSendv_stret is not for the kernel
#else
    pushl   %ebp
    movl    %esp, %ebp
    subl    $12, %esp   // align stack assuming no extra arguments
    movl    (marg_list_stret+4)(%ebp), %edx
    addl    $8, %edx            // skip self & selector
    movl    (marg_size_stret+4)(%ebp), %ecx
    subl    $5, %ecx            // skip self & selector
    shrl    $2, %ecx
    jle LMsgSendvStretArgsOK

    // %esp = %esp - (16 - ((numVariableArguments & 3) << 2))
    movl    %ecx, %eax          // 16-byte align stack
    andl    $3, %eax
    shll    $2, %eax
    subl    $16, %esp
    addl    %eax, %esp

LMsgSendvStretArgLoop:
    decl    %ecx
    movl    0(%edx, %ecx, 4), %eax
    pushl   %eax
    jg  LMsgSendvStretArgLoop

LMsgSendvStretArgsOK:
    movl    (selector_stret+4)(%ebp), %ecx
    pushl   %ecx
    movl    (self_stret+4)(%ebp),%ecx
    pushl   %ecx
    movl    (struct_addr+4)(%ebp),%ecx
    pushl   %ecx
    call    objc_msgSend_stret
    movl    %ebp,%esp
    popl    %ebp

    ret
#endif
    END_ENTRY   _objc_msgSendv_stret


/********************************************************************
 *
 * id _objc_msgForward(id self, SEL _cmd,...);
 *
 ********************************************************************/

// _FwdSel is @selector(forward::), set up in map_images().
// ALWAYS dereference _FwdSel to get to "forward::" !!
    .data
    .align 2
    .globl _FwdSel
_FwdSel: .long 0

    .align 2
LUnkSelStr: .ascii "Does not recognize selector %s (while forwarding %s)\0"

    .data
    .align 2
    .globl _objc_forward_handler
_objc_forward_handler:  .long 0

    .data
    .align 2
    .globl _objc_forward_stret_handler
_objc_forward_stret_handler:    .long 0

    STATIC_ENTRY    _objc_msgForward_internal
    // Method cache version
    
    // THIS IS NOT A CALLABLE C FUNCTION
    // Out-of-band register %edx is nonzero for stret, zero otherwise
    
    // Check return type (stret or not)
    testl   %edx, %edx
    jnz _objc_msgForward_stret
    jmp _objc_msgForward
    
    END_ENTRY   _objc_msgForward_internal

    
    STATIC_ENTRY    _objc_msgForward
    // Non-struct return version

    // Get PIC base into %edx
    call    L__objc_msgForward$pic_base
L__objc_msgForward$pic_base:
    popl    %edx
    
    // Call user handler, if any
    movl    _objc_forward_handler-L__objc_msgForward$pic_base(%edx),%ecx
    testl   %ecx, %ecx      // if not NULL
    je  1f          //   skip to default handler
    jmp *%ecx           // call _objc_forward_handler
1:  
    // No user handler
    // Push stack frame
    pushl   %ebp
    movl    %esp, %ebp
    
    // Die if forwarding "forward::"
    movl    (selector+4)(%ebp), %eax
    movl    _FwdSel-L__objc_msgForward$pic_base(%edx),%ecx
    cmpl    %ecx, %eax
    je  LMsgForwardError

    // Call [receiver forward:sel :margs]
    subl    $8, %esp        // 16-byte align the stack
    leal    (self+4)(%ebp), %ecx
    pushl   %ecx            // &margs
    pushl   %eax            // sel
    movl    _FwdSel-L__objc_msgForward$pic_base(%edx),%ecx
    pushl   %ecx            // forward::
    pushl   (self+4)(%ebp)      // receiver
    
    call    objc_msgSend
    
    movl    %ebp, %esp
    popl    %ebp
    ret

LMsgForwardError:
    // Call __objc_error(receiver, "unknown selector %s %s", "forward::", forwardedSel)
    subl    $8, %esp        // 16-byte align the stack
    pushl   (selector+4+4)(%ebp)    // the forwarded selector
    movl    _FwdSel-L__objc_msgForward$pic_base(%edx),%eax
    pushl   %eax
    leal    LUnkSelStr-L__objc_msgForward$pic_base(%edx),%eax
    pushl   %eax
    pushl   (self+4)(%ebp)
    call    __objc_error    // never returns

    END_ENTRY   _objc_msgForward


    ENTRY   _objc_msgForward_stret
    // Struct return version

    // Get PIC base into %edx
    call    L__objc_msgForwardStret$pic_base
L__objc_msgForwardStret$pic_base:
    popl    %edx

    // Call user handler, if any
    movl    _objc_forward_stret_handler-L__objc_msgForwardStret$pic_base(%edx), %ecx
    testl   %ecx, %ecx      // if not NULL
    je  1f          //   skip to default handler
    jmp *%ecx           // call _objc_forward_stret_handler
1:  
    // No user handler
    // Push stack frame
    pushl   %ebp
    movl    %esp, %ebp

    // Die if forwarding "forward::"
    movl    (selector_stret+4)(%ebp), %eax
    movl    _FwdSel-L__objc_msgForwardStret$pic_base(%edx), %ecx
    cmpl    %ecx, %eax
    je  LMsgForwardStretError

    // Call [receiver forward:sel :margs]
    subl    $8, %esp        // 16-byte align the stack
    leal    (self_stret+4)(%ebp), %ecx
    pushl   %ecx            // &margs
    pushl   %eax            // sel
    movl    _FwdSel-L__objc_msgForwardStret$pic_base(%edx),%ecx
    pushl   %ecx            // forward::
    pushl   (self_stret+4)(%ebp)    // receiver
    
    call    objc_msgSend
    
    movl    %ebp, %esp
    popl    %ebp
    ret $4          // pop struct return address (#2995932)

LMsgForwardStretError:
    // Call __objc_error(receiver, "unknown selector %s %s", "forward::", forwardedSelector)
    subl    $12, %esp       // 16-byte align the stack
    leal    _FwdSel-L__objc_msgForwardStret$pic_base(%edx),%eax
    pushl   %eax
    leal    LUnkSelStr-L__objc_msgForwardStret$pic_base(%edx),%eax
    pushl   %eax
    pushl   (self_stret+4)(%ebp)
    call    __objc_error    // never returns

    END_ENTRY   _objc_msgForward_stret

    ENTRY objc_msgSend_debug
    jmp objc_msgSend
    END_ENTRY objc_msgSend_debug

    ENTRY objc_msgSendSuper2_debug
    jmp objc_msgSendSuper2
    END_ENTRY objc_msgSendSuper2_debug

    ENTRY objc_msgSend_stret_debug
    jmp objc_msgSend_stret
    END_ENTRY objc_msgSend_stret_debug

    ENTRY objc_msgSendSuper2_stret_debug
    jmp objc_msgSendSuper2_stret
    END_ENTRY objc_msgSendSuper2_stret_debug

    ENTRY objc_msgSend_fpret_debug
    jmp objc_msgSend_fpret
    END_ENTRY objc_msgSend_fpret_debug

    ENTRY objc_msgSend_noarg
    jmp objc_msgSend
    END_ENTRY objc_msgSend_noarg

    ENTRY method_invoke

    movl    selector(%esp), %ecx
    movl    method_name(%ecx), %edx
    movl    method_imp(%ecx), %eax
    movl    %edx, selector(%esp)
    jmp *%eax
    
    END_ENTRY method_invoke


    ENTRY method_invoke_stret

    movl    selector_stret(%esp), %ecx
    movl    method_name(%ecx), %edx
    movl    method_imp(%ecx), %eax
    movl    %edx, selector_stret(%esp)
    jmp *%eax
    
    END_ENTRY method_invoke_stret

    
    STATIC_ENTRY _objc_ignored_method
    
    movl    self(%esp), %eax
    ret
    
    END_ENTRY _objc_ignored_method
    
#endif
