; s3vbefix main code
; just tryin' to implement primary stream fifo fetch bug fix

; use FASM to compile

format binary

; VESA 2.0 mode info block structure

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

resident_start equ 40h ; resident start offset

start:
            org     100h
            jmp     init
            nop
        
            ; start of resident part
realint10:
            org     resident_start
int10:
newint10id  dw  "fK"
inTSR       db  0       ; флаг для проверки на повторный вызов
            ; resident entry point
newint10:
            ; check for inner call
            cmp     [cs:inTSR], 1
            jnz     @first_call
            jmp     dword [cs:int10ofs]
            
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
            
            cmp     ah, 0x4F
            jnz     @invoke
            ; check for VESA calls to patch mode number
            cmp     al, 0x1     ; Function 01h  - Get VBE Mode Information
            jnz     @@not_this
            mov     si, mode_xlat
            push    bx
            mov     bx, cx
            call    patch_mode
            mov     [patchedmode], bx
            mov     cx, bx
            pop     bx
            jmp     @invoke
@@not_this:
            cmp     al, 0x2     ; Function 02h  - Set VBE Mode
            jnz     @invoke
            mov     si, mode_xlat
            call    patch_mode
            mov     [patchedmode], bx
            
@invoke:
            ; call original handler
            ; here is a trick - since fasm doesn't support org as "move assembly
            ; pointer" we need to build our instruction "by hand"
            pushf
            db      0x9A    ; call dword ?:?
int10ofs    dw      ?
int10seg    dw      ?

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
            jz      patch_modetable
            cmp     al, 0x1     ; Function 01h - Get VBE Mode Information
            jz      patch_modeinfo
            cmp     al, 0x2     ; Function 02h - Set VBE Mode
            jz      patch_modeheight

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
; input:  AX, BX - function numbers; DX - patched VESA mode number (for VESA patchers)
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
            
            ; vga function 0x0 - fix primary stream fifo fetch bug
fix_fetch:
            mov     dx, 0x3D4
            
            call    unlock_extensions
            
            mov     al, 0x90
            out     dx, al
            inc     dx
            in      al, dx
            and     al, 0x7F
            out     dx, al   ; disable fetch
            dec     dx
            
            call    lock_extensions
            
            jmp     done_iret
            
            ; VESA function 0x0 - set out mode table pointer
patch_modetable:
            mov     ax, cs
            mov     word [es:di + VbeInfoBlock.VideoModePtr + 2], ax
            mov     ax, mode_table
            mov     word [es:di + VbeInfoBlock.VideoModePtr    ], ax
            
            jmp     done_iret
            
            ; VESA function 0x1 - patch mode info for 400 pixels height
patch_modeinfo:
            ; check for modenum is patched
            cmp     cx, dx
            jz      done_iret
            
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
            
            jmp     done_iret
            
            ; VESA function 0x2 - set scanline height to 1 
patch_modeheight:
            ; check for modenum < 0x100
            cmp     bx, 0x100
            jb      fix_fetch
            
            ; check for modenum is patched
            cmp     bx, dx
            jz      done_iret
            
            mov     dx, 0x3D4
            
            ; set scanline height = 1
            mov     al, 0x9
            out     dx, al
            inc     dl
            in      al, dx
            and     al, 0x60
            out     dx, al
            
            jmp     done_iret
            

; replace current VESA mode number with other (used for mode info block patching)
; input:  BX - VESA mode number; DS:SI - address of replacement table
; output: BX - patched mode number; SI destroyed          
patch_mode:
            push    ax
@loop:
            lodsb
            cmp     al, 0xFF    ; check for 0xFF terminator
            jz      @done
            cmp     bl, al
            jz      @yep
            inc     si          ; else adjust table
            jmp     @loop
@yep:       lodsb
            mov     bl, al
@done:      pop     ax
            ret                  
            

