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
            jmp     short init
        
            ; start of resident part
realint10:
            org     resident_start
int10:
newint10id  dw  "fK"
            ; resident entry point
newint10:
            ; save original ax\bx\cx\dx
            mov     [cs:saveAX], ax
            ;mov     [cs:saveBX], bx
            ;mov     [cs:saveCX], cx
            ;mov     [cs:saveDX], dx
        
            ; check for calling function and doing some conditional branch magic
            ; should be used for patching arguments before INT10h call
        
            ; call original handler
            pushf
            ; here is a trick - since fasm doesn't support org as "move assembly
            ; pointer" we need to build our instruction "by hand"
            db  0x9A ; call dword ?:?
int10ofs    dw  ?
int10seg    dw  ?

            ; do the patch (NB: some regs were changed so keep in mind)
            push    ax
            ; and once again this trick (fffuck!)
            db      0xB8    ; mov ax, ?
saveAX      dw      ?

            test    ah, 0
            jz      fix_fifo_fetch
        
done_iret:
            ; all done, do the IRET
            pop     ax
            iret
        
unlock_extensions:
            ; unlock S3 extensions
            ; input: dx = 0x3D4
            mov    ax, 0x4838
            out    dx, ax
            mov    ax, 0xA539
            out    dx, ax
            ret
lock_extensions:
            ; lock S3 extensions
            ; input: dx = 0x3D4
            mov    ax, 0x0038
            out    dx, ax
            mov    ax, 0x0039
            out    dx, ax
            ret
            
            ; vga function 0x0 - fix primary stream fifo fetch bug
fix_fifo_fetch:
            push   ax
            push   dx
        
            mov    dx, 0x3D4
            
            call   unlock_extensions
            
            mov    al, 0x90
            out    dx, al
            inc    dl
            in     al, dx
            and    al, 0x7F
            out    dx, al   ; disable fetch
            dec    dl
            
            call   lock_extensions
            
            pop    dx
            pop    ax
        
            jmp    done_iret
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
                call    install
                mov     ah, 9
                mov     dx, installed_str
                int     21h
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
                
install_done:   mov     dx, newint10end
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