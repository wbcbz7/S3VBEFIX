; s3vbefix main code - wbcbz7 xx.xx.0x7e0
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
resident_ver        equ     0x0051   ; resident version, in 0x1234 - 12.3.4 format

check_func          equ     0xCE00   ; installation check function number
check_in            equ     "ne"     ; installation check key input  word
check_out           equ     "ko"     ; installation check key output word 
; pretty nice (and simple) choice, eh? ^.^

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
            cmp     [cs:inTSR], 1
            jnz     @first_call
            ; here is a trick - since fasm doesn't support org as "move assembly
            ; pointer" we need to build our instruction "by hand"
            db      0xEA    ; jmp dword ?:?
int10ofs    dw      ?
int10seg    dw      ?
            
@first_call:
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
            jnz     @check_vbe
            cmp     dx, check_in
            jnz     @check_vbe
            ; installation check
            ; input:  ax    = check_func (see above)
            ;         dx    = check_in
            ; output: ax    = 0x0000
            ;         dx    = check_out
            ;         es:bx = resident entry point
            mov     ax, ds
            mov     es, ax
            xor     ax, ax
            mov     dx, check_out
            mov     bx, newint10
            jmp     done_2
            
@check_vbe: 
            cmp     ah, 0x4F
            jnz     @invoke
            ; check for VESA calls to patch mode number
            mov     si, mode_xlat
            
            cmp     al, 0x1     ; Function 01h  - Get VBE Mode Information
            jnz     @@f2
            ; replace mode number
            push    bx
            mov     bx, cx
            call    patch_mode
            mov     [patchedmode], bx
            mov     cx, bx
            pop     bx
            
@@f2:
            cmp     al, 0x2     ; Function 02h  - Set VBE Mode
            jnz     @@f5
            ; replace mode number
            call    patch_mode
            mov     [patchedmode], bx
            ; if lfb+clear requested - set banked+clear then lfb+noclear
            ; (because booster can crash the system otherwise)
            test    bh, 0x40
            jz      @invoke     ; banked
            ; do it!
            push    ax
            push    bx
            and     bh, 0xBF
            pushf                   ; в принципе можно и int 0x10, защита от
            call    dword [int10ofs]; повторного вхождения есть
            pop     bx
            pop     ax
            or      bh, 0x80
            
@@f5:
            cmp     al, 0x5     ; Function 05h - Display Window Control
            jnz     @@f7
            push    cs
            call    bankproc    ; perform far call
            jmp     done_2
            
@@f7:
            cmp     al, 0x7     ; Function 07h - Set/Get Display Start
            jnz     @invoke
            ; clear "wait for retrace" flag
            db      0x82, 0xCB  ; or bl, ?
sds_or      db      0x00
            db      0x82, 0xE3  ; and bl, ?
sds_and     db      0xFF

            
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
            ; all done, reset inTSR flag and quit from ISR
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
            
            ; vga function 0x0 - fix primary stream fifo fetch bug
fix_fetch:
            mov     dx, 0x3D4
            
            call    unlock_extensions
            
            mov     al, 0x90
            db      0xBB    ; mov bx, ?
fetch_mask  dw      0xFF00
            call    rmw
            
            call    lock_extensions
            
            jmp     done_iret
            
            ; VESA function 0x0 patch
patch_vbeinfo:
            mov     ax, cs
            mov     word [es:di + VbeInfoBlock.VideoModePtr + 2], ax
            mov     ax, mode_table
            mov     word [es:di + VbeInfoBlock.VideoModePtr    ], ax
            
            mov     al, byte [es:di + VbeInfoBlock.Capabilities]
            db      0x24  ; and al, ?
cap_and     db      0xFF
            mov     byte [es:di + VbeInfoBlock.Capabilities], al
            
            mov     ax, [fakememsize] 
            test    ax, ax
            jz      done_iret
            
            ; override memory size
            mov    [es:di + VbeInfoBlock.TotalMemory], ax
            
            jmp     done_iret
            
            ; VESA function 0x1 patch
