; s3vbefix main code - wbcbz7 xx.xx.0x7e0-xx.xx.0x7e6
; blah-blah, read readme.txt and github repo docs for MOAR bullshit! :)

; use FASM to compile

format binary

; VESA info blocks structures

struc VbeInfoBlock {
    .VbeSignature        dd   ?           ; VBE Signature
    .VbeVersion          dw   ?           ; VBE Version
    .OemStringPtr        dd   ?           ; Pointer to OEM String
    .Capabilities        dd   ?           ; Capabilities of graphics cont.
    .VideoModePtr        dd   ?           ; Pointer to Video Mode List
    .TotalMemory         dw   ?           ; Number of 64kb memory blocks
    
    ; Added for VBE 2.0
    .OemSoftwareRev      dw   ?           ; VBE implementation Software revision
    .OemVendorNamePtr    dd   ?           ; Pointer to Vendor Name String
    .OemProductNamePtr   dd   ?           ; Pointer to Product Name String
    .OemProductRevPtr    dd   ?           ; Pointer to Product Revision String
    .Reserved            db   222 dup (?) ; Reserved for VBE implementation
                                          ; scratch area
    .OemData             db   256 dup (?) ; Data Area for OEM Strings
}
    
struc ModeInfoBlock {
     ; Mandatory information for all VBE revisions
    .ModeAttributes      dw ?      ; mode attributes
    .WinAAttributes      db ?      ; window A attributes
    .WinBAttributes      db ?      ; window B attributes
    .WinGranularity      dw ?      ; window granularity
    .WinSize             dw ?      ; window size
    .WinASegment         dw ?      ; window A start segment
    .WinBSegment         dw ?      ; window B start segment
    .WinFuncPtr          dd ?      ; pointer to window function
    .BytesPerScanLine    dw ?      ; bytes per scan line

     ; Mandatory information for VBE 1.2 and above
    .XResolution         dw ?      ; horizontal resolution in pixels or chars
    .YResolution         dw ?      ; vertical resolution in pixels or chars
    .XCharSize           db ?      ; character cell width in pixels
    .YCharSize           db ?      ; character cell height in pixels
    .NumberOfPlanes      db ?      ; number of memory planes
    .BitsPerPixel        db ?      ; bits per pixel
    .NumberOfBanks       db ?      ; number of banks
    .MemoryModel         db ?      ; memory model type
    .BankSize            db ?      ; bank size in KB
    .NumberOfImagePages  db ?      ; number of images
    .Reserved            db ?      ; reserved for page function

     ; Direct Color fields (required for direct/6 and YUV/7 memory models)
    .RedMaskSize         db ?      ; size of direct color red mask in bits
    .RedFieldPosition    db ?      ; bit position of lsb of red mask
    .GreenMaskSize       db ?      ; size of direct color green mask in bits
    .GreenFieldPosition  db ?      ; bit position of lsb of green mask
    .BlueMaskSize        db ?      ; size of direct color blue mask in bits
    .BlueFieldPosition   db ?      ; bit position of lsb of blue mask
    .RsvdMaskSize        db ?      ; size of direct color reserved mask in bits
    .RsvdFieldPosition   db ?      ; bit position of lsb of reserved mask
    .DirectColorModeInfo db ?      ; direct color mode attributes

     ; Mandatory information for VBE 2.0 and above
    .PhysBasePtr         dd ?      ; physical address for flat frame buffer
    .OffScreenMemOffset  dd ?      ; pointer to start of off screen memory
    .OffScreenMemSize    dw ?      ; amount of off screen memory in 1k units
    .Reserved2           db 206 dup (?)  ; remainder of ModeInfoBlock
}

virtual at 0
    ModeInfoBlock ModeInfoBlock
end virtual

virtual at 0
    VbeInfoBlock VbeInfoBlock
end virtual

resident_start      equ     0x40     ; resident start offset
resident_id         equ     "fK"     ; resident id word
resident_ver        equ     0x0060   ; resident version, in 0x1234 - 12.3.4 format

check_func          equ     0xCE00   ; installation check function number
check_in            equ     "ne"     ; installation check key input  word
check_out           equ     "ko"     ; installation check key output word 
; pretty nice (and simple) choice, eh? ^.^

; hacky stuff
; pointer to temporary VESA mode table
modeinfo_temp   equ     vbeinfo_transient + 512
modetab_temp    equ     vbeinfo_transient + 512 + 256

; patch bitfields
PATCH_BIT_MEMSIZE   equ     (1 shl 0)
PATCH_BIT_SDS       equ     (1 shl 1)
PATCH_BIT_BOOSTER   equ     (1 shl 2)
PATCH_BIT_CAPS      equ     (1 shl 3)
PATCH_BIT_GAMMA     equ     (1 shl 4)
PATCH_BIT_VBEVER    equ     (1 shl 5)
PATCH_BIT_PAGELIMIT equ     (1 shl 6)
PATCH_BIT_MODECAPS  equ     (1 shl 7)
; patch at install
PATCH_BIT_INT6D     equ     (1 shl 13)
PATCH_BIT_PALPROC   equ     (1 shl 14)
PATCH_BIT_320X400   equ     (1 shl 15)

; install check bitfields
INSTALL_BIT_INT10       equ (1 shl 0)
INSTALL_BIT_INT10LAST   equ (1 shl 1)
INSTALL_BIT_INT6D       equ (1 shl 6)
INSTALL_BIT_INT6DLAST   equ (1 shl 7)

; ---------------------------------------- START OF CODE ----------------------------

start:
            org     0x100
            jmp     init
            nop
        
            ; start of resident part
realint10:
            org     resident_start
int10:
newint10id  dw      resident_id
newint10ver dw      resident_ver
var_ofs     dw      add_vars    ; additional vars offset
inTSR       dw      0           ; inner call check flag
            ; resident entry point
newint10:
            ; check for inner call
            cmp     byte [cs:inTSR], 0
            jz      @first_call
            ; here is a trick - since fasm doesn't support org as "move assembly
            ; pointer" we need to build our instruction "by hand"
            db      0xEA    ; jmp dword ?:?
int10ofs    dw      ?
int10seg    dw      ?

@first_call:
            ; VESA function 0x4F05 shortcut
            cmp     ax,0x4F05
            jnz     @f
            push    cs
            call    bankproc
            iret
@@:

            push    ds
            push    si
            ; set TSR segment as data segment
            push    cs
            pop     ds
            ; save original ax\bx\cx\dx
            mov     [saveAX], ax
            mov     [saveBX], bx
            mov     [saveCX], cx
            
            ; set inTSR flag
            inc     [inTSR]
            
            ; check for calling function and doing some conditional branch magic
            ; should be used for patching arguments before INT10h call
            
            cmp     ax, check_func  ; installaion check invoked
            jnz     .check_vbe
            cmp     dx, check_in
            jnz     .check_vbe
            ; installation check
            ; input:  ax    = check_func (see above)
            ;         dx    = check_in
            ; output: ax    = 0x0000
            ;         dx    = check_out
            ;         es:bx = resident entry point
            push    ds
            pop     es
            xor     ax, ax
            mov     dx, check_out
            mov     bx, newint10
            jmp     done_2
            
