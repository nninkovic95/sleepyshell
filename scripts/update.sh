#!/bin/sh
# The updater's terminal (Updates.qml, "Update now"): a big "UPDATER" banner so the sudo prompt
# does not sit in a bare window, then paru -Syu. In place of fastfetch's CachyOS logo
# (letters only, outline only, bold and italic): JetBrains Mono ExtraBold Italic
# rendered once to a grid and reduced to its edge cells, each drawn with its own letter. Written
# out here, no figlet (no extra packages). 106 columns wide. Blue is palette colour 4, which
# matugen themes in kitty.
printf '\033[1;34m'
cat <<'BANNER'

  UUU    UUU     PPPPPPPPPP      DDDDDDDDD          AAAA        TTTTTTTTTTTT    EEEEEEEEEEE     RRRRRRRRR
 U  U    U U     P  PPPPP  P     D  DDDD  D        A A  A       TTT    TTTT     E  EEEEEEE     R   RRRR  R
 U  U   U  U     P P     P P    D  D    D D       A A A A          T  T         E E            R  R    R R
 U U    U U     P   PPPPP P     D  D    D D      A A  A A          T T         E   EEEEEE      R   RRRRRR
U  U    U U     P  PPPPPPP      D D    D  D     A  A  A A          T T         E  EEEEEE       R  RR  R
U  U   U  U     P P            D  D    D D      A AAAA  A         T  T         E E            R  R  R R
U  U  U  U      P P            D   DDDD DD     A A    A  A        T  T         E  EEEEEE      R R   R  R
 UUUUUUUU      PPPP            DDDDDDDDD      AAAA    AAAA        TTT         EEEEEEEEEE      RRR    RRR

BANNER
printf '\033[0m'
paru -Syu
echo
echo 'Done. Press Enter to close.'
read -r _