patch_modeinfo:
            mov     ax, cs
            mov     word [es:di + ModeInfoBlock.WinFuncPtr + 2], ax
            mov     ax, bankproc
            mov     word [es:di + ModeInfoBlock.WinFuncPtr    ], ax

            ; check for modenum is patched
            cmp     cx, dx
            jz      .memsize_chk
            
            ; set 400 pixel height
            mov     ax, [es:di + ModeInfoBlock.YResolution]
            shl     ax, 1
            mov     [es:di + ModeInfoBlock.YResolution], ax
            
            ; divide page number by two
            mov     al, [es:di + ModeInfoBlock.NumberOfImagePages]
            inc     al
            shr     al, 1
            dec     al
            mov     [es:di + ModeInfoBlock.NumberOfImagePages], al
            
.memsize_chk:
            ; check for overriden memsize
            mov     ax, [fakememsize] 
            test    ax, ax
            jz      done_iret
            
            push    ax
            mov     ax, [es:di + ModeInfoBlock.BytesPerScanLine]
            mov     bx, [es:di + ModeInfoBlock.YResolution]
            mul     bx              ; dx:ax - page size in bytes
            add     ax, 0xFFFF
            adc     dx, 0           ; ceil(dx:ax)
            
            mov     bx, dx          ; bx - page size in 64kb blocks (inaccurate but who cares? :)
            xor     dx, dx
            pop     ax
            div     bx              ; ax - number of pages
            
            test    ax, ax          ; numofpages = 0?
            jz      .not_avail      ; mode is not available in fact
            
            ; check for pagenum >= 128
            ; some LAME apps treat this field as signed byte (//_-)
            cmp     ax, 128
            jb      .pagenum_ok
            ; clip it
            mov     ax, 127
.pagenum_ok:
            ; if avail - set new pages value
            dec     al
            mov     [es:di + ModeInfoBlock.NumberOfImagePages], al
            jmp     done_iret
            
.not_avail:            
            ; set "not supported" flag
            mov     ax, [es:di + ModeInfoBlock.ModeAttributes]
            and     ax, 0xFFFE
            mov     [es:di + ModeInfoBlock.ModeAttributes], ax
            
            jmp     done_iret
            
            ; VESA function 0x2 patch
patch_modeset:
            ; check for modenum < 0x100
            cmp     bx, 0x100
            jb      fix_fetch
            
            ; check for modenum is patched
            cmp     bx, dx
            jz      modeset_booster
            
            mov     dx, 0x3D4
            
            ; set scanline height = 1       
            mov     al, 0x9
            mov     bx, 0x6000
            call    rmw
            
modeset_booster:
            db      0xB8                ; mov ax, ?
booster_en  dw      0                   ; booster flag (nonzero - enabled)
            test    ax, ax
            jz      done_iret           ; booster not enabled
            ; BOOSTAH! :)
            mov     dx, 0x3D4
            call    unlock_extensions
            test    bx, 0x4000
            jnz     booster_lfb
            
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
            
booster_done:
            call    lock_extensions
            jmp     done_iret

            ; VESA function 0x5 new routine
bankproc:
            push    cx
            
            test    bl, bl              ; check for selected window
            jnz     @bankproc_fail      ; window B is not supported

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
            jz      @bankproc_lfb       ; not supported in VGA or LFB modes
            
            mov     al, 0x6A
            ; check for get/set bank
            test    bh, bh
            jnz     @bankproc_get
            
            ; set new window pos
            mov     ah, cl
            out     dx, ax
            call    lock_extensions
            jmp     @bankproc_ok
            
@bankproc_get:
            out     dx, al
            inc     dx
            in      al, dx
            dec     dx
            call    lock_extensions
            xor     dx, dx
            mov     dl, al
            
