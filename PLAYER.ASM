include "MUSIC.INC"
include "FUNCTION.ASM"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;ROM header
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;$0000-$003F: Reset vectors (unused)
SECTION "Reset 1", ROM0[$0000]
RS_00:
    jp $0100
SECTION "Reset 2", ROM0[$0008]
RS_08:
    jp $0100
SECTION "Reset 3", ROM0[$0010]
RS_10:
    jp $0100
SECTION "Reset 4", ROM0[$0018]
RS_18:
    jp $0100
SECTION "Reset 5", ROM0[$0020]
RS_20:
    jp $0100
SECTION "Reset 6", ROM0[$0028]
RS_28:
    jp $0100
SECTION "Reset 7", ROM0[$0030]
RS_30:
    jp $0100
SECTION "Reset 8", ROM0[$0038]
RS_38:
    jp $0100
SECTION "V-Blank IRQ", ROM0[$0040]
RS_DRAW:
    reti
SECTION "STAT", ROM0[$0048]
RS_STAT:
    reti
SECTION "Timer", ROM0[$0050]
RS_TIMER:
    reti
SECTION "Serial", ROM0[$0058]
RS_SERIAL:
    reti
SECTION "Joypad Vector", ROM0 [$0060]
RS_JOYPAD:
    reti
;$0100-$0103: Entry point
SECTION "Startup", ROM0 [$0100]
 nop
 jp Main

;$0104-$0133: Nintendo logo
db $CE, $ED, $66, $66
db $CC, $0D, $00, $0B
db $03, $73, $00, $83
db $00, $0C, $00, $0D
db $00, $08, $11, $1F
db $88, $89, $00, $0E
db $DC, $CC, $6E, $E6
db $DD, $DD, $D9, $99
db $BB, $BB, $67, $63
db $6E, $0E, $EC, $CC
db $DD, $DC, $99, $9F
db $BB, $B9, $33, $3E

;$0134-$0142: Title
db "AUDIO PLAYER"
ds 3

;$0143: GBC compatibility flag
db $00                              ;Not GBC

;$0144-$0145: Manufacturer code
db "SW"								;Swift

;$0146: SGB compatibility flag
db $00                              ;Not SGB

;$0147: Cartridge type
db $19                              ;MBC5

;$0148: Cartridge size
db $01                              ;512 KBit

;$0149: Cartridge RAM
db $00                              ;None

;$014A: Destination code
db $01                              ;Non-Japanese

;$014B: Manufacturer code (old)
db $33                              ;See new

;$014C: ROM version
db $00                              ;V1.0

;$014D: Header checksum
db $00                              ;(Fill in)

;$014E: Global checksum
db $00, $00                         ;(Fill in)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Main section
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION "MainCode", ROM0[$0400]

Main:

.ResetScrollXY
	xor a							;Set register A to 0 with exclusive OR
	ld [rSCX], a					;Set SCX to 0
	ld [rSCY], a					;Set SCY to 0

.WaitVBL							;Wait for V-Blank (145 frames)
	ld a, [rLY]
	cp 144
	jr nz, .WaitVBL
	
.ScreenOff
	xor a
	ld [rLCDC], a
	
.SetPalette
	ld a, %11100100					;3, 2, 1, 0
	ld [rBGP], a					;Set background palette
	
CopyData:

.InitFont							;Load font tiles
	ld hl, $8300					;Address in VRAM
	ld de, FontTiles				;Start offset of tile data
	ld bc, FontTilesEnd - FontTiles	;Total size of tile data
	call .CopyFont
	
.CleanUp							;"Clean up" the screen's tile data
	ld hl, $9800
	ld bc, $9FFF - $9800
	call ClearScreen
	
.InitText							;Display the text
	ld hl, $9860					;Address in VRAM (start of BG tilemap)
	ld de, TitleMessage
	ld bc, TitleMessageEnd - TitleMessage
	call CopyText
	
	ld hl, $98A0
	ld de, Instructions
	ld bc, InstructionsEnd - Instructions
	call CopyText
	
	ld hl, $9960
	ld de, Tags
	ld bc, TagsEnd - Tags
	call CopyText
	
.CleanUpWRAM						;"Clean up" WRAM
	ld hl, $C000
	ld bc, $DFFF - $C000
	call ClearZero
	