; mode number patch table (filled by transient path)
; formmat - [src_modenum], [dst_modenum], ... , 0xFF
; only low bytes are stored
mode_xlat   db      (10*2 + 1) dup 0xFF  ; for security reasons
; so why (10*2) + 1? :) well because we can have 320x(200\240) 8\15\16\24\32bpp
; and we need to expand 'em all (+ termination byte ofcourse)

; VESA mode table starts here (with dynamic size)
mode_table:
newint10end:

; START OF TRANSIENT PART
                org     realint10 + (newint10end - int10)
init:
                push    cs
                pop     ds
                xor     bp, bp                ; will be used later
                
                mov     ah, 9
                mov     dx, info_str
                int     21h
                mov     dx, dash_str
                int     21h                   ; display our message
                
                mov     ax, 3510h
                int     21h                   ; get int10h vector
                
                cmp     word [es:bx - (newint10 - newint10id)], "fK"  ; check for signature
                jnz     parse
                inc     bp                    ; if already installed
parse:
                ; parse command line
                mov     si, 80h
                lodsb
                or      al, al
                jz      no_params             ; empty commandline
                
                movzx   cx, al
@parse_loop:
                lodsb
                cmp     al, "?"               ; help
                jz      help
                cmp     al, 40h               ; spaces, slashes and other stuff
                jb      @gottaloop
                cmp     al, 5Fh               ; a-z
                jb      @skip_upcase
                sub     al, 20h               ; upcase these symbols
@skip_upcase:
                cmp     al, "U"               ; release
                jz      release
                cmp     al, "R"               ; release
                jz      release
@gottaloop:     loop    @parse_loop           ; else gotta loop
no_params:
                jmp     build                 ; empty or invalid commandline
                
build:
                ; build it! :)
                mov     ah, 9
                or      bp, bp
                jnz     installed
                
                ; install resident
                mov     ah, 9
                mov     dx, installed_str
                int     21h
                call    install
                call    hujak_info
                jmp     install_done
                
installed:
                cmp     [cs:reset_flag], 0
                jz      already               ; already installed
                mov     dx, reset_str
                int     21h
                jmp     done
                
already:        mov     dx, already_str
                int     21h
                mov     dx, installed_str
                int     21h
                jmp     done
                
install_done:   mov     dx, si
                int     27h
                
                
; SUBPROGRAMS
; release resident from memory
; input: es - resident segment
; output: nope, immediate exit from application
release:        mov     ah, 9                   ; remove us
                or      bp, bp
                jz      cant_release
                
                mov     dx, released_str
                int     21h 
                
                mov     ax, [es:int10seg]
                mov     ds, ax
                mov     dx, [es:int10ofs]
                mov     ax, 2510h
                int     21h                    ; set old int10h
                
                ; now we should release memory, okay? :)
                
                mov     ah, 49h
                int     21h
                jmp     done
                
cant_release:   mov     dx, relfail_str
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

; set mode number patching and mode number table
; если оно заработает, я буду ржать :D
hujak_info:
                ; get vbe info block
                mov     di, vbeinfo_transient
                mov     ax, 0x4F00
                ; осторожно, возможна "проблема курицы и яйца", так что
                ; вместо int 10h здесь будет прямой вызов старого обработчика
                pushf
                call    dword [cs:int10ofs]
                
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
                call    dword [cs:int10ofs]
                
                mov     ax, [es:di + ModeInfoBlock.XResolution]
                cmp     ax, 320
                jnz     @scan_not_target    ; не наш клиент :)
                
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

info_str        db      "S3 VBE fix TSR - by wbc\\bz7 2o.o5.2o16$"
already_str     db      "already $"
installed_str   db      "installed$"
dash_str        db      " - $"
reset_str       db      "reset$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "/U      - release from memory$"
reset_flag      db      0

; some place for mode info block (will be used for initialization)
vbeinfo_transient:
;modeinfo_transient      equ     $ + 512