@bankproc_ok:
            mov     ax, 0x004F
            jmp     @bankproc_done
@bankproc_fail:
            mov     ax, 0x014F
            jmp     @bankproc_done
@bankproc_lfb:
            mov     ax, 0x034F
@bankproc_done:
            pop     cx
            retf

; VESA function 0x6 patcher
; just recalculate maximum number of scanlines

patch_setscanlinelen:
            ; check for overriden memsize
            mov     ax, [fakememsize] 
            test    ax, ax
            jz      done_iret

            ; and then...do stack frame hacking :)
            push    bp
            mov     bp, sp
            ; stack frame: sp   - old_bp; sp+2 - out_dx; sp+4 - out_cx;
            ;              sp+6 - out_bx; sp+8 - out_ax
            
            mov     dx, ax
            xor     ax, ax
            div     word [ss:bp+6]  ; out_bx = new bytes per scanline
            mov     [ss:bp+2], ax   ; ax     = new max number of scanlines
            
            pop     bp
            jmp     done_iret
            
; replace current VESA mode number with other (used for mode info block patching)
; input:  BX - VESA mode number; DS:SI - address of replacement table
; output: BX - patched mode number; SI destroyed          
patch_mode:
            push    ax
@patch_loop:
            lodsb
            cmp     al, 0xFF    ; check for 0xFF terminator
            jz      @patch_done
            cmp     bl, al
            jz      @patch_yep
            inc     si          ; else adjust table
            jmp     @patch_loop
@patch_yep: lodsb
            mov     bl, al
@patch_done:pop     ax
            ret                  
            
add_vars:
; additional vars
fakememsize dw      0 ; fake memory size (set via /Mx, 0 - BIOS default)
lfb_size    db      0 ; LFB size (0x3d4 index 0x58)
lfb_addr    dw      0 ; LFB address bits 16-31 (saved for booster)
            
; mode number patch table (filled by transient part)
; format - [src_modenum], [dst_modenum], ... , 0xFF
; only low bytes are stored
mode_xlat   db      (10*2 + 1) dup 0xFF  ; for security reasons
; so why (10*2) + 1? :) well because we can have 320x(200\240) 8\15\16\24\32bpp
; and we need to expand 'em all (+ termination byte ofcourse)

; VESA mode table starts here (with dynamic size)
mode_table:
newint10end:

;--------------------------------------------------------------------------------------------------
; START OF TRANSIENT PART
                org     realint10 + (newint10end - int10)
init:
                push    cs
                pop     ds
                xor     bp, bp              ; will be used later
                
                mov     ah, 9
                mov     dx, info_str
                int     0x21
                
                ; check for already installed
                mov     ax, 0x3510
                int     0x21                 ; get int10h vector
                push    es
                pop     gs
                
                ; installation check via int10
                mov     ax, check_func
                mov     dx, check_in
                int     0x10
                test    ax, ax
                jnz     parse               ; not installed
                cmp     dx, check_out
                jnz     parse               ; not installed
                
                cmp     word [es:bx - (newint10 - newint10id) ], resident_id    ; check for signature
                jnz     parse               ; NOT INSTALLED
                cmp     word [es:bx - (newint10 - newint10ver)], resident_ver   ; check for version
                jnz     parse               ; NOT INSTALLED!!!1 (arrrgh!)
                
                or      bp, 1               ; installed
                ; check if our resident is last in chain
                mov     ax, es
                mov     cx, gs
                cmp     ax, cx
                jnz     parse
                or      bp, 2               ; last in chain
parse:
                ; зануляем часть переменных
                xor     ax, ax
                mov     [memsize_temp], ax
                mov     [booster_temp], ax
                mov     ax, 0xFF00
                mov     [sds_mask], ax
                mov     [cap_temp], ah
                
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
                cmp     al, "D"             ; force RAMDAC width
                jz      dacwidth_parse
                cmp     al, "M"             ; override memory size
                jz      fakememsize_parse
                cmp     al, "S"             ; set display start flag
                jz      sds_parse
@gottaloop:     jcxz    no_params
                loop    @parse_loop         ; else gotta loop
no_params:
                jmp     build               ; empty or invalid commandline
                
                ; parse override memory size
fakememsize_parse:
                dec     cx
                jcxz    no_params
                
                call    bcdhex
                
                ;we got a number, store it :)
                mov     [memsize_temp], ax
                or      [reset_flag], 1
                jmp     @gottaloop
                
                ; parse force RAMDAC width
dacwidth_parse:
                dec     cx
                jcxz    no_params
                
                call    bcdhex
                
                ;we got a number, store it :)
                or      [reset_flag], 8
                cmp     ax, 6
                jnz     @gottaloop
                mov     al, 0xFE
                mov     [cap_temp], al
                jmp     @gottaloop
                
                ; parse set display start flag
sds_parse:
                dec     cx
                jcxz    no_params
                
                call    bcdhex
                
                ; check param
                dec     ax                ; /S1 - force wait for retrace
                jnz     @sds_p2
                mov     dx, 0xFF80        ; dh - AND mask, dl - OR mask
                jmp     sds_end
@sds_p2:
                dec     ax                ; /S2 - force no wait for retrace
                jnz     @sds_other
                mov     dx, 0x7F00
                jmp     sds_end
@sds_other:
                mov     dx, 0xFF00        ; any other param - by application
                
sds_end:
                mov     [sds_mask], dx
                or      [reset_flag], 2
                jmp     @gottaloop
                
                ; parse booster enable\disable
                ; какой-то пиздец здесь :D
booster_parse:
                push    dx
                mov     dx, 1               ; if /B param present - assume that booster is enabled
                dec     cx
                jcxz    @bparse_end         ; last param - assume that enabled
@bparse_loop:
                lodsb
                cmp     al, 0xA             ; CR
                jz      @bparse_end
                cmp     al, 0xD             ; LF
                jz      @bparse_end
                cmp     al, 0x2D            ; "-" - disable
                jz      @bparse_dec
                cmp     al, 0x2B            ; "+" - enable
                jz      @bparse_end
                cmp     al, 0x2E            ; blabla :)
                ja      @bparse_gottaloop
                jmp     @bparse_end         ; else - invalid param or end        
@bparse_gottaloop:
                loop    @bparse_loop
@bparse_end:
                mov     [booster_temp], dx
                or      [reset_flag], 4
                pop     dx
                jmp     @gottaloop
@bparse_dec:
                dec     dx                  ; dx = 0
                jmp     @bparse_end
                
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
                call    hujak_info
                call    display_status
                                
                mov     di, [hw_flag]
                test    di, 2
                jz      .partdecode
                mov     ax, 0x7F00
                mov     [es:fetch_mask], ax
.partdecode:    

                jmp     install_done
                
installed:
                cmp     [reset_flag], 0
                jz      already               ; already installed
                call    reset_vars
                call    restore_lfb
                mov     ah, 9
                mov     dx, reset_str
                int     21h
                call    display_status
                jmp     done
                
already:        mov     dx, already_str
                int     21h
                mov     dx, installed_str
                int     21h
                call    display_status
                jmp     done
                
install_done:   mov     dx, si
                int     27h
                
                
; SUBPROGRAMS

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
@bcdhex_loop:
                lodsb
                cmp     al, 0xA             ; CR
                jz      @bcdhex_end
                cmp     al, 0xD             ; LF
                jz      @bcdhex_end
                cmp     al, 0x3A            ; blabla :)
                ja      @bcdhex_gottaloop
                cmp     al, 0x30            ; end or invalid param
                jb      @bcdhex_end          
                ; else we have char in '0' - '9' range
                sub     al, 0x30
                imul    dx, bx              ; dx *= 10    
                add     dx, ax