.InitMusic							;Initialize the sound engine
	ld a, AudioBank1				;Map the first audio bank before calling into it
	ld [MapBank], a					;(MBC5 happens to power up on bank 1, but don't rely on it)
	call SwitchBank
	ld a, MUS_STAGE_SELECT
	ld hl, MusVar
	ld [hl], a
	push af
	call AudioROM+$06				;Call sound init routine
	pop af
	ld a, SFX_SHOT
	ld hl, SFXVar
	ld [hl], a

.ResetInput							;Reset controller input state
	xor a
	ld [CurInputA], a

.ScreenOn
	ld a, %10010001					;Turn on screen and BG layer, set bank to $8000
	ld [rLCDC], a
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Main loop
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.MainLoop
	ld a, [rLY]						;Wait for V-Blank (145 frames)
	cp 144
	jr nz, .MainLoop
	call AudioROM+$00				;Play music+SFX
	call DisplaySong				;Display music and SFX text
	call DisplaySFX
	call CheckInput					;Check D-Pad input
	call CheckInputButtons			;Check other buttons

jr .MainLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.Copy								;Multi-purpose data copy function
	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .Copy
	ret
	
.CopyFont							;Copy 1-bit font tile data
	ld a, [de]
	ld [hli], a						;Load twice to convert to 2-bit
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .CopyFont
	ret	

;Specialized text data copy function	
CopyText:
	ld a, b							;Check if length is remaining
	or c
	jr z, .CopyDone					;If so, then go to end
	
.CopyLoop
	ld a, [de]						;Get current byte from source
	inc de
	dec bc
	or a							;Check if the value is 0
	jr nz, .WriteByte				;If not, then write to VRAM
	
	ld a, h							;Otherwise, advance to next "row"
	and a							;Get sign
	ld a, l
	and a, $1F						;Get current position in row ($20 = length of row)
	cp $14							;Check if tile is off-screen ($14+ tiles = off-screen)					
	jr nc, .SkipAdvance				;If so, then don't add remainder

	push bc							;Otherwise, add to total position
	push de
	ld b, a
	ld a, $20
	sub b
	pop bc
	
	add l
	ld l, a
	pop bc
	jr nc, .NoCarryAdd
	inc h
.NoCarryAdd
	jr .CheckDone
	
.SkipAdvance						;Don't add remainder
	xor a
	
.WriteByte
	add a, $10						;Convert ASCII values to tile values by adding $10 to each character
	ld [hli], a						;Then write to VRAM
	jr .CheckDone

.CheckDone							;Check if done copying
	ld a, b
	or c
	jr nz, .CopyLoop
	
.CopyDone
	ret
	
CopyMap:

.StartRow
	push bc
	
.CopyRow
	ld a, [de]
	ld [hli], a
	inc de
	dec c
	jr nz, .CopyRow
	
.EndRow
	ld a, [$C070]					;Get tile skip amount (from RAM as we ran out of registers)
	push bc
	ld b, a
	ld a, l
	add b
	pop bc
	jr nc, .NextRow
	inc h

.NextRow
	ld l, a
	pop bc
	dec b
	jr nz, .StartRow
	ret

ClearScreen:						;Fill in both tilemaps with white space
	ld a, $30
	ld [hli], a
	dec bc
	ld a, b
	or c
	jr nz, ClearScreen
	ret
	
ClearZero:							;General cleanup function
	ld a, 0
	ld [hli], a
	dec bc
	ld a, b
	or c
	jr nz, ClearZero
	ret

LoadNewSong:						;Start a new song
	ld hl, MusVar					;Load the current song number into A
	ld a, [hl]
	
	add a							;Multiply number by 2
	ld e, a							;Get corresponding bank and index from table
	ld d, 0
	ld hl, BankSongNumMap
	add hl, de
	ld a, [hli]
	ld [MapBank], a
	ld a, [hli]
	ld [MapNum], a
	call SwitchBank					;Switch to the correct bank
	call AudioROM+$06				;Re-initialize audio
	
	ld a, [MapNum]					;Get the index stored in RAM
	push af
	call AudioROM+$03				;Call song load routine
	ld a, [CurInputB]
	ld d, a
	pop af
	ret
	
LoadNewSFX:							;Start a new sound effect
	ld hl, SFXVar					;Load the current song number into A
	ld a, [hl]

	ld e, a							;Get corresponding index from table
	ld d, 0
	ld hl, SFXNumMap
	add hl, de
	ld a, [hl]
	ld [MapSFX], a
	
	ld a, [MapSFX]					;Get the index stored in RAM
	push af
	call AudioROM+$03				;Call sound effect load routine
	ld a, [CurInputB]
	ld d, a
	pop af
	ret
	
DisplaySong:
	;Display current music number
	ld a, [MusVar]
	ld de, $9965
	ld c, a
	
	and %11110000					;First, get the upper 4 bits and convert to ASCII (hex)
	swap a
	cp $0A
	jr nc, .ConvertToLetter	
	add $40							;Convert to a number if less than $A (10)
	jp .DisplaySong2
.ConvertToLetter
	add $47
.DisplaySong2
	ld [de], a
	
	inc de
	ld a, c
	and %00001111
	cp $0A
	jr nc, .ConvertToLetter2
	add $40
	jp .DisplaySong3
.ConvertToLetter2
	add $47
.DisplaySong3
	ld [de], a
	
	
	
;Display the title of the current song

	ld hl, MusTitles						;First, get start of music titles
	
	ld b, 0									;Check if song number is 0
	ld a, [MusVar]	
	cp 0
	jr z, .StartCopyZero					;If so, then copy without adding
	ld c, a									;Otherwise, "multiply" 12 to get the offset
	ld de, 12
	
.Add12Title									;Repeat adding 12 until reaching current number
	add hl, de
	dec bc
	ld a, b
	or c
	jr nz, .Add12Title
	
	ld a, l
	ld e, a
	ld a, h
	ld d, a
	jr .StartCopyTitleData
	
.StartCopyZero								;Get copy offset from the first entry
	ld de, MusTitles

.StartCopyTitleData							;Copy the title data from the current offset
	ld hl, $9968
	ld bc, 12
	jr .CopyTitleData
	
	ld hl, $9968
	ld bc, 12
	
.CopyTitleData								;Copy the song title to VRAM and convert mapping
	ld a, [de]
	add $10
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .CopyTitleData
	ret
	
DisplaySFX:
	;Display current sound effect number
	ld a, [SFXVar]
	ld de, $9985
	ld c, a
	
	and %11110000					;First, get the upper 4 bits and convert to ASCII (hex)
	swap a
	cp $0A
	jr nc, .ConvertToLetter	
	add $40							;Convert to a number if less than $A (10)
	jp .DisplaySFX2
.ConvertToLetter
	add $47
.DisplaySFX2
	ld [de], a
	
	inc de
	ld a, c
	and %00001111
	cp $0A
	jr nc, .ConvertToLetter2
	add $40
	jp .DisplaySFX3
.ConvertToLetter2
	add $47
.DisplaySFX3
	ld [de], a
	
	
	
;Display the title of the current SFX
	ld hl, SFXTitles						;First, get start of SFX titles
	
	ld b, 0									;Check if SFX number is 0
	ld a, [SFXVar]
	cp 0
	jr z, .StartCopyZero					;If so, then copy without adding
	ld c, a									;Otherwise, "multiply" 12 to get the offset
	ld de, 12
	
.Add12Title									;Repeat adding 12 until reaching current number
	add hl, de
	dec bc
	ld a, b
	or c
	jr nz, .Add12Title
	
	ld a, l
	ld e, a
	ld a, h
	ld d, a
	jr .StartCopyTitleData
	
.StartCopyZero								;Get copy offset from the first entry
	ld de, SFXTitles

.StartCopyTitleData							;Copy the title data from the current offset
	ld hl, $9988
	ld bc, 12
	jr .CopyTitleData
	
.CopyTitleData								;Copy the SFX title to VRAM and convert mapping
	ld a, [de]
	add $10
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .CopyTitleData
	ret
	
CheckInput:									;Check for D-Pad input
	ld a, %00100000
    ldh [rJOYP], a
    ldh a, [rJOYP]
    ldh a, [rJOYP]							;Multiple read to prevent input lag
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
	cpl
    and %00001111
	ld d, a
	
	ld a, %00110000
    ldh [rJOYP], a
		
    ld a, d
	cp 0								;If input, then continue
	jr nz, .CheckInput2
	ld [CurInputA], a					;Otherwise, then set input variable and return
	jp InputRet
		
.CheckInput2
	ld a, [CurInputA]					;Check if variable is 0
	cp 0
	jp nz, InputRet						;If so, then set variable
		
	ld a, d
	ld [CurInputA], a

.CheckRight
	ld a, d								;First, check for right
	and JOYP_RIGHT
	cp 0
	jr z, .CheckLeft					;If not pressed, then check next button
		
	ld a, [MusVar]						;Check current music number
	cp a, MUS_CNT - 1					;If maximum, then reset to 0 (wrap around)
	jr z, .WrapSong
.IncSong								;Otherwise, increment song number
	inc a
	ld [MusVar], a
	jr .CheckLeft

.WrapSong								;Reset song number to 0 (wrap around)
	xor a
	ld [MusVar], a
		
.CheckLeft								;Then, check for left
	ld a, d
	and JOYP_LEFT
	cp 0
	jr z, .CheckUp						;If not pressed, then check next button
		
	ld a, [MusVar]						;Check current music number
	cp 0								;If 0, then reset to maximum (wrap around)
	jr z, .WrapSong2
		
.DecSong								;Otherwise, decrement song number
	dec a
	ld [MusVar], a
	jr .CheckUp

.WrapSong2								;Reset song number to maximum (wrap around)
	ld a, MUS_CNT - 1
	ld [MusVar], a
	
.CheckUp
	ld a, d								;Then, check for up
	and JOYP_UP
	cp 0
	jr z, .CheckDown					;If not pressed, then check next button
		
	ld a, [SFXVar]						;Check current sound effect number
	cp a, SFX_CNT - 1					;If maximum, then reset to 0 (wrap around)
	jr z, .WrapSFX
.IncSFX									;Otherwise, increment sound effect number
	inc a
	ld [SFXVar], a
	jr .CheckDown
	
.WrapSFX								;Reset sound effect number to maximum (wrap around)
	xor a
	ld [SFXVar], a
	
.CheckDown								;Finally, check for left
	ld a, d
	and JOYP_DOWN
	cp 0
	jr z, InputRet						;If not pressed, then return
		
	ld a, [SFXVar]						;Check sound effect music number
	cp a, 0								;If 0, then reset to maximum (wrap around)
	jr z, .WrapSFX2
		
.DecSFX									;Otherwise, decrement sound effect number
	dec a
	ld [SFXVar], a
	jr InputRet

.WrapSFX2								;Reset sound effect number to maximum (wrap around)
	ld a, SFX_CNT - 1
	ld [SFXVar], a
	
InputRet:								;Return from the routine
	ret
	
	
CheckInputButtons:						;Now check other buttons
	ld a, %00010000
    ldh [rJOYP], a
    ldh a, [rJOYP]
    ldh a, [rJOYP]						;Multiple read to prevent input lag
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    ldh a, [rJOYP]
	cpl
    and %00001111
		
    ld d, a
	cp 0								;If input, then continue
	jr nz, .CheckInput4
	ld [CurInputB], a					;Otherwise, then set input variable and return
	jp InputRet
	
.CheckInput4
	ld a, [CurInputB]					;Check if variable is 0
	cp 0
	jp nz, InputRet						;If so, then set variable
		
	ld a, d
	ld [CurInputB], a

.CheckStart								;First, check for start
	ld a, d
	and JOYP_START
	cp 0
	jr z, .CheckSelect					;If not pressed, then check next button
		
	call LoadNewSong					;Play the current song number

.CheckSelect							;Then, check for select
	ld a, d
	and JOYP_SELECT
	cp 0
	jr z, InputRet2						;If not pressed, then return
		
	call LoadNewSFX						;Play the current sound effect number
	
	jp InputRet2

InputRet2:								;Return from the routine				
	ret
	
SwitchBank:								;Switch the current bank
	ld a, [MapBank]						;Load bank number from RAM
	ld [$2000], a
	
	cp 1
	ret
	
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;"Strings"
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Strings", ROM0[$2000]

TitleMessage:							;Game title
	db "MEGA MAN 5", 0
TitleMessageEnd:

Instructions:							;Instructions for buttons
	db "START = PLAY MUSIC", 0
	db "L/R = TOGGLE MUSIC", 0
	db "SELECT = PLAY SFX", 0
	db "U/D = TOGGLE SFX", 0
InstructionsEnd:
Tags:									;Music and SFX tags
	db "MUS: ", 0
	db "SFX: ", 0
TagsEnd:
MusTitles:								;Music titles
	db "STAGE SELECT"
	db "WILY INTRO  "
	db "URANUS      "
	db "RUSH SPACE  "
	db "NEPTUNE     "
	db "CUTSCENE ALT"
	db "BOSS        "
	db "SATURN      "
	db "MERCURY     "
	db "CUTSCENE    "
	db "MARS        "
	db "JUPITER     "
	db "VENUS ALT   "
	db "PLUTO       "
	db "WILY        "
	db "INTRO 1     "
	db "STAGE START "
	db "GAME OVER   "
	db "VICTORY     "
	db "FINLVICT ALT"
	db "GET WEAPON  "
	db "END GAME    "
	db "VICTORY ALT "
	db "TITLE ALT   "
	db "TITLE       "
	db "TERRA       "
	db "SHOP        "
	db "LIGHT INTRO "
	db "INTRO 2     "
	db "PASSWORD    "
	db "SUNSTAR     "
	db "FINALVICTORY"
	db "VENUS       "
MusTitlesEnd:
SFXTitles:								;Sound effect titles
	db "SHOT        "
	db "CHARGESHOT S"
	db "CHARGESHOT L"
	db "CHARGE      "
	db "LAND        "
	db "EXTRA LIFE  "
	db "PLAYER HIT  "
	db "PLYR EXPLODE"
	db "ENEMY HIT   "
	db "BOSS EXPLODE"
	db "HEALTH      "
	db "SHING       "
	db "SELECT      "
	db "PAUSE       "
	db "TELEPORT IN "
	db "TELEPORT OUT"
	db "DEFLECT     "
	db "DOOR        "
	db "EXPLODE     "
	db "SPLASH      "
	db "WILY UFO    "
	db "ERROR       "
	db "ACCEPT      "
	db "TEXT        "
	db "FORTRS EXPLD"
	db "RAIN FLUSH  "
	db "HELICOPTER  "
	db "CANNON      "
	db "GET WEAPON  "
	db "STOMP       "
	db "MACHIN EXPLD"
	db "TANK MISSILE"
	db "PROTO MAN   "
	db "BIG SHOT 1  "
	db "BIG SHOT 2  "
	db "SHOT ALT    "
	db "CHARGE ALT 1"
	db "CHARGE ALT 2"
	db "CHARGE ALT 3"
	db "GET WPN ALT "
	db "RUSH CHARGE "
	db "RUSH BLAST  "
	db "RUSH MOTOR  "
	db "SUPERMEGAARM"
	db "TANGO       "
	db "BREAK DASH  "
	db "ELCTRC SHCK1"
	db "ELCTRC SHCK2"
	db "PHOTON MISSL"
	db "GRAB BUSTER "
	db "SALT WATER  "
	db "BUBBLE BOMB "
	db "SPCLEXPLSION"
	db "STAR EXPLODE"
	db "ENEMY SHOT  "
	db "TIME FREEZE "
	db "TELEPORTOUTA"
	db "BUBBLE ENEMY"
	db "TANGO HIT   "
	db "SPARK CHASR1"
	db "SPARK CHASR2"
	db "BLACK HOLE 1"
	db "BLACK HOLE 2"
	db "EXPLODE BLST"
	db "LASER       "
	db "PLATFRM EXPL"
SFXTitlesEnd:

BankSongNumMap:
	db $01, $59
	db $01, $5B
	db $01, $5C
	db $01, $5D
	db $01, $5E
	db $01, $5F
	db $01, $60
	db $01, $61
	db $01, $62
	db $01, $63
	db $01, $64
	db $01, $65
	db $01, $66
	db $01, $67
	db $01, $6C
	db $02, $6D
	db $02, $6E
	db $02, $6F
	db $02, $70
	db $02, $71
	db $02, $72
	db $02, $73
	db $02, $74
	db $02, $75
	db $02, $76
	db $02, $77
	db $02, $78
	db $02, $79
	db $02, $7A
	db $02, $7B
	db $02, $7C
	db $02, $7D
	db $02, $7E
BankSongNumMapEnd:
SFXNumMap:
	db $0D,$0E,$0F,$10,$11,$12,$13,$14
	db $15,$16,$17,$18,$19,$1A,$1B,$1C
	db $1D,$1E,$1F,$20,$21,$22,$23,$24
	db $25,$26,$27,$28,$29,$2A,$2B,$2C
	db $2D,$2E,$2F,$30,$31,$32,$33,$34
	db $35,$36,$37,$38,$39,$3A,$3B,$3C
	db $3D,$3E,$3F,$40,$41,$42,$43,$44
	db $45,$46,$47,$4C,$4D,$4E,$4F,$50
	db $51,$52
SFXNumMapEnd:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Font data
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Graphics", ROM0[$3000]

FontTiles:
	incbin "FONT.DAT"				;Graphics tile data file for the font (1-bit)
FontTilesEnd:

include "MM5A.ASM"					;Audio code and data from Mega Man 5 - bank 1
include "MM5B.ASM"					;Audio code and data from Mega Man 5 - bank 2

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Variables", WRAM0[$C000]
MusVar: ds 1						;Current music number
SFXVar: ds 1						;Current sound effect number
MapBank: ds 1						;Bank mapping for song
MapNum: ds 1						;Number mapping for each song
MapSFX: ds 1						;Number mapping for each SFX

CurInputA: ds 1						;D-PAD input
CurInputB: ds 1						;Other button input
CurBank: ds 1						;Bank number