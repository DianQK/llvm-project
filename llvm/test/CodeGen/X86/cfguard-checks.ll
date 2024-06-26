; RUN: llc < %s -mtriple=i686-pc-windows-msvc | FileCheck %s -check-prefix=X86
; RUN: llc < %s -mtriple=x86_64-pc-windows-msvc | FileCheck %s -check-prefixes=X64,X64_MSVC
; RUN: llc < %s -mtriple=i686-w64-windows-gnu | FileCheck %s -check-prefixes=X86,X86_MINGW
; RUN: llc < %s -mtriple=x86_64-w64-windows-gnu | FileCheck %s -check-prefixes=X64,X64_MINGW
; Control Flow Guard is currently only available on Windows

; Test that Control Flow Guard checks are correctly added when required.


declare i32 @target_func()


; Test that Control Flow Guard checks are not added on calls with the "guard_nocf" attribute.
define i32 @func_guard_nocf() {
entry:
  %func_ptr = alloca ptr, align 8
  store ptr @target_func, ptr %func_ptr, align 8
  %0 = load ptr, ptr %func_ptr, align 8
  %1 = call i32 %0() #0
  ret i32 %1

  ; X86-LABEL: func_guard_nocf
  ; X86:         movl  $_target_func, %eax
  ; X86-NOT: __guard_check_icall_fptr
  ; X86:         calll *%eax

  ; X64-LABEL: func_guard_nocf
  ; X64:       leaq	target_func(%rip), %rax
  ; X64-NOT: __guard_dispatch_icall_fptr
  ; X64:       callq	*%rax
}
attributes #0 = { "guard_nocf" }


; Test that Control Flow Guard checks are added even at -O0.
; FIXME Ideally these checks should be added as a single call instruction, as in the optimized case.
define i32 @func_optnone_cf() #1 {
entry:
  %func_ptr = alloca ptr, align 8
  store ptr @target_func, ptr %func_ptr, align 8
  %0 = load ptr, ptr %func_ptr, align 8
  %1 = call i32 %0()
  ret i32 %1

  ; On i686, the call to __guard_check_icall_fptr should come immediately before the call to the target function.
  ; X86-LABEL: func_optnone_cf
  ; X86:         leal  _target_func, %eax
  ; X86:         movl  %eax, (%esp)
  ; X86:         movl  (%esp), %ecx
  ; X86:         calll *___guard_check_icall_fptr
  ; X86-NEXT:  calll *%ecx

  ; On x86_64, __guard_dispatch_icall_fptr tail calls the function, so there should be only one call instruction.
  ; X64-LABEL: func_optnone_cf
  ; X64:       leaq	target_func(%rip), %rax
  ; X64:       movq __guard_dispatch_icall_fptr(%rip), %rcx
  ; X64:       callq *%rcx
  ; X64-NOT:   callq
}
attributes #1 = { noinline optnone }


; Test that Control Flow Guard checks are correctly added in optimized code (common case).
define i32 @func_cf() {
entry:
  %func_ptr = alloca ptr, align 8
  store ptr @target_func, ptr %func_ptr, align 8
  %0 = load ptr, ptr %func_ptr, align 8
  %1 = call i32 %0()
  ret i32 %1

  ; On i686, the call to __guard_check_icall_fptr should come immediately before the call to the target function.
  ; X86-LABEL: func_cf
  ; X86:         movl  $_target_func, %esi
  ; X86:         movl  $_target_func, %ecx
  ; X86:         calll *___guard_check_icall_fptr
  ; X86-NEXT:  calll *%esi

  ; On x86_64, __guard_dispatch_icall_fptr tail calls the function, so there should be only one call instruction.
  ; X64-LABEL: func_cf
  ; X64:       leaq	target_func(%rip), %rax
  ; X64:       callq *__guard_dispatch_icall_fptr(%rip)
  ; X64-NOT:   callq
}