@bcdhex_gottaloop:
                loop    @bcdhex_loop
                
@bcdhex_end:
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
@hexbcd_loop:
                xor     dx, dx
                div     bx      ; remainder in dl
                add     dl, 0x30
                push    dx
                inc     cx
                test    ax, ax
                jnz     @hexbcd_loop
                
                mov     ah, 0x2
                ; закончили конвертировать
@hexbcd_print:
                pop     dx
                int     0x21
                loop    @hexbcd_print
                
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
                int     21h
                jmp     done
                
cant_release:   mov     dx, zap_str
                int     0x21
                mov     dx, relfail_str
                int     21h
                test    bp, bp
                jz      notinst
                
                mov     dx, notlast_str
                int     21h
                jmp     done
                
notinst:        mov     dx, notinst_str
                int     21h
                mov     dx, crlf
                int     21h

done:           int     20h                  ; and now we can exit (yes!)
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
	
                ; free environment
                mov     bx, [cs:2Ch]
                mov     es, bx
                mov     ah, 49h
                int     21h	
    
                push    cs
                pop     es
                
                ret
;----
; ставим те переменные которые меняются
reset_vars:
                mov     di, [reset_flag]
                
                test    di, 1
                jz      @reset_skip1
                ; set memory size
                mov     ax, [memsize_temp]
                mov     [es:fakememsize], ax                

@reset_skip1:
                test    di, 2
                jz      @reset_skip2
                ; set display start flags
                mov     ax, [sds_mask]
                mov     [es:sds_or],  al
                mov     [es:sds_and], ah
                
@reset_skip2:
                test    di, 4
                jz      @reset_skip4
                ; set booster flag
                mov     ax, [booster_temp]
                mov     [es:booster_en], ax
                
@reset_skip4:
                test    di, 8
                jz      @reset_skip8
                ; set booster flag
                mov     al, [cap_temp]
                mov     [es:cap_and], al
                
@reset_skip8:

                ret
;----

; display curent TSR status
; input:  es - resident segment
; output: none
; походу эта епаная бодяга действует - я начал давать меткам короткие имена xD
display_status:
                push    ax
                push    bx
                push    cx
                push    dx
                mov     ah, 0x9
                ; display booster status
                mov     dx, db_1
                int     0x21
                
                mov     bx, [es:booster_en]
                test    bx, bx
                jz      @db_dis
                mov     dx, db_en
                int     0x21
                jmp     @db_done
@db_dis:
                mov     dx, db_dis
                int     0x21
@db_done:
                
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
                push    es
                push    di
                push    cs
                pop     es
                
                mov     ax, 0x4F00
                mov     di, vbeinfo_transient
                int     0x10
                mov     ax, [es:di + VbeInfoBlock.TotalMemory]
                shl     ax, 6
                call    hexbcd
                
                pop     di
                pop     es
                mov     ah, 0x9
                mov     dx, dm_kb
                int     0x21
                mov     dx, crlf
                int     0x21
@dm_done:
                
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
                
                pop     dx
                pop     cx
                pop     bx
                pop     ax
                ret
                
crlf            db      13,10,"$" 
db_1            db      "- VESA banked modes booster status: $"
db_en           db      "enabled",13,10,"$"
db_dis          db      "disabled",13,10,"$"

dd_1            db      "- RAMDAC CLUT width setting:        $"
dd_en           db      "force 6 bit per channel",13,10,"$"
dd_dis          db      "normal",13,10,"$"

dm_1            db      "- VESA available memory size:       $"
dm_kb           db      " KB$"
dm_forced       db      " (forced)",13,10,"$"

ds_1            db      "- 'set display start' flag status:  $"
ds_forced       db      "force $"
ds_no           db      "no $"
ds_retr         db      "wait for retrace",13,10,"$"

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
                jz      .not_inst
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

