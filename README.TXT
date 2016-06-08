
 < logo placeholder >

            S3VBEFIX - TSR fix for S3 VESA 2.0 BIOS v.0.4.0
       blah-blah copyleft (cl) 2o16 by Artem Vasilev - wbc \\ b-state
 . _ _____________________________________________________________________ _ .

 0x0. disclaimer

    this product is distributed "as is", so if ypu computer was freaked up or
 you have lost all your data I will NOT respond blah-blah, you know :)

 0x1. what the &^*% it is?

    well...since 1997 (afaik) S3 cards are distributed with video BIOS version
 2.0 (starting with S3 Trio64V2/ViRGE-DX and later). It fully supports VESA
 BIOS Extensions 2.0 with LOTS of videomodes (from 320x200 to 1600x1200!),
 linear framebuffer support and mostly bug-free interface (as I know about 90%
 of apps\games\demos\intros work without issues), althought...
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
    Normally FIFO fetch is used in VESA modes for perfomance optimising, but
    video BIOS does not disables it when swithcing back to VGA modes, resulting
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
   You can replase slash with dash "-", also keys are case-insensitive and can
 be expanded, for example:
  "S3VBEFIX.COM /BOOSTER=+ /MEMORY=8" and "S3VBEFIX.COM -b+ -m8" are same.

 0x5. bugs?
   if you got them, contact with me
 
 0x6. plans?
   in TODO.TXT

 0x7. source code?
   in GitHub repository: https://github.com/wbcbz7/S3VBEFIX

 0x8. how to contact me?
   mailto:wbc.bz7(at)gmail.com or telegram (at)wbcbz7 or irc.forestnet.org/#z80
   vogons.org - wbc, phantom.sannata.ru and other sites - wbcbz7

 that's all! :)

 p.s. I HATE WRITING READMES! >_<