.check_vbe: 
            cmp     ah, 0x4F
            jnz     @invoke

            ; check for VESA calls to patch mode number
            cmp     al, 0x1     ; Function 01h  - Get VBE Mode Information
            jnz     .f2
            ; replace mode number
            xchg    bx, cx
            call    patch_mode
            mov     [patchedmode], bx
            xchg    bx, cx
            
.f2:
            cmp     al, 0x2     ; Function 02h  - Set VBE Mode
            jnz     .f7

            ; replace mode number
            call    patch_mode
            mov     [patchedmode], bx

            ; if LFB requested - set banked mode, then if success, set LFB
            ; (because booster can crash the system otherwise and fake LFB will not work)
            test    bh, 0x40
            jz      @invoke             ; banked
            ; do it!
            push    ax
            push    bx
            and     bh, 0xBF            ; preserve clear bits
            pushf
            call    dword [int10ofs]    ; call original handler
            test    ah, ah              ; check return status
            jz      .success
            add     sp, 4               ; failure - don't bother with LFB mode set, return error
            jmp     done_2
.success:
            pop     bx
            pop     ax
            or      bh, 0x80            ; do LFB + noclear
            
.f7:
            cmp     al, 0x7     ; Function 07h - Set/Get Display Start
            jnz     @f9
            ; clear "wait for retrace" flag
            or      bl, 0
sds_or      =       $-1
            and     bl, 0xFF
sds_and     =       $-1

@f9:
            cmp     al, 0x9     ; Function 09h - Set/Get Palette        ; 0x3C 0x09
f9_jmp:                         ; 0xEB -> 0x75 - enable pal procedure
            jmp     @invoke
            jmp     palproc
            
@invoke:
            ; call original handler
            pushf
            call    dword [int10ofs]

            push    ax
            push    bx
            push    cx
            push    dx
            
            ; and once again this trick (fffuck!)
            db      0xB8    ; mov ax, ?
saveAX      dw      ?
            db      0xBB    ; mov bx, ?
saveBX      dw      ?
            db      0xB9    ; mov cx, ?
saveCX      dw      ?
            db      0xBA    ; mov dx, ?
patchedmode dw      ?
            
            ; init stack frame
            push    bp
            mov     bp, sp
            ; stack frame:   sp   - old_bp; 
            ; sp+2 - out_dx; sp+4 - out_cx;
            ; sp+6 - out_bx; sp+8 - out_ax;

            ; check for VGA BIOS calls
            cmp     ah, 0
            jz      fix_fetch
            
            ; check for VESA calls
            cmp     ah, 0x4F
            jnz     done_iret
            
            cmp     al, 0x0     ; Function 00h - Return VBE Controller Information
            jz      patch_vbeinfo
            cmp     al, 0x1     ; Function 01h - Get VBE Mode Information
            jz      patch_modeinfo
            cmp     al, 0x2     ; Function 02h - Set VBE Mode
            jz      patch_modeset
            cmp     al, 0x6     ; Function 06h - Set/Get Logical Scan Line Length
            jz      patch_setscanlinelen

done_iret:
            ; all done, close stack frame, reset inTSR flag and quit from ISR
            pop     bp
            pop     dx
            pop     cx
            pop     bx
            pop     ax
done_2:
            dec     [inTSR]
            pop     si
            pop     ds
            iret

; PATCHERS!1!11 YARRRRRRRRRR!1!!
; input:  AX, BX, CX - parameters; DX - patched VESA mode number (for VESA patchers)
;         DS - TSR code segment; other regs - passed from previous INT10h handler
; output: none (not supported yet)
; what you can change: AX, BX, CX, DX; others - don't forget about push\pop!

unlock_extensions:
            ; unlock S3 extensions
            ; input: dx = 0x3D4
            mov     ax, 0x4838
            out     dx, ax
            mov     ax, 0xA539
            out     dx, ax
            ret
lock_extensions:
            ; lock S3 extensions
            ; input: dx = 0x3D4
            mov     ax, 0x0038
            out     dx, ax
            mov     ax, 0x0039
            out     dx, ax
            ret
            
; read-modify-write proc
; input:  dx - index port; al - index; bh - AND mask; bl - OR mask
; output: al - resulting value
rmw:
            out     dx, al
            inc     dx
            in      al, dx
            and     al, bh
            or      al, bl
            out     dx, al
            dec     dx
            ret
            
            ; ----------------------
            ; VGA function 0x0 - fix primary stream FIFO fetch bug
fix_fetch:
            mov     dx, 0x3D4
            
            call    unlock_extensions
            
            mov     al, 0x90
            db      0xBB    ; mov bx, ?
fetch_mask  dw      0xFF00
            call    rmw
            
            call    lock_extensions
            
            jmp     done_iret
            
            ; ----------------------
            ; VESA function 0x0 patch
patch_vbeinfo:

            ; patch VBE version if requested
            mov     ax, [vbever]
            test    ax, ax
            jz      .vbever_skip
            mov     [es:di + VbeInfoBlock.VbeVersion], ax
.vbever_skip:

            ; patch mode table if requested
            mov     ax, [modetabptr]
            test    ax, ax
            jz      .modetab_skip

            mov     word [es:di + VbeInfoBlock.VideoModePtr + 2], cs
            mov     word [es:di + VbeInfoBlock.VideoModePtr    ], ax
.modetab_skip:

            ; patch capabilities
            and     byte [es:di + VbeInfoBlock.Capabilities], 0xFF
cap_and     =       $-1

            ; override memory size
            mov     ax, [fakememsize] 
            test    ax, ax
            jz      .memsize_skip
            
            mov    [es:di + VbeInfoBlock.TotalMemory], ax
        
.memsize_skip:
            jmp     done_iret
            
            ; ----------------------
            ; VESA function 0x1 patch
patch_modeinfo:
            mov     word [es:di + ModeInfoBlock.WinFuncPtr + 2], cs
            mov     word [es:di + ModeInfoBlock.WinFuncPtr    ], bankproc

            ; patch mode capabilities
            and     byte [es:di + ModeInfoBlock.ModeAttributes], 0xFF
modecaps_and    =   $-1
            or      byte [es:di + ModeInfoBlock.ModeAttributes], 0
modecaps_or     =   $-1

            ; set LFB address
            xor     ax, ax
            mov     word [es:di + ModeInfoBlock.PhysBasePtr], ax
            mov     ax, [lfb_addr]
            mov     word [es:di + ModeInfoBlock.PhysBasePtr + 2], ax

            ; check for modenum is patched
            cmp     cx, dx
            jz      .gamma_chk
            
            ; double the pixel height
            shl     word [es:di + ModeInfoBlock.YResolution], 1
            
            ; divide page number by two
            mov     al, [es:di + ModeInfoBlock.NumberOfImagePages]
            inc     al
            shr     al, 1
            dec     al
            mov     [es:di + ModeInfoBlock.NumberOfImagePages], al
            
.gamma_chk:
            ; check for gamma correction override
            cmp     byte [gamma_en], 0 
            jz      .skip_gamma

            ; check if direct color mode
            cmp     byte [es:di + ModeInfoBlock.MemoryModel], 6
            jnz     .skip_gamma

            ; indicate gamma correction support + reserved bits are unused
            mov     byte [es:di + ModeInfoBlock.DirectColorModeInfo], 3

.skip_gamma:

            ; get page count
            xor     ax, ax
            mov     al, [es:di + ModeInfoBlock.NumberOfImagePages]
            inc     ax

.memsize_check:
            ; check for overriden memsize
            mov     bx, [fakememsize] 
            test    bx, bx
            jz      .pagecount_check
            
            mov     ax,  [es:di + ModeInfoBlock.BytesPerScanLine]
            mul     word [es:di + ModeInfoBlock.YResolution]        ; dx:ax - page size in bytes
            add     ax, 0xFFFF
            adc     dx, 0           ; ceil(dx:ax)
            
            mov     cx, dx          ; cx    - pagesize in 64kb blocks (inaccurate but who cares? :)
            xor     dx, dx
            mov     ax, bx          ; dx:ax - mem size in 64kb blocks
            div     cx              ; ax    - number of pages
            
            test    ax, ax          ; numofpages = 0?
            jz      .not_avail      ; mode is not available in fact
            
.pagecount_check:
            ; check for pagenum >= limit
            cmp     ax, [pagelimit]
            jb      .pagecount_ok
            ; clip it
            mov     ax, [pagelimit]
.pagecount_ok:
            ; if avail - set new pages value
            dec     ax
            mov     [es:di + ModeInfoBlock.NumberOfImagePages], al
            jmp     done_iret
            
.not_avail:
            ; set "not supported" flag
            and     word [es:di + ModeInfoBlock.ModeAttributes], 0xFFFE
            
            ; done
            jmp     done_iret
            
            ; ----------------------
            ; VESA function 0x2 patch
patch_modeset:
            ; check for modenum < 0x100
            cmp     bx, 0x100
            jb      fix_fetch
            
            ; check for modenum is patched (== 320x400/480 mode)
            cmp     bx, dx
            jz      skip_doublescan_dis
            
            ; set scanline height = 1
            push    bx
            mov     dx, 0x3D4
            mov     al, 0x9
            mov     bx, 0x6000
            call    rmw
            pop     bx
            
skip_doublescan_dis:
            mov     dx, 0x3D4
            call    unlock_extensions

            ; restore LFB settings if LFB mode requested
            test    bh, 0x40
            jnz     booster_lfb

            ; test for booster
            db      0xB0                ; mov al, ?
booster_en  db      0                   ; booster flag (nonzero - enabled)
            test    al, al
            jz      booster_done        ; booster not enabled

            ; boost banked modes
            ; bank switching is enabled already, we need to just enable
            ; linear addressing via 64k window and set new linear window address
            ; сперто из SVGATRIX.TXT и перепилено чуток
            
            ; set 64k window size and disable linear addressing
            mov     al, 0x58
            mov     bx, 0xEC00
            call    rmw
            
            ; set 0xA0000 as linear window address
            xor     ax, ax
            mov     al, 0x59
            out     dx, ax
            inc     ax
            mov     ah, 0x0A
            out     dx, ax
            
            ; enable linear addressing (костылек :)
            mov     al, 0x58
            mov     bx, 0xFF10
            call    rmw
            
            jmp     booster_done

booster_lfb:
            ; restore linear window address and size
            mov     al, 0x58
            mov     bx, 0xEC00
            call    rmw
            
            mov     bx, [lfb_addr]
            mov     al, 0x59
            mov     ah, bh
            out     dx, ax
            inc     ax
            mov     ah, bl
            out     dx, ax
            
            mov     ah, [lfb_size]
            mov     al, 0x58
            or      ah, 0x10
            out     dx, ax
            
            ; fake mode setting success if "force lfb" enabled
            ; as you may have noticed, before INT10 call, I set first banked mode, and then try to set LFB
            ; if the banked mode set call succeeds, the card is already initialized for the requested VESA
            ; mode, so it should technically work.
            cmp     byte [modecaps_or], 0x80
            jnz     booster_done
            mov     word [ss:bp + 8], 0x004F
booster_done:

            ; check if enable gamma correction
            db      0xB0        ; mov al, ?
gamma_en    db      0x00
            test    al, al
            jz      gamma_en_skip

            ; check if direct color mode
            mov     al, 0x67
            out     dx, al
            inc     dx
            in      al, dx
            dec     dx
            and     al, 0xE0
            jz      gamma_en_skip

            ; enable gamma correction
            mov     dx, 0x3C4
            mov     ax, 0x0608
            out     dx, ax      ; unlock sequencer extended registers

            mov     al, 0x1B
            mov     bx, 0xFF18  ; 24bit CLUT, gamma correction enabled
            call    rmw

            ; upload identity gamma ramp
            xor     ax, ax
            mov     dx, 0x3C8
            out     dx, al
            inc     dx
            mov     cx, 256
.loop:
            out     dx, al
            out     dx, al
            out     dx, al
            inc     al
            loop    .loop

            ; lock sequencer extended registers
            mov     dx, 0x3C4
            mov     ax, 0x0008
            out     dx, ax

gamma_en_skip:
            mov     dx, 0x3D4
            call    lock_extensions
            jmp     done_iret

            ; ----------------------------------
            ; VESA function 0x5 new routine
bankproc:
            push    cx
            
            test    bl, bl              ; check for selected window
            jnz     .fail               ; window B is not supported

            mov     cx, dx
            mov     dx, 0x3D4
            call    unlock_extensions
            
            ; check for banking enabled
            mov     al, 0x31
            out     dx, al
            inc     dx
            in      al, dx
            dec     dx
            test    al, 1
            jz      .lfb       ; not supported in VGA or LFB modes
            
            mov     al, 0x6A
            ; check for get/set bank
            test    bh, bh
            jnz     .get
            
            ; set new window pos
            mov     ah, cl
            out     dx, ax
            call    lock_extensions
            jmp     .ok
            
.get:
            out     dx, al
            inc     dx
            in      al, dx
            mov     cl, al      ; FIX: preserve read bank value across lock_extensions
            dec     dx
            call    lock_extensions
            