; set mode number patching and mode number table
; input:  es - resident segment
; output: ?
hujak_info:
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

                ; get vbe info block
                mov     di, vbeinfo_transient
                mov     ax, 0x4F00
                ; осторожно, возможна "проблема курицы и яйца", так что
                ; вместо int 10h здесь будет прямой вызов старого обработчика
                pushf
                call    dword [int10ofs]
                
                ; copy mode table
                mov     ax, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr + 2]
                mov     ds, ax
                mov     ax, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr    ]
                mov     si, ax
                
                mov     di, mode_table
                
@modetab_copy_loop:
                lodsw
                cmp     ax, 0xFFFF   ; check for 0xFFFF terminator
                jz      @modetab_copy_done
                stosw
                jmp     @modetab_copy_loop
                
@modetab_copy_done:
                ; now scan this table for 320x(something) modes for patching
                mov     ax, es
                mov     ds, ax 
                
                mov     dx, 0x180   ; первый режим по списку, "созданный" нами
                mov     ax, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr + 2]
                mov     fs, ax
                mov     bx, word [cs:vbeinfo_transient + VbeInfoBlock.VideoModePtr]
                mov     bp, mode_xlat
                mov     si, di      ; конец mode_table
                mov     di, (vbeinfo_transient + 512) ; modeinfo_transient
                
@scan_loop:
                mov     cx, [fs:bx] ; get mode number
                add     bx, 2
                cmp     cx, 0xFFFF
                jz      @scan_done  ; end of table
                
                ; get mode info
                mov     ax, 0x4F01
                pushf
                call    dword [int10ofs]
                
                mov     ax, [es:di + ModeInfoBlock.XResolution]
                cmp     ax, 320
                jnz     @scan_not_target    ; не наш клиент :)
                mov     ax, [es:di + ModeInfoBlock.YResolution]
                cmp     ax, 350
                jae     @scan_not_target    ; не наш клиент :)
                
                ; add new mode to mode table and patch table
                mov     word [ds:si    ], dx
                mov     byte [ds:bp    ], dl
                mov     byte [ds:bp + 1], cl
                inc     dx
                add     si, 2
                add     bp, 2
                
@scan_not_target:
                jmp     @scan_loop
                
@scan_done:
                ; add terminators to tables
                mov     ax, 0xFFFF
                mov     word [ds:si], ax
                mov     byte [ds:bp], al
                
                add     si, 2
                ret
;----

info_str        db      "S3 VBE fix TSR v.0.5.1 - by wbc\\bz7 15.o6.2o16"
dash_str        db      " - $"                                      ; small trick here
already_str     db      "already $"
installed_str   db      "installed",13,10,13,10,"$"
reset_str       db      "reset",13,10,13,10,"$"
released_str    db      "released",13,10,"$"
zap_str         db      8,8,8,"   ",13,10,"$"
relfail_str     db      "unable to release - $"
notlast_str     db      "not last in chain",13,10,"$"
notinst_str     db      "not installed$"
nots3_str       db      "can't find S3 graphics card",13,10,"$"
help_str        db      "help",13,10,13,10
                db      "/B[+/-] - enable\disable banked VESA modes booster",13,10
                db      "/D[x]   - force RAMDAC CLUT width (/D8 - normal, /D6 - force 6 bit)",13,10
                db      "/M[x]   - override memory size in 64kb units (/M16 - 1 MB, /M0 - by BIOS)",13,10
                db      "/S[x]   - 'set display start' mode",13,10
                db      "          (/S0 - normal, /S1 - force wait for retrace, /S2 - force no wait)",13,10
                db      "/R, /U  - release from memory",13,10,"$"
reset_flag      dw      0
hw_flag         dw      0

; some place for mode info block (will be used for initialization)
vbeinfo_transient:
; некоторые временные переменные - будут переписаны vesa инфой
memsize_temp    dw      ?
sds_mask        dw      ?
booster_temp    dw      ?
cap_temp        db      ?
