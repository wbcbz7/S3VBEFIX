
 < logo placeholder >

             S3VBEFIX - TSR fix for S3 VESA 2.0 BIOS v.0.6.0
         blah-blah copyleft (cl) 2o16-2o22 by Artem Vasilev - wbcbz7
 . _ _____________________________________________________________________ _ .

 0x0. disclaimer

    this product is distributed "as is", so if your computer was freaked up or
 you have lost all your data I will NOT respond for blah-blah, you know :)

 0x1. what the &^*% it is?

    well...since 1997 (afaik) S3 cards are distributed with video BIOS version
 2.0 (starting with S3 Trio64V2, ViRGE/DX and later). It fully supports VESA
 BIOS Extensions 2.0 with LOTS of video modes (from 320x200 to 1600x1200!),
 linear framebuffer support and mostly bug-free interface (as I know about 90%
 of apps/games/demos/intros work without issues), although...
    ...yep, some bugs are found and I had written this small TSR :) 

    Now, as 6 years have passed, I decided to gather the feedback and update
 the TSR with bugfixes and small neat features. you know :)

 0x2. system requirements

  - 100% IBM PC/AT compatible personal computer (blahblah) with PCI\AGP bus
  - 80386 processor or higher
  - about 1kb of free conventional\UMB memory (S3VBEFIX will use 900-1200
    bytes of memory depending on number of available VESA modes)
  - MS-DOS 3.30 or higher
  - and the most important - GRAPHICS CARD with S3 chipset with video BIOS
    version 2.0 or higher (or 1.2 to use "fake VBE 2.0" feature, see below)
    S3 Trio64V2/DX-GX or ViRGE/DX-GX or later chipset is recommended.

 0x3. features

 what S3VBEFIX can do with your card?
  - primary stream fifo fetch fix
    Normally, FIFO fetch is used in VESA modes to optimize memory performance,
    however due to bugs in S3 video BIOS, it stays active when switching back
    to VGA modes, resulting in various visual glitches.
    test example:
    - run Quake, DO NOT use -stdvid switch, the open console window
    - switch to VGA 320x200 mode (vid_mode 0)
    - type vid_describemodes and find a number for VESA(!) 320x240 mode (if you
      can't find it, then your video BIOS is not VBE 2.0 compatible)
    - type vid_mode #, where # - number of VESA 320x240 mode
    - type vid_mode 2 to set 360x200 Mode-X and....
      if you see vertical stripes on right side of screen then you got a bug
    - quit Quake and look at right side of text screen, sometimes you can
      notice odd characters and other garbage
    On Trio3D FIFO fetch is enabled in all modes so Mode-X 360-wide modes will
    not work properly in any case.
    S3VBEFIX disables FIFO fetch in all VGA modes so this bug will not occur.

  - VESA 320x400/320x480 modes (8/15/16/24/32bpp, depending on capabilities)
    basically just a 320x200/240 VESA modes with doublescan disabled. useful
    for some demos which request these resolutions and don't work in others.
    Note that this option stays active until TSR release, and increases memory
    footprint by 100-200 bytes, depending on VESA mode list length.

  - VESA BIOS Extensions version and video memory size overriding
    some apps don't like huge amounts of video memory, in this case you can use
    /M[x] key to set "new" memory size. Note that it is not recommended to set
    bigger memory size than available on your card.
    Likely, you can "downgrade" VBE version to fix quirky apps, or, rather, 
    "upgrade" it to mimic VBE 2.0 features :) see "fake VBE 2.0" section.

  - Linear Frame Buffer control
    some applications may experience issues while using linear frame buffer
    (LFB) modes, while working fine with bank switching. in that case, you may
    force S3VBEFIX to remove LFB capability from mode info by using /S1 switch
    This is basically equivaent to NOLFB by Ken Silverman, but only marks each
    VESA mode as banked-only, and does not prevent to set LFB mode.

    You can do the opposite, and force LFB capability for every mode, even
    if BIOS does not support it by default. This can be used to implement
    so-called "fake-VBE 2.0", when VBE version is overrided to 2.0 or later,
    and mode LFB capability is forced. S3VBEFIX automatically initializes
    LFB mode in this case if LFB mode is requested. enabled by /S2 switch.
    NOTE: this feature is wildly experimental - see "fake VBE 2.0" section.
    /S0 - use BIOS default LFB handling.

  - LFB mode set fix
    if LFB mode is reuqested, S3VBEFIX first sets the same mode with bank
    switching, preserving other mode flags (like clearing screen), then sets
    LFB mode without screen clearing (OR 0x8000). Additionally, S3VBEFIX makes
    sure that LFB address is correctly set and LFB is enabled on the chip.
    This prevents crashes while booster enabled and permits "fake VBE 2.0".  

  - VBE Get/Set Palette (0x4F09) and Display Window (0x4F05) custom procedures
    standard S3 bank switching routine is incompatible with booster, so it
    needs to be reimplemented.
    Get/Set Palette override is used for "fake VBE 2.0" feature to make VBE
    runtime implementation more compatible with some games like Quake (it 
    always updates palette via VBE call, even if adapter is VGA compatible),
    enabled by /Q switch (active until release!)

  - VESA maximum video page count limit
    some applications (Build Engine titles are known examples) seem to not
    function properly with double/triple buffering, or misinterpret video
    page count field in VESA mode info as signed byte. By default, S3VBEFIX
    limits page count to 127, you may override it via /P[x] switch

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
    Use /B[+/-] to enable/disable booster.
    NOTE: this feature does not work on S3 Savage cards!

    S3 Trio3D/Savage only features:
  - force RAMDAC CLUT width to 6 bit per channel (Trio3D and later)
    (NB: CLUT means palette RAM in RAMDAC, or well known ports 0x3C6-0x3C9 :)
    Older cards (like ViRGE/DX) are able to use only 6 bits per channel (18 bit
    overall) in RAMDAC CLUT in 8bpp mode, while newer (Trio3D and later) are
    switchable to 8 bit per channel (24 bit total) palette mode, thus giving
    more color shades (256 vs 64) and total colors in palette (16.7m vs 256k).
    Some games (like Terra Nova) do have support for wide (8 bit per channel)
    RAMDAC' CLUT in 8bpp modes but cannot work in this mode properly (too dark
    or corrupted colors). In this case use /D6 key to force 18 bit CLUT mode.
    Set /D0 or /D8 to normal operation. Note that /D8 will NOT enable 24 bit
    CLUT mode on ViRGE/DX and older cards since it's not supported by hardware!

  - Hi/TrueColor (15/16/24/32bpp) gamma correction
    VBE 2.0/3.0 permits color gamma ramp to be user defined if RAMDAC supports
    it and VBE implementation exposes gamma capability in mode info block.
    If this option is enabled, linear gamma ramp is initialized each mode set,
    plus you can prepare custom gamma ramp (8 bit per channel) and upload it 
    just like regular VGA palette - refer to VBE spec for more info.

 that's all, read TODO.TXT in GitHub repo (in Russian, sorry :) for other info

 0x4. usage

   usage - [LH] S3VBEFIX.COM <key> <key>...
 keys are:
   - /M[x]   - override memory size in 64kb units (/M16 - 1 MB, /M0 - by BIOS)
   - /P[x]   - limit max. video page count (/P1 - max. 1 page, /P0 - default)
   - /V[x]   - force reported VBE version (/V102 - 1.2, /V200 - 2.0)
   - /Q      - replace VBE Get/Set Palette (0x4F09) (until release!)
   - /X      - add 320x400 and 320x480 VESA modes   (until release!)
   - /L[x]   - linear frame buffer control
               (/L0 - normal, /L1 - off, /L2 - force on)
   - /S[x]   - 'set display start' mode
   -           (/S0 - normal, /S1 - force wait for retrace, /S2 - force no wait)
   - /B[+/-] - enable/disable banked VESA modes booster (not Savage)
   - /I      - hook INT 6D in addition to INT 10, disables release function!
   - /R, /U  - release from memory
               DO NOT release S3VBEFIX by using VC or RELEASE, since valid LFB
               address will not be restored if booster was enabled, resulting
               in lockups and crashes while switching to LFB mode.

    S3 Trio3D/Savage only:
   - /D[x]   - force RAMDAC CLUT width (/D8 - normal, /D6 - force 6 bit)
   - /G[+/-] - enable Hi/TrueColor gamma correction

   - LH      - load TSR in upper memory (recommended if UMB is available)

 examples:
   S3VBEFIX.COM /B+ /S2 - enable booster and force no wait for retrace when
                          set display start function was invoked
   S3VBEFIX.COM /M32    - set memory size to 2 MB

   NOTE: /Q and /X keys increase TSR memory usage and active until release.
   Once you have installed TSR you can change current settings on the fly by
 running it again with new parameters in command line.
   You can replace slash with dash "-", also keys are case-insensitive and can
 be expanded, for example:
  "S3VBEFIX.COM /BOOSTER=+ /MEMORY=8" and "S3VBEFIX.COM -b+ -m8" are same.

 0x5. fake VBE 2.0

   NOTE: this is a dirty hack allowing to enable partial VBE 2.0 support on 
   VBE 1.2 capable S3 video BIOSes (primarily, Trio64/V+/original ViRGE).
   it seems to work with most applications (Quake, Duke3D, some apps/demos)
   but it might fail in more advanced cases. USE AT OWN RISK!
   If possible, use UniVBE or S3VBE20 instead :)

   Since S3VBEFIX now supports VBE version override and LFB control, it is
   possible to force LFB version to 2.0 or later, and enable LFB capability.
   This alone is usually enough to run most LFB applications, but some 256
   color games (like Quake) use VBE Get/Set Palette (0x4F09) function, which
   is not present in VBE 1.2. You can install custom 0x4F09 procedure with 
   /Q switch, but it has to be done during installation.

   To activate fake VBE 2.0 mode, run S3VBEFIX /V200 /L2 /Q

   NOTE: S3VBEFIX does NOT initialize VBE 2.0-specific controller info fields
   like adapter name/revision/vendor string pointers, leaving them at
   whatever BIOS has returned (usually zeroes, so these pointers are NULL).
   Some applications may not like this. Moreover, SciTech Display Doctor's
   VBETEST may hang or crash during mode test.
   Besides that, no additional VESA modes are added (except for /X switch but
   those 320x400 / 320x480 modes are hacked from existing 320x200 / 320x240 
   modes, and if BIOS does not provide them, then /X switch is useless).
   VBE 2.0 protected mode services (0x4F0A) are also not inplemented.

 0x6. internal int10 api and TSR tech info

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

 0x7. bugs?

 - /M[x] key quirks
   Do NOT set fake memsize bigger than available memory size, otherwise you can
   get nasty crashes and hangups when trying to use double\triple buffer in
   some applications.
   By the way, owners of >=64 MB videocards - memory size will be displayed
   incorrectly, and I can't guarantee that S3VBEFIX will work correctly in
   these cases (but I hope it will :)
 - VBETEST
   uses either undocumented API or manages to bypass S3VBEFIX hooks, resulting
   in some features like CLUT width or SDS flags being not working properly.

 fixed bugs:
 - VBETEST.EXE and /M[x] key
   VBETEST from SciTech Display Doctor can crash while attempting to scroll a
   virtual wide\tall screen if /M[x] key is used.
   >>fixed after adding function 0x4F06 fix
 - Chasm: The Rift Runtime Error 216 while VESA mode set
   >>fixed bank procedure

   if you got some more bugs, contact with me
 
 0x8. plans?
   in TODO.TXT. basically this code base is 6 years old, and i perhaps will
   stop fiddling with it due to numerous trics and bugs asscciated with it.
   perhaps i'll fork some common features like VBE version/memory/max. page
   and make a generic TSR to fix common VESA BIOS bugs, leaving chip-specific
   stuff on separate TSR.
   idk anyway :)

 0x9. source code?
   in GitHub repository: https://github.com/wbcbz7/S3VBEFIX

 0xA. how to contact me?
   mailto:   wbcbz7.at(at)gmail.com 
   telegram: (at)wbcbz7
   discord:  wbcbz7#3519, also i'm active on https://discord.io/demoscene
   vogons.org - wbc, phantom.sannata.ru and other sites - wbcbz7

 that's all! :)

 p.s MAKE FUN, NOT "SPECIAL OPERATIONS", fuck the useless putin's war!