.ok:
            xor     dx, dx      ; FIX: return current bank in DX - fix chasm: the rift runtime error 216
            mov     dl, cl
            mov     ax, 0x004F
            jmp     .done
.fail:
            mov     ax, 0x014F
            jmp     .done
.lfb:
            mov     ax, 0x034F
.done:
            pop     cx
            retf

            ; ----------------------------------
            ; VESA function 0x6 patcher
            ; just recalculate maximum number of scanlines

patch_setscanlinelen:
            ; check for overriden memsize
            mov     dx, [fakememsize] 
            test    dx, dx
            jz      done_iret
            
            xor     ax, ax
            div     word [ss:bp+6]  ; out_bx = new bytes per scanline
            mov     [ss:bp+2], ax   ; ax     = new max number of scanlines
            
            jmp     done_iret
            
; ----------------------------------
; replace current VESA mode number with other (used for mode info block patching)
; input:  BX - VESA mode number; DS:SI - address of replacement table
; output: BX - patched mode number; SI destroyed          
patch_mode:
            mov     si, [modexlatptr]
            test    si, si
            jz      .ret

            push    ax
            push    bx
            and     bx, 0x03FF
.loop:
            lodsw
            cmp     ax, 0xFFFF  ; check for 0xFF terminator
            jz      .done
            cmp     bx, ax      ; check for matching value
            jz      .yep
            add     si, 2       ; else adjust table
            jmp     .loop
.yep:       lodsw
            mov     bx, ax
.done:      pop     ax
            and     ax, not 0x03FF
            or      bx, ax
            pop     ax
.ret:
            ret                  
            
add_vars:
; additional vars
fakememsize dw      0 ; fake memory size (set via /Mx, 0 - BIOS default)
vbever      dw      0 ; VBE version overriden
pagelimit   dw    127 ; video page limit
lfb_size    db      0 ; LFB size (0x3d4 index 0x58)
lfb_addr    dw      0 ; LFB address bits 16-31 (saved for booster)
modexlatptr dw      0 ; mode number patch table offset, 0 if absent
modetabptr  dw      0 ; VESA mode table offset,         0 if absent
            
            ; ----------------------------------
            ; VESA function 0x09 new routine - used for VBE 2.x/LFB "emulation", optional
            ; Input:    AX   = 4F09h   VBE Load/Unload Palette Data
            ;           BL   = 00h          Set Palette Data
            ;                = 01h          Get Palette Data
            ;                = 02h          Set Secondary Palette Data
            ;                = 03h          Get Secondary Palette Data
            ;                = 80h          Set Palette Data during Vertical Retrace
            ;                               with Blank Bit on
            ;           CX   =         Number of palette registers to update
            ;           DX   =         First palette register to update
            ;           ES:DI=         Table of palette values
            ; Output:   AX   =         VBE Return Status
palproc:
            ; allow BL = 00,01,80,81 only
            test    bl, 0x7E
            jnz     .fail

            push    cx
            push    dx
            push    si
            mov     ah, dl      ; save first palette index

            ; bail out if CX==0
            jcxz    .ok

            ; check if vsync requested
            test    bl, 0x80
            mov     dx, 0x3DA
            jz      .skip_vsync
            
            ; account for applications using this functions for vsync
@@:
            in      al, dx
            test    al, 8
            jnz     @B
@@:
            in      al, dx
            test    al, 8
            jz      @B

.skip_vsync:
            mov     al, ah  ; restore saved start index
            test    bl, 1
            jnz     .read

            ; write palette
            mov     dl, 0xC8
            out     dx, al
            inc     dl
@@:
            mov     al, [es:di + 2]
            out     dx, al
            mov     al, [es:di + 1]
            out     dx, al
            mov     al, [es:di + 0]
            out     dx, al
            add     di, 4
            loop    @b
            jmp     .ok

.read:
            ; read palette
            mov     dl, 0xC7
            out     dx, al
            add     dl, 2
@@:
            in      al, dx
            mov     al, [es:di + 2]
            in      al, dx
            mov     al, [es:di + 1]
            in      al, dx
            mov     al, [es:di + 0]
            add     di, 4
            loop    @b

.ok:
            pop     di
            pop     dx
            pop     cx
            mov     ax, 0x004F
            jmp     done_2
.fail:
            mov     ax, 0x014F
            jmp     done_2

; mode list and mode patch table follow here until TSR end

newint10end:

;--------------------------------------------------------------------------------------------------
; START OF TRANSIENT PART
                org     realint10 + (newint10end - int10)

; ---------------------
; strings
info_str        db      "S3 VBE fix TSR v.0.6.0 - by wbcbz7 o2.1o.2o22"
dash_str        db      " - $"                                      ; small trick here
already_str     db      "already $"
installed_str   db      "installed",13,10,13,10,"$"
reset_str       db      "reset",13,10,13,10,"$"
released_str    db      "released",13,10,"$"
zap_str         db      8,8,8,"   ",13,10,"$"
relfail_str     db      "unable to release - $"
notlast_str     db      "not last in chain",13,10,"$"
int6d_str       db      "int6d hooked",13,10,"$"
notinst_str     db      "not installed$"
nots3_str       db      "can't find S3 graphics card",13,10,"$"
help_str        db      "help",13,10,13,10
                db      "/M[x]   - override memory size in 64kb units (/M16 - 1 MB, /M0 - by BIOS)",13,10
                db      "/P[x]   - limit max. video page count (/P1 - max. 1 page, /P0 - default)",13,10
                db      "/V[x]   - force VBE version (/V102 - 1.2, /V200 - 2.0)",13,10
                db      "/Q      - replace VBE Get/Set Palette (0x4F09) (until release!)",13,10
                db      "/X      - add 320x400 and 320x480 VESA modes   (until release!)",13,10
                db      "/L[x]   - linear frame buffer control",13,10
                db      "          (/L0 - normal, /L1 - off, /L2 - force on)",13,10
                db      "/S[x]   - 'set display start' control",13,10
                db      "          (/S0 - normal, /S1 - force wait for retrace, /S2 - force no wait)",13,10
                db      "/B[+/-] - enable/disable banked VESA modes booster (not Savage)",13,10
                db      "/I      - hook INT6D (disables release!)",13,10
                db      "/R, /U  - release from memory",13,10
                db      13,10
                db      "S3 Trio3D/Savage only:",13,10
                db      "/D[x]   - force RAMDAC CLUT width (/D8 - normal, /D6 - force 6 bit)",13,10
                db      "/G[+/-] - enable Hi/TrueColor gamma correction",13,10
                db      "$"

; --------------------
; entrypoint
init:
                push    cs
                pop     ds
                xor     bp, bp              ; will be used later
                
                mov     ah, 9
                mov     dx, info_str
                int     0x21
                
                ; check if INT6D hooked
                mov     al, 0x6D
                call    install_check
                shl     bp, 6

                ; check if INT10 hooked
                mov     al, 0x10
                call    install_check

