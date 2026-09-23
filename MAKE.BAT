rgbasm "PLAYER.ASM" -o "MM5.OBJ"
rgblink "MM5.OBJ" -o "MM5.GB"
rgbfix "MM5.GB" -v -p00