; Test that Control Flow Guard checks are correctly added on invoke instructions.
define i32 @func_cf_invoke() personality ptr @h {
entry:
  %0 = alloca i32, align 4
  %func_ptr = alloca ptr, align 8
  store ptr @target_func, ptr %func_ptr, align 8
  %1 = load ptr, ptr %func_ptr, align 8
  %2 = invoke i32 %1()
          to label %invoke.cont unwind label %lpad
invoke.cont:                                      ; preds = %entry
  ret i32 %2

lpad:                                             ; preds = %entry
  %tmp = landingpad { ptr, i32 }
          catch ptr null
  ret i32 -1

  ; On i686, the call to __guard_check_icall_fptr should come immediately before the call to the target function.
  ; X86-LABEL: func_cf_invoke
  ; X86:         movl  $_target_func, %esi
  ; X86:         movl  $_target_func, %ecx
  ; X86:         calll *___guard_check_icall_fptr
  ; X86_MINGW-NEXT: Ltmp0:
  ; X86-NEXT:  calll *%esi
  ; X86:       # %invoke.cont
  ; X86:       # %lpad

  ; On x86_64, __guard_dispatch_icall_fptr tail calls the function, so there should be only one call instruction.
  ; X64-LABEL: func_cf_invoke
  ; X64:       leaq	target_func(%rip), %rax
  ; X64:       callq *__guard_dispatch_icall_fptr(%rip)
  ; X64-NOT:   callq
  ; X64:       # %invoke.cont
  ; X64:       # %lpad
}

declare void @h()


; Test that Control Flow Guard preserves floating point arguments.
declare double @target_func_doubles(double, double, double, double)

define double @func_cf_doubles() {
entry:
  %func_ptr = alloca ptr, align 8
  store ptr @target_func_doubles, ptr %func_ptr, align 8
  %0 = load ptr, ptr %func_ptr, align 8
  %1 = call double %0(double 1.000000e+00, double 2.000000e+00, double 3.000000e+00, double 4.000000e+00)
  ret double %1

  ; On i686, the call to __guard_check_icall_fptr should come immediately before the call to the target function.
  ; X86-LABEL: func_cf_doubles
  ; X86:         movl  $_target_func_doubles, %esi
  ; X86:         movl  $_target_func_doubles, %ecx
  ; X86:         calll *___guard_check_icall_fptr
  ; X86:         calll *%esi


  ; On x86_64, __guard_dispatch_icall_fptr tail calls the function, so there should be only one call instruction.
  ; X64-LABEL: func_cf_doubles
  ; X64:       leaq	target_func_doubles(%rip), %rax
  ; X64_MSVC:  movsd __real@3ff0000000000000(%rip), %xmm0
  ; X64_MSVC:  movsd __real@4000000000000000(%rip), %xmm1
  ; X64_MSVC:  movsd __real@4008000000000000(%rip), %xmm2
  ; X64_MSVC:  movsd __real@4010000000000000(%rip), %xmm3
  ; X64_MINGW: movsd .LCPI4_0(%rip), %xmm0
  ; X64_MINGW: movsd .LCPI4_1(%rip), %xmm1
  ; X64_MINGW: movsd .LCPI4_2(%rip), %xmm2
  ; X64_MINGW: movsd .LCPI4_3(%rip), %xmm3
  ; X64:       callq *__guard_dispatch_icall_fptr(%rip)
  ; X64-NOT:   callq

}


; Test that Control Flow Guard checks are correctly added for tail calls.
define i32 @func_cf_tail() {
entry:
  %func_ptr = alloca ptr, align 8
  store ptr @target_func, ptr %func_ptr, align 8
  %0 = load ptr, ptr %func_ptr, align 8
  %1 = musttail call i32 %0()
  ret i32 %1

  ; On i686, the call to __guard_check_icall_fptr should come immediately before the call to the target function.
  ; X86-LABEL: func_cf_tail
  ; X86:         movl  $_target_func, %ecx
  ; X86:         calll *___guard_check_icall_fptr
  ; X86:         movl $_target_func, %eax
  ; X86:         jmpl	*%eax                  # TAILCALL
  ; X86-NOT:   calll

  ; X64-LABEL: func_cf_tail
  ; X64:       leaq	target_func(%rip), %rax
  ; X64:       rex64 jmpq *__guard_dispatch_icall_fptr(%rip)         # TAILCALL
  ; X64-NOT:   callq
}


%struct.Foo = type { ptr }

; Test that Control Flow Guard checks are correctly added for variadic musttail
; calls. These are used for MS C++ ABI virtual member pointer thunks.
; PR44049
define i32 @vmptr_thunk(ptr inreg %p) {
entry:
  %vptr = load ptr, ptr %p
  %slot = getelementptr inbounds ptr, ptr %vptr, i32 1
  %vmethod = load ptr, ptr %slot
  %rv = musttail call i32 %vmethod(ptr inreg %p)
  ret i32 %rv

  ; On i686, the call to __guard_check_icall_fptr should come immediately before the call to the target function.
  ; X86-LABEL: _vmptr_thunk:
  ; X86:       movl %eax, %esi
  ; X86:       movl (%eax), %eax
  ; X86:       movl 4(%eax), %ecx
  ; X86:       calll *___guard_check_icall_fptr
  ; X86:       movl %esi, %eax
  ; X86:       jmpl       *%ecx                  # TAILCALL
  ; X86-NOT:   calll

  ; Use NEXT here because we previously had an extra instruction in this sequence.
  ; X64-LABEL: vmptr_thunk:
  ; X64:            movq (%rcx), %rax
  ; X64-NEXT:       movq 8(%rax), %rax
  ; X64-NEXT:       movq __guard_dispatch_icall_fptr(%rip), %rdx
  ; X64-NEXT:       rex64 jmpq *%rdx            # TAILCALL
  ; X64-NOT:   callq
}

; Test that longjmp targets have public labels and are included in the .gljmp section.
%struct._SETJMP_FLOAT128 = type { [2 x i64] }
@buf1 = internal global [16 x %struct._SETJMP_FLOAT128] zeroinitializer, align 16

define i32 @func_cf_setjmp() {
  %1 = alloca i32, align 4
  %2 = alloca i32, align 4
  store i32 0, ptr %1, align 4
  store i32 -1, ptr %2, align 4
  %3 = call ptr @llvm.frameaddress(i32 0)
  %4 = call i32 @_setjmp(ptr @buf1, ptr %3) #2

  ; X86-LABEL: func_cf_setjmp
  ; X86:       calll __setjmp
  ; X86-NEXT:  $cfgsj_func_cf_setjmp0:

  ; X64-LABEL: func_cf_setjmp
  ; X64:       callq _setjmp
  ; X64-NEXT:  $cfgsj_func_cf_setjmp0:

  %5 = call ptr @llvm.frameaddress(i32 0)
  %6 = call i32 @_setjmp(ptr @buf1, ptr %5) #2

  ; X86:       calll __setjmp
  ; X86-NEXT:  $cfgsj_func_cf_setjmp1:

  ; X64:       callq _setjmp
  ; X64-NEXT:  $cfgsj_func_cf_setjmp1:

  store i32 1, ptr %2, align 4
  %7 = load i32, ptr %2, align 4
  ret i32 %7

  ; X86:       .section .gljmp$y,"dr"
  ; X86-NEXT:  .symidx $cfgsj_func_cf_setjmp0
  ; X86-NEXT:  .symidx $cfgsj_func_cf_setjmp1

  ; X64:       .section .gljmp$y,"dr"
  ; X64-NEXT:  .symidx $cfgsj_func_cf_setjmp0
  ; X64-NEXT:  .symidx $cfgsj_func_cf_setjmp1
}

declare ptr @llvm.frameaddress(i32)

; Function Attrs: returns_twice
declare dso_local i32 @_setjmp(ptr, ptr) #2

attributes #2 = { returns_twice }


!llvm.module.flags = !{!0}
!0 = !{i32 2, !"cfguard", i32 2}