parse:
                ; parse command line
                mov     si, 80h
                lodsb
                test    al, al
                jz      no_params           ; empty commandline
                
                movzx   cx, al
@parse_loop:
                lodsb
                cmp     al, "?"             ; help
                jz      help
                cmp     al, 40h             ; spaces, slashes and other stuff
                jb      @gottaloop
                cmp     al, 5Fh             ; a-z
                jb      @skip_upcase
                sub     al, 20h             ; upcase these symbols
@skip_upcase:
                cmp     al, "U"             ; release
                jz      release
                cmp     al, "R"             ; release
                jz      release
                cmp     al, "B"             ; booster enable\disable
                jz      booster_parse
                cmp     al, "V"             ; VBE version override
                jz      vbever_parse
                cmp     al, "X"             ; add 320x400/480 modes?
                jz      newmodes_parse
                cmp     al, "P"             ; page limit override
                jz      pagelimit_parse
                cmp     al, "G"             ; gamma correction enable\disable
                jz      gamma_parse
                cmp     al, "L"             ; LFB control
                jz      lfb_parse
                cmp     al, "Q"             ; VBE Get/Set Palette (0x4F09) override
                jz      palproc_parse
                cmp     al, "D"             ; force RAMDAC width
                jz      dacwidth_parse
                cmp     al, "M"             ; override memory size
                jz      fakememsize_parse
                cmp     al, "S"             ; set display start flag
                jz      sds_parse
                cmp     al, "I"             ; hook INT 0x6D
                jz      int6d_parse
@gottaloop:     
                dec     cx
                jcxz    no_params
                jmp     @parse_loop         ; else gotta loop
no_params:
                jmp     build               ; empty or invalid commandline
                
                ; parse override memory size
fakememsize_parse:
                xor     ax, ax
                jcxz    .done
                
                call    bcdhex
                
.done:
                ;we got a number, store it :)
                mov     [memsize_temp], ax
                or      [reset_flag], PATCH_BIT_MEMSIZE
                jmp     @gottaloop

                ; parse page limit
pagelimit_parse:
                xor     ax, ax
                jcxz    .done
                
                call    bcdhex
                
                test    ax, ax
                jnz     .done
                mov     ax, 127
.done:
                ;we got a number, store it :)
                mov     [pagelimit_temp], ax
                or      [reset_flag], PATCH_BIT_PAGELIMIT
                jmp     @gottaloop

                ; parse force RAMDAC width
dacwidth_parse:
                xor     ax, ax
                jcxz    .done
                
                call    bcdhex
                
.done:
                ;we got a number, store it :)
                or      [reset_flag], PATCH_BIT_CAPS
                cmp     ax, 6
                jnz     @gottaloop
                mov     al, 0xFE
                mov     [cap_temp], al
                jmp     @gottaloop
                
                ; parse VBE version override
vbever_parse:
                xor     ax, ax
                jcxz    .done

                call    hexhex

.done:
                ; we got a number, store it :)
                mov     [vbever_temp], ax
                or      [reset_flag], PATCH_BIT_VBEVER
                jmp     @gottaloop

newmodes_parse:
                or      [reset_flag], PATCH_BIT_320X400
                jmp     @gottaloop

palproc_parse:
                or      [reset_flag], PATCH_BIT_PALPROC
                jmp     @gottaloop

int6d_parse:
                or      [reset_flag], PATCH_BIT_INT6D
                jmp     @gottaloop

                ; parse set display start flag
sds_parse:
                xor     ax, ax
                jcxz    .done
                
                call    bcdhex

.done: 
                ; check param
                dec     ax                ; /S1 - force wait for retrace
                jnz     .p2
                mov     dx, 0xFF80        ; dh - AND mask, dl - OR mask
                jmp     .end
.p2:
                dec     ax                ; /S2 - force no wait for retrace
                jnz     .other
                mov     dx, 0x7F00
                jmp     .end
.other:
                mov     dx, 0xFF00        ; any other param - by application
                
.end:
                mov     [sds_mask], dx
                or      [reset_flag], PATCH_BIT_SDS
                jmp     @gottaloop

                ; parse LFB control
lfb_parse:
                xor     ax, ax
                jcxz    .done
                
                call    bcdhex
.done: 
                ; check param
                dec     ax                ; /L1 - force on
                jnz     @f
                mov     dx, 0x7F00        ; dh - AND mask, dl - OR mask
                jmp     .end
@@:
                dec     ax                ; /L2 - force off
                jnz     @f
                mov     dx, 0xFF80        ; dh - AND mask, dl - OR mask
                jmp     .end
@@:
                mov     dx, 0xFF00        ; any other param - by application
                
.end:
                mov     [modecaps_temp], dx
                or      [reset_flag], PATCH_BIT_MODECAPS
                jmp     @gottaloop


booster_parse:
                push    bx
                mov     di, booster_temp
                mov     bx, PATCH_BIT_BOOSTER
                call    endis_parse
                pop     bx
                jmp     @gottaloop

gamma_parse:
                push    bx
                mov     di, gamma_temp
                mov     bx, PATCH_BIT_GAMMA
                call    endis_parse
                pop     bx
                jmp     @gottaloop

endis_parse:
                ; parse enable\disable
                push    dx
                mov     dx, 1               ; if param present - assume enabled
                jcxz    .end                ; last param - assume that enabled
.loop:
                lodsb
                cmp     al, 0xA             ; CR
                jz      .end
                cmp     al, 0xD             ; LF
                jz      .end
                cmp     al, 0x2D            ; "-" - disable
                jz      .dec
                cmp     al, 0x2B            ; "+" - enable
                jz      .end
                cmp     al, 0x2E            ; blabla :)
                ja      .gottaloop
                jmp     .end                ; else - invalid param or end        
.gottaloop:
                loop    .loop
.end:
                mov     [di], dl
                or      [reset_flag], bx
                pop     dx
                ret
.dec:
                dec     dx                  ; dx = 0
                jmp     .end


build:
                ; build it! :)
                mov     ah, 9
                test    bp, bp
                jnz     installed
                
                ; install resident
                call    get_hwinfo
                mov     ah, 9
                mov     dx, installed_str
                int     21h
                call    install
                call    reset_vars
                call    install_appendInfo
                call    display_status
                                
                mov     di, [hw_flag]
                test    di, 2
                jz      .partdecode
                mov     ax, 0x7F00
                mov     [es:fetch_mask], ax
.partdecode:    

                mov     dx, si
                int     27h
                
installed:
                cmp     [reset_flag], 0
                jz      already               ; already installed
                call    reset_vars
                call    restore_lfb
                mov     ah, 9
                mov     dx, reset_str
                int     21h
                call    display_status
                jmp     done_int20
                
already:        mov     dx, already_str
                int     21h
                mov     dx, installed_str
                int     21h
                call    display_status
                jmp     done_int20
                
                
; SUBPROGRAMS

; hex parser
; input:  ds:si - string, cx - number of avail chars in string
; output: ax - number
hexhex:
                xor     ax, ax
                push    bx
                push    dx

                xor     dx, dx
.loop:
                lodsb
                cmp     al, 0xA             ; CR
                jz      .end
                cmp     al, 0xD             ; LF
                jz      .end
                cmp     al, 0x3A            ; blabla :)
                ja      .gottaloop
                cmp     al, '0'
                jb      .end                ; invalid param
                cmp     al, '9'
                ja      .hex
                sub     al, '0'
                jmp     .advance
.hex:
                cmp     al, 0x60
                ja      .uppercase
                sub     al, 0x20
.uppercase:
                sub     al, 'A' + 10
.advance:
                shl     dx, 4
                or      dx, ax
.gottaloop:
                loop    .loop
.end:
                mov     ax, dx              ; save given number in ax
                pop     dx
                pop     bx
                ret

; bcd to hex parser
; input:  ds:si - string, cx - number of avail chars in string
; output: ax - number
bcdhex:
                xor     ax, ax
                push    bx
                push    dx
                
                ; get BCD number
                xor     dx, dx
                mov     bx, 10              ; multiplier          
.loop:
                lodsb
                cmp     al, 0xA             ; CR
                jz      .end
                cmp     al, 0xD             ; LF
                jz      .end
                cmp     al, 0x3A            ; blabla :)
                ja      .gottaloop
                cmp     al, 0x30            ; end or invalid param
                jb      .end          
                ; else we have char in '0' - '9' range
                sub     al, 0x30
                imul    dx, bx              ; dx *= 10    
                add     dx, ax
.gottaloop:
                loop    .loop
                
.end:
                mov     ax, dx              ; save given number in ax
                pop     dx
                pop     bx
                ret
;----
                
; hex to bcd -> stdout converter 
; input:  ax - number
; output: bcd number in stdout
; uses up to 10 bytes in stack
hexbcd:
                push    bx
                push    cx
                push    dx
                mov     bx, 10
                xor     cx, cx
.loop:
                xor     dx, dx
                div     bx      ; remainder in dl
                add     dl, 0x30
                push    dx
                inc     cx
                test    ax, ax
                jnz     .loop
                
                mov     ah, 0x2
                ; закончили конвертировать
.print:
                pop     dx
                int     0x21
                loop    .print
                
                pop     dx
                pop     cx
                pop     bx
                ret
;----
                
; restore LFB address
; input: es - resident segment
; output: none
restore_lfb:
                mov     dx, 0x3D4
                call    (unlock_extensions + (realint10 - resident_start))
                mov     bx, [es:lfb_addr]
                mov     al, 0x59
                mov     ah, bh
                out     dx, ax
                inc     ax
                mov     ah, bl
                out     dx, ax
                
                mov     ah, [es:lfb_size]
                mov     al, 0x58
                out     dx, ax
                call    (lock_extensions + (realint10 - resident_start))
                ret
;----
                
; release resident from memory
; input: es - resident segment
; output: nope, immediate exit from application
release:        mov     ah, 9                   ; remove us
                cmp     bp, 3
                jnz     cant_release
                
                mov     dx, released_str
                int     21h 
                
                mov     ax, [es:int10seg]
                mov     ds, ax
                mov     dx, [es:int10ofs]
                mov     ax, 2510h
                int     21h                    ; set old int10h
                
                ; restore LFB address and size
                call    restore_lfb
                
                ; now we should release memory, okay? :)
                
                mov     ah, 49h
                jmp     done
                
cant_release:   mov     dx, zap_str
                int     0x21
                mov     dx, relfail_str
                int     21h
                test    bp, bp
                jz      notinst
                
                test    bp, INSTALL_BIT_INT6D
                jz      .not_last

                mov     dx, int6d_str
                jmp     done

.not_last:
                mov     dx, notlast_str
                jmp     done
                
notinst:        mov     dx, notinst_str
                int     21h
                mov     dx, crlf
                

done:           int     21h
done_int20:
                int     20h                  ; and now we can exit (yes!)
;----

; display help
; input\output - none
help:
                mov    ah, 9
                mov    dx, help_str
                int    21h
                
                int    20h
;----

; install resident
; input:  es:bx - address of preious int10h handler
; output: es    - new resident segment
install:
                push    es
                
                ; move TSR in PSP area
                cld
                push    cs
                pop     es
                mov     si, realint10
                mov     di, int10
                mov     cx, (newint10end - int10)
                rep     movsb
                
                pop     es
    
                mov     [int10seg], es
                mov     [int10ofs], bx
                mov     ax, 2510h
                mov     dx, newint10
                int     21h

                ; check if need to hook INT6D
                test    [reset_flag], PATCH_BIT_INT6D
                jz      .skip_int6d
                mov     ax, 256Dh
                mov     dx, newint10
                int     21h
.skip_int6d:
	
                ; free environment
                mov     bx, [cs:2Ch]
                mov     es, bx
                mov     ah, 49h
                int     21h	
    
                push    cs
                pop     es
                
                ret
;----
; set/reset requested parameters
reset_vars:
                mov     di, [reset_flag]
                
                test    di, PATCH_BIT_MEMSIZE
                jz      @f
                ; set memory size
                mov     ax, [memsize_temp]
                mov     [es:fakememsize], ax                

@@:
                test    di, PATCH_BIT_SDS
                jz      @f
                ; set display start flags
                mov     ax, [sds_mask]
                mov     [es:sds_or],  al
                mov     [es:sds_and], ah
                
@@:
                test    di, PATCH_BIT_BOOSTER
                jz      @f
                ; set booster flag
                mov     al, [booster_temp]
                mov     [es:booster_en], al
                
@@:
                test    di, PATCH_BIT_CAPS
                jz      @f
                ; set capabilities flag
                mov     al, [cap_temp]
                mov     [es:cap_and], al
                
@@:
                test    di, PATCH_BIT_GAMMA
                jz      @f
                ; set gamma flag
                mov     al, [gamma_temp]
                mov     [es:gamma_en], al

@@:
                test    di, PATCH_BIT_VBEVER
                jz      @f
                ; override VBE version
                mov     ax, [vbever_temp]
                mov     [es:vbever], ax

@@:
                test    di, PATCH_BIT_PAGELIMIT
                jz      @f
                ; override page limit
                mov     ax, [pagelimit_temp]
                mov     [es:pagelimit], ax

@@:
                test    di, PATCH_BIT_MODECAPS
                jz      @f
                ; override page limit
                mov     ax, [modecaps_temp]
                mov     [es:modecaps_or],  al
                mov     [es:modecaps_and], ah

@@:
                ret
;----

; display curent TSR status
; input:  es - resident segment
; output: none
display_status:
                push    ax
                push    bx
                push    cx
                push    dx

                ; query VESA BIOS
                push    es
                push    di
                push    cs
                pop     es
                mov     ax, 0x4F00
                mov     di, vbeinfo_transient
                int     0x10
                pop     di
                pop     es

                ; preload AH=0x09 for string out
                mov     ah, 0x9

                ; display VBE version
                mov     dx, dv_1
                int     0x21

                mov     bx, [cs:vbeinfo_transient + VbeInfoBlock.VbeVersion]
                
                ; print first digit
                xor     ax, ax
                mov     al, bh
                call    hexbcd

                ; print dot
                mov     ah, 0x02
                mov     dl, '.'
                int     0x21

                ; print second digit
                xor     ax, ax
                mov     al, bl
                call    hexbcd

                ; print if overrided or not
                mov     ah, 0x09
                cmp     [es:vbever], 0
                jz      @dv_done
                mov     dx, dm_forced
                int     0x21
@dv_done:
                mov     dx, crlf
                int     0x21

                ; display override memory status
                mov     dx, dm_1
                int     0x21
                
                mov     bx, [es:fakememsize]
                test    bx, bx
                jz      @dm_bios
                
                mov     ax, bx
                shl     ax, 6
                call    hexbcd
                
                mov     ah, 0x9
                mov     dx, dm_kb
                int     0x21
                mov     dx, dm_forced
                int     0x21
                jmp     @dm_done
@dm_bios:
                ; query VESA BIOS
                mov     ax, [cs:vbeinfo_transient + VbeInfoBlock.TotalMemory]
                shl     ax, 6
                call    hexbcd
                
                mov     ah, 0x9
                mov     dx, dm_kb
                int     0x21
@dm_done:
                mov     dx, crlf
                int     0x21

                ; display max page count
                mov     dx, dp_1
                int     0x21

                mov     ax, [es:pagelimit]
                call    hexbcd

                mov     ah, 0x9
                mov     dx, crlf
                int     0x21

                ; display LFB status
                mov     dx, dl_1
                int     0x21

                mov     bl, [es:modecaps_or]
                mov     bh, [es:modecaps_and]
                cmp     bx, 0xFF00
                jnz     @dl_not_default
                mov     dx, dd_dis ; RE-RE-RE-RECYCLING!!1!!
                int     0x21
                jmp     @dl_done
@dl_not_default:
                mov     dx, ds_forced
                int     0x21
                cmp     bx, 0xFF80
                jnz     @dl_force_disabled
                mov     dx, db_en
                int     0x21
                jmp     @dl_done
@dl_force_disabled:
                mov     dx, db_dis
                int     0x21
@dl_done:

                ; display 320x400/480 modes status
                mov     dx, dx_1
                int     0x21
                
                mov     bx, [es:modexlatptr]
                test    bx, bx
                jz      @dx_dis
                mov     dx, db_en
                int     0x21
                jmp     @dx_done
@dx_dis:
                mov     dx, db_dis
                int     0x21
@dx_done:

                ; display palproc status

                mov     dx, dq_1
                int     0x21
                
                mov     bl, [es:f9_jmp]
                cmp     bl, 0xEB            ; jnz @invoke -> palproc disabled
                jz      @dq_dis
                mov     dx, dq_custom
                int     0x21
                jmp     @dq_done
@dq_dis:
                mov     dx, dq_default
                int     0x21
@dq_done:


                ; display booster status
                mov     dx, db_1
                int     0x21
                
                mov     bl, [es:booster_en]
                test    bl, bl
                jz      @db_dis
                mov     dx, db_en
                int     0x21
                jmp     @db_done
@db_dis:
                mov     dx, db_dis
                int     0x21
@db_done:

                ; display "set display start" status

                mov     dx, ds_1
                int     0x21
                
                mov     bl, [es:sds_or]
                mov     bh, [es:sds_and]
                cmp     bx, 0xFF00
                jnz     @ds_force
                mov     dx, dd_dis ; RE-RE-RE-RECYCLING!!1!!
                int     0x21
                jmp     @ds_done
@ds_force:
                cmp     bx, 0x7F00
                jnz     @ds_wait
                
                mov     dx, ds_forced
                int     0x21
                mov     dx, ds_no
                int     0x21
                mov     dx, ds_retr
                int     0x21
                jmp     @ds_done
@ds_wait:
                mov     dx, ds_forced
                int     0x21
                mov     dx, ds_retr
                int     0x21
@ds_done:

                ; display ramdac width status
                mov     dx, dd_1
                int     0x21
                
                mov     bl, [es:cap_and]
                inc     bl
                jz      @dd_dis
                mov     dx, dd_en
                int     0x21
                jmp     @dd_done
@dd_dis:
                mov     dx, dd_dis
                int     0x21
@dd_done:
                ; display gamma correction status
                mov     dx, dg_1
                int     0x21

                mov     al, [es:gamma_en]
                test    al, al
                jz      @dg_dis
                mov     dx, db_en
                int     0x21
                jmp     @dg_done
@dg_dis:
                mov     dx, db_dis
                int     0x21
@dg_done:

                pop     dx
                pop     cx
                pop     bx
                pop     ax
                ret
                
crlf            db      13,10,"$" 
dv_1            db      "- VESA BIOS Extensions version:     $"
dp_1            db      "- VESA maximum video page count:    $"

db_1            db      "- VESA banked modes booster status: $"
db_en           db      "enabled",13,10,"$"
db_dis          db      "disabled",13,10,"$"

dd_1            db      "- RAMDAC CLUT width setting:        $"
dd_en           db      "force 6 bit per channel",13,10,"$"
dd_dis          db      "normal",13,10,"$"

dg_1            db      "- Hi/TrueColor gamma correction:    $"

dx_1            db      "- VESA 320x400 and 320x480 modes:   $"

dl_1            db      "- VESA Linear Frame Buffer control: $"

dm_1            db      "- VESA available memory size:       $"
dm_kb           db      " KB$"
dm_forced       db      " (forced)$"

ds_1            db      "- 'set display start' flag status:  $"
ds_forced       db      "force $"
ds_no           db      "no $"
ds_retr         db      "wait for retrace",13,10,"$"

dq_1            db      "- VESA Get/Set Palette (0x4F09):    $"
dq_default      db      "default or none",13,10,"$"
dq_custom       db      "custom",13,10,"$"

;----
; installation check
; input:  AL = interrupt
; output: BP = install flags, ES:BX - S3VBEFIX resident copy entrypoint, CX - current ISR segment
install_check:
                mov     [.int], al
                jmp     $+2                 ; pipeline flush
                
                ; check for already installed
                mov     ah, 0x35
                int     0x21                 ; get interrupt vector
                push    es
                pop     cx
                
                ; installation check
                mov     ax, check_func
                mov     dx, check_in
                int     0x10
.int            =       $-1

                test    ax, ax
                jnz     .ret                ; not installed
                cmp     dx, check_out
                jnz     .ret                ; not installed
                cmp     word [es:bx - (newint10 - newint10id) ], resident_id    ; check for signature
                jnz     .ret                ; NOT INSTALLED
                cmp     word [es:bx - (newint10 - newint10ver)], resident_ver   ; check for version
                jnz     .ret                ; NOT INSTALLED!!!1 (arrrgh!)

                or      bp, INSTALL_BIT_INT10       ; installed

                ; check if our resident is last in chain
                mov     ax, es
                cmp     ax, cx
                jnz     parse
                or      bp, INSTALL_BIT_INT10LAST   ; last in chain
.ret:
                ret

;----
; check for hardware environment
; input/output: ?
get_hwinfo:
                ; check for S3 card installed
                ; warning: may screw up some hardware registers on other cards!
                mov     dx, 0x3d4
                call    (lock_extensions + (realint10 - resident_start))
                mov     al, 0x30        ; s3 old chip id (NOT unlocked!)
                out     dx, al
                inc     dx
                in      al, dx
                mov     ah, al
                dec     dx
                push    ax
                call    (unlock_extensions + (realint10 - resident_start))
                pop     ax
                mov     al, 0x30        ; s3 old chip id
                out     dx, al
                inc     dx
                in      al, dx
                dec     dx
                cmp     al, ah
                ;jz      .not_inst  ; comment for DOSbox hack here!
                or      [hw_flag], 1
                
                ; check for crtc regs decoding
                ; if b7 of reg index is not decoded then i.e. reg0x10 and reg0x90 are same
                mov     al, 0x10        ; vertical retrace start position
                out     dx, al
                inc     dx
                in      al, dx
                mov     ah, al
                dec     dx
                mov     al, 0x90        ; primary stream fifo fetch
                out     dx, al
                inc     dx
                in      al, dx
                dec     dx
                cmp     al, ah
                jz      .decode
                or      [hw_flag], 2    ; crtc reg0x90 is available
.decode:
                call    (lock_extensions + (realint10 - resident_start))
                ret
                
.not_inst:
                ; if S3 card is not installed at all - GET OUT THERE!!1!!1! :)
                mov     ah, 0x9
                mov     dx, zap_str
                int     0x21
                mov     dx, notinst_str
                int     0x21
                mov     dx, dash_str
                int     0x21
                mov     dx, nots3_str
                int     0x21
                jmp     done

; append info (mode list and xlat table) to the end of TSR
; output: si - last resident address
install_appendInfo:
                ; get LFB address
                mov     dx, 0x3D4
                call    unlock_extensions
                
                mov     al, 0x58
                out     dx, al
                inc     dx
                in      al, dx
                mov     [lfb_size], al
                dec     dx
                
                mov     al, 0x59
                out     dx, al
                inc     dx
                in      al, dx
                mov     bh, al
                dec     dx
                
                mov     al, 0x5A
                out     dx, al
                inc     dx
                in      al, dx
                mov     bl, al
                dec     dx
                mov     [lfb_addr], bx
                call    lock_extensions

                ; test if install custom Get/Set Palette?
                mov     si, palproc                                     ; SI - last resident memory address
                test    [reset_flag], PATCH_BIT_PALPROC
                jz      .skip_palproc

                ; patch f9_jmp from 0xEB to 0x75
                mov     byte [f9_jmp], 0x75
                mov     si, newint10end

.skip_palproc:
                ; test if add new modes
                test    [reset_flag], PATCH_BIT_320X400
                jz      @scan_ret
                
                ; add 320x400 / 320x480 modes, append mode xlat and new mode list to TSR end

                ; get vbe info block
                mov     di, vbeinfo_transient
                mov     ax, 0x4F00
                ; осторожно, возможна "проблема курицы и яйца", так что
                ; вместо int 10h здесь будет прямой вызов старого обработчика
                pushf
                call    dword [int10ofs]

                ; set mode patch table pointer
                mov     ax, newint10end
                mov     [modexlatptr], ax
                
                ; copy mode table
                mov     ds, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr + 2]
                mov     si, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr    ]
                
                mov     di, modetab_temp
                
@modetab_copy_loop:
                lodsw
                cmp     ax, 0xFFFF   ; check for 0xFFFF terminator
                jz      @modetab_copy_done
                stosw
                jmp     @modetab_copy_loop
                
@modetab_copy_done:
                ; di points to mode table end (without 0xFFFF terminator)

                ; now scan this table for 320x(something) modes for patching
                mov     ax, es
                mov     ds, ax 
                
                mov     dx, 0x1F0   ; первый режим по списку, "созданный" нами
                mov     fs, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr + 2]
                mov     bx, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr]
                mov     bp, newint10end   ; modexlat start
                mov     si, di            ; конец mode_table
                mov     di, modeinfo_temp ; modeinfo_transient
                
@scan_loop:
                mov     cx, [fs:bx] ; get mode number
                add     bx, 2
                cmp     cx, 0xFFFF
                jz      @scan_done  ; end of table
                
                ; get mode info
                mov     ax, 0x4F01
                pushf
                call    dword [int10ofs]
                
                cmp     word [es:di + ModeInfoBlock.XResolution], 320
                jnz     @scan_not_target    ; не наш клиент :)
                cmp     word [es:di + ModeInfoBlock.YResolution], 350
                jae     @scan_not_target    ; не наш клиент :)
                
                ; add new mode to mode table and patch table
                mov     word [ds:si    ], dx
                mov     word [ds:bp    ], dx
                mov     word [ds:bp + 2], cx
                inc     dx
                add     si, 2
                add     bp, 4
                
@scan_not_target:
                jmp     @scan_loop
                
@scan_done:
                ; add terminators to tables
                mov     ax, 0xFFFF
                mov     word [ds:si], ax
                mov     word [ds:bp], ax
                
                ; set modetab pointer and append it to resident
                add     si, 2
                add     bp, 2
                mov     [modetabptr], bp
                ; SI - temp mode table end, BP - mode xlat end

                mov     di, bp
                mov     cx, si
                mov     si, modetab_temp
                sub     cx, si              ; calculate modetab length
                shr     cx, 1
                rep     movsw
                
                mov     si, di
                
@scan_ret:
                ; si - last resident address
                ret
;----

; temp variables
reset_flag      dw      0
hw_flag         dw      0
memsize_temp    dw      0
sds_mask        dw      0xFF00
booster_temp    db      0
cap_temp        db      0xFF
gamma_temp      db      0
vbever_temp     dw      0
pagelimit_temp  dw      127
modecaps_temp   dw      0xFF00


; some place for mode info block (will be used for initialization)
vbeinfo_transient:
