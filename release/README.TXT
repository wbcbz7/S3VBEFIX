
 < logo placeholder >

            S3VBEFIX - TSR fix for S3 VESA 2.0 BIOS v.0.5.2
       blah-blah copyleft (cl) 2o16 by Artem Vasilev - wbc \\ b-state
 . _ _____________________________________________________________________ _ .

 0x0. disclaimer

    this product is distributed "as is", so if your computer was freaked up or
 you have lost all your data I will NOT respond for blah-blah, you know :)

 0x1. what the &^*% it is?

    well...since 1997 (afaik) S3 cards are distributed with video BIOS version
 2.0 (starting with S3 Trio64V2/ViRGE-DX and later). It fully supports VESA
 BIOS Extensions 2.0 with LOTS of videomodes (from 320x200 to 1600x1200!),
 linear framebuffer support and mostly bug-free interface (as I know about 90%
 of apps\games\demos\intros work without issues), although...
    ...yep, some bugs are found and I had written this small TSR :) 

 0x2. system requirements

  - 100% IBM PC/AT compatible personal computer (blahblah :) with PCI\AGP bus
  - 80386 processor or higher
  - about 1kb of free conventional\UMB memory (S3VBEFIX will use about 800-900
    bytes of memory depending on number of available VESA modes)
  - MS-DOS 3.30 or higher
  - and the most important - GRAPHICS CARD with S3 chipset with video BIOS
    version 2.0 or higher (Trio64V+ users - sorry, use UniVBE instead :)
    S3 Trio64V2/DX-GX or ViRGE/DX-GX or later chipset is recommended (should
    work on Trio3D and later also)

 0x3. features

 what S3VBEFIX can do with your card?
  - primary stream fifo fetch fix
    Normally FIFO fetch is used in VESA modes for performance optimizing, but
    video BIOS does not disables it when switching back to VGA modes, resulting
    in various visual glitches
    still can't imagine it? :)
    - run Quake, DO NOT use -stdvid switch, the open console window
    - switch to VGA 320x200 mode (vid_mode 0)
    - type vid_describemodes and find a number for VESA(!) 320x240 mode (if you
      can't find it then your video BIOS is not VBE 2.0 compatible)
    - type vid_mode #, where # - number of VESA 320x240 mode
    - type vid_mode 2 to set 360x200 Mode-X and....
      if you see vertical stripes on right side of screen then you got a bug :)
    - quit Quake and look at right side of text screen, sometimes you can
      notice odd characters and other garbage
    On Trio3D FIFO fetch is enabled in all modes so Mode-X 360-wide modes will
    not work properly in any case.
    S3VBEFIX disables FIFO fetch in all VGA modes so this bug will never occur.
  - new 320x[400/400] 8\15\16\32bpp modes
    basically just a 320x200\240 VESA modes with doublescan disabled. useful
    for some demos which request these resolutions and doesn't work in others.
  - VESA video memory size overriding
    some apps don't like huge amounts of video memory, in this case you can use
    /M[x] key to set "new" memory size. Note that it is not recommended to set
    bigger memory size than available on your card.
  - "set display start" settings
    applications can force waiting for vertical retrace by setting a flag
    (BL=0x80) before calling set display start (AX=0x4F07) function, but some
    apps don't uses it properly. in this case you can use /S[x] key for forcing
    flag status.
  - force RAMDAC CLUT width to 6 bit per channel (Trio3D and later)
    (NB: CLUT means palette RAM in RAMDAC, or well known ports 0x3C6-0x3C9 :)
    Older cards (like ViRGE/DX) are able to use only 6 bits per channel (18 bit
    overall) in RAMDAC CLUT in 8bpp mode, while newer (Trio3D and later) are
    switchable to 8 bit per channel (24 bit total) palette mode, thus giving
    more color shades (256 vs 64) and total colors in palette (16.7m vs 256k).
    Some games (like Terra Nova) do have support for wide (8 bit per channel)
    RAMDAC' CLUT in 8bpp modes but do not work in this mode properly (too dark
    or corrupted colors). In this case use /D6 key to force 18 bit CLUT mode.
    Set /D0 or /D8 to normal operation. Note that /D8 will NOT enable 24 bit
    CLUT mode on ViRGE/DX and older cards since it's not supported by hardware!
  - VESA banked modes booster!
    YEAH, it works like S3SPDUP but doesn't require S3VBE20 for proper work!
    It just enables linear addressing for 0xA0000 window while bank switching
    is still enabled (and this mode is documented in datasheets!!!), therefore
    it will dramatically increase memory speed. On my P200MMX and Trio64V2/DX
    memory write speed was increased from 22 MB/s to incredible 85 MB/s!!! just
    like linear modes it will work REALLY fast!
    Use /B[+/-] to enable\disable booster.

 that's all, read TODO.TXT in GitHub repo (in Russian, sorry :) for other info

 0x4. usage

   usage - [LH] S3VBEFIX.COM <key> <key>...
 keys are:
   - /B[+/-] - enable\disable banked VESA modes booster (disabled by default)
   - /D[x]   - force RAMDAC CLUT width (/D8 - normal, /D6 - force 6 bit)
   - /M[x]   - override memory size in 64kb units (/M16 - 1 MB, /M0 - by BIOS)
   - /S[x]   - 'set display start' mode
               (x = 0 - normal, 1 - force wait for retrace, 2 - force no wait)
   - /R, /U  - release from memory
               DO NOT release S3VBEFIX by using VC or RELEASE, since valid LFB
               address will not be restored if booster was enabled, resulting
               in lockups and crashes while switching to LFB mode.

   - LH      - load TSR in upper memory (recommended if UMB is available)

 examples:
   S3VBEFIX.COM /B+ /S2 - enable booster and force no wait for retrace when
                          set display start function was invoked
   S3VBEFIX.COM /M32    - set memory size to 2 MB

   Once you have installed TSR you can change current settings on the fly by
 running it again with new parameters in command line.
   You can replace slash with dash "-", also keys are case-insensitive and can
 be expanded, for example:
  "S3VBEFIX.COM /BOOSTER=+ /MEMORY=8" and "S3VBEFIX.COM -b+ -m8" are same.

 0x5. internal int10 api and TSR tech info

   pretty simple and silly, mainly used by installation check.
   input:  AX    = 0xCE00
           DX    = 0x656E ('ne') -.
   output: AX    = 0x0000          > (pretty nice, eh? ^.^)
           DX    = 0x6F6B ('ko') -'
           ES:BX = int10 handler entrypoint

   additional available vars:
    word ptr ES:[BX-8] - S3VBEFIX signature = 'fK'
    word ptr ES:[BX-6] - S3VBEFIX version in packed format (0x1234 - v.12.3.4)
    word ptr ES:[BX-4] - internal variables offset (refer to asm source)
    word ptr ES:[BX-2] - inTSR flag (0x0001 if inner int10 call was invoked)
   dword ptr ES:[BX+9] - previous int10 handler pointer

 - if AX and DX are not equal to output values then S3VBEFIX is not loaded.
 - if ES:BX returned by this function != ES:BX returned by int0x21 AX=0x3510
   then S3VBEFIX is NOT last in int10 chain, therefore it CANNOT be unloaded
 - you can temporary disable S3VBEFIX by setting inTSR flag to 0x0001, set it
   to zero for normal function.
 - YES, S3VBEFIX almost always uses self-modifying code for variable settings
   (enable\disable booster, "set display start" flag, RAMDAC width blah-blah)
   and there is no way to get version-independent locations of these vars, so
   it can be changed ONLY by transient part of compatible version of S3VBEFIX.
   maybe some holes in PSP will be used for this purpose.
 - ..ah, yes, currently S3VBEFIX overlaps PSP a bit, starting at offset CS:0x40
   but you can change it in .asm file before compilation, and thus you should
   NOT assume than TSR is always starts from this offset.
 - mode number patch table can destroy VESA mode table during initialization
   if number of 320x??? modes are greater than 10 in total (this will never
   occur on S3 built-in VESA 2.0 interface but DOSBox can crack it, yessss! :)

 0x6. bugs?

 - /M[x] key quirks
   Do NOT set fake memsize bigger than available memory size, otherwise you can
   get nasty crashes and hangups when trying to use double\triple buffer in
   some applications.
   By the way, owners of >=64 MB videocards - memory size will be displayed
   incorrectly, and I can't guarantee that S3VBEFIX will work correctly in
   these cases (but I hope it will :)
  

 fixed bugs:
 - VBETEST.EXE and /M[x] key
   VBETEST from SciTech Display Doctor can crash while attempting to scroll a
   virtual wide\tall screen if /M[x] key is used.
   >>fixed after adding function 0x4F06 fix

   if you got some more bugs, contact with me
 
 0x7. plans?
   in TODO.TXT

 0x8. source code?
   in GitHub repository: https://github.com/wbcbz7/S3VBEFIX

 0x9. how to contact me?
   mailto:wbc.bz7(at)gmail.com or telegram (at)wbcbz7 or irc.forestnet.org/#z80
   vogons.org - wbc, phantom.sannata.ru and other sites - wbcbz7

 0xA. greetings
   - #z80 irc channnel users
   - demoscene pals - well, pretty big list here :)
     diver4d, prof4d, nyuk, kowalski, introspec, n1k-o, nodeus, mmcm, scl^mc,
     mmcm, psndcj, wbr, blackcat\eracg, xlat, buddy, quiet, grachev, vbi, tsl,
     g0blinish, denpopov, dman_pcb, bitl, f0x, manwe and da russian scene!
     sensensthal, hellmood, optimus, orby, branch, mikron, demosplash staff,
     fsqrt, factor6, yerzmyey, scali, trixter, reengine, phoenix, rrrola
     and ofcoz others because we rulez!
   - vogoners - keropi, phil, leileilol, gerwin, vetz, elianda, feipoa and all.
   - hello world! :)

 that's all! :)

 p.s. I HATE WRITING READMES! >_<
