# Theme presets

Colour presets for `scripts/theme.py --preset <family>[:<variant>]` (`--list-presets` lists them).
Each `<family>.toml` maps one palette family onto the 22 Material roles the matugen templates use
(`[variants.<name>]`, with `mode = "dark"|"light"`). Values come from each project's published
palette; roles marked in a variant's `derived` list were not published as such and were computed
from published colours (mixes, or a text colour moved toward black or white to reach WCAG contrast
4.5:1), as the comment on each line says.

The palettes are third-party works. They are redistributed here under their original licences,
whose notices are reproduced below; the copyright belongs to the holders named.

| Preset | Variants | Licence | Source |
|---|---|---|---|
| Ayu (`ayu`) | `dark` (dark), `mirage` (dark), `light` (light) | Apache-2.0, ayu-theme/ayu-vim (LICENSE text fetched is the unfilled Apache template; copyright holder not stated in it) | https://github.com/ayu-theme/ayu-vim<br>https://raw.githubusercontent.com/ayu-theme/ayu-vim/master/colors/ayu.vim<br>https://raw.githubusercontent.com/ayu-theme/ayu-vim/master/LICENSE |
| Catppuccin (`catppuccin`) | `mocha` (dark), `macchiato` (dark), `frappe` (dark), `latte` (light) | MIT, Copyright (c) 2021 Catppuccin | https://github.com/catppuccin/palette<br>https://raw.githubusercontent.com/catppuccin/palette/main/palette.json |
| Cyberdream (`cyberdream`) | `dark` (dark) | MIT, Copyright (c) 2023 Scott McKendry | https://github.com/scottmckendry/cyberdream.nvim<br>https://raw.githubusercontent.com/scottmckendry/cyberdream.nvim/main/lua/cyberdream/colors.lua<br>https://raw.githubusercontent.com/scottmckendry/cyberdream.nvim/main/LICENSE |
| Dracula (`dracula`) | `dark` (dark) | MIT, Copyright (c) Dracula Theme | https://github.com/dracula/dracula-theme<br>https://raw.githubusercontent.com/dracula/dracula-theme/main/README.md |
| Everforest (`everforest`) | `dark` (dark), `light` (light) | MIT, Copyright (c) 2019 sainnhe | https://github.com/sainnhe/everforest/blob/master/autoload/everforest.vim<br>https://raw.githubusercontent.com/sainnhe/everforest/master/autoload/everforest.vim |
| Gruvbox (`gruvbox`) | `dark` (dark), `light` (light) | MIT/X11 as declared in the repository README (no LICENSE file found at the raw URL, no copyright line); author morhetz | https://github.com/morhetz/gruvbox<br>https://raw.githubusercontent.com/morhetz/gruvbox/master/colors/gruvbox.vim |
| Kanagawa (`kanagawa`) | `wave` (dark), `lotus` (light) | MIT, Copyright (c) 2021 Tommaso Laurenzi | https://github.com/rebelot/kanagawa.nvim<br>https://raw.githubusercontent.com/rebelot/kanagawa.nvim/master/lua/kanagawa/colors.lua<br>https://raw.githubusercontent.com/rebelot/kanagawa.nvim/master/lua/kanagawa/themes.lua |
| Moonfly (`moonfly`) | `dark` (dark) | MIT, Copyright (c) 2017-present vim-moonfly-colors authors | https://github.com/bluz71/vim-moonfly-colors<br>https://raw.githubusercontent.com/bluz71/vim-moonfly-colors/master/autoload/moonfly.vim<br>https://raw.githubusercontent.com/bluz71/vim-moonfly-colors/master/LICENSE |
| Night Owl (`nightowl`) | `dark` (dark) | MIT, Copyright (c) 2018 Sarah Drasner | https://github.com/sdras/night-owl-vscode-theme<br>https://raw.githubusercontent.com/sdras/night-owl-vscode-theme/main/themes/Night%20Owl-color-theme.json<br>https://raw.githubusercontent.com/sdras/night-owl-vscode-theme/main/LICENSE.md |
| Nightfox (`nightfox`) | `nightfox` (dark), `dayfox` (light), `duskfox` (dark) | MIT, Copyright (c) 2021 James Simpson | https://github.com/EdenEast/nightfox.nvim/tree/main/lua/nightfox/palette<br>https://raw.githubusercontent.com/EdenEast/nightfox.nvim/main/lua/nightfox/palette/nightfox.lua<br>https://raw.githubusercontent.com/EdenEast/nightfox.nvim/main/lua/nightfox/palette/dayfox.lua<br>https://raw.githubusercontent.com/EdenEast/nightfox.nvim/main/lua/nightfox/palette/duskfox.lua<br>https://raw.githubusercontent.com/EdenEast/nightfox.nvim/main/LICENSE |
| Nord (`nord`) | `dark` (dark) | MIT, Copyright (c) 2016-present Sven Greb | https://www.nordtheme.com/docs/colors-and-palettes<br>https://raw.githubusercontent.com/nordtheme/nord/develop/src/nord.css |
| One Dark / One Light (Atom) (`one`) | `dark` (dark), `light` (light) | MIT, Copyright (c) 2011-2022 GitHub Inc. (Atom; the palette is published as hsl() values and converted to hex here) | https://github.com/atom/atom/tree/master/packages/one-dark-syntax<br>https://raw.githubusercontent.com/atom/atom/master/packages/one-dark-syntax/styles/colors.less<br>https://raw.githubusercontent.com/atom/atom/master/packages/one-light-syntax/styles/colors.less<br>https://raw.githubusercontent.com/atom/atom/master/LICENSE.md |
| Oxocarbon (`oxocarbon`) | `dark` (dark), `light` (light) | MIT, Copyright (c) 2022 Riccardo Mazzarini (as stated in the LICENSE file of oxocarbon.nvim; the base16-oxocarbon repository shows no licence) | https://github.com/nyoom-engineering/oxocarbon.nvim<br>https://raw.githubusercontent.com/nyoom-engineering/oxocarbon.nvim/main/lua/oxocarbon/init.lua<br>https://raw.githubusercontent.com/nyoom-engineering/base16-oxocarbon/main/base16-oxocarbon-dark.yaml<br>https://raw.githubusercontent.com/nyoom-engineering/base16-oxocarbon/main/base16-oxocarbon-light.yaml<br>https://raw.githubusercontent.com/nyoom-engineering/oxocarbon.nvim/main/LICENSE |
| Poimandres (`poimandres`) | `dark` (dark) | MIT, Copyright (c) 2023 drcmda | https://github.com/drcmda/poimandres-theme<br>https://raw.githubusercontent.com/drcmda/poimandres-theme/main/themes/poimandres-color-theme.json<br>https://raw.githubusercontent.com/drcmda/poimandres-theme/main/LICENSE |
| Rosé Pine (`rosepine`) | `main` (dark), `moon` (dark), `dawn` (light) | MIT, Copyright (c) 2023 Rosé Pine (rose-pine/rose-pine-theme) | https://github.com/rose-pine/neovim/blob/main/lua/rose-pine/palette.lua<br>https://raw.githubusercontent.com/rose-pine/neovim/main/lua/rose-pine/palette.lua |
| Solarized (`solarized`) | `dark` (dark), `light` (light) | MIT, Copyright (c) 2011 Ethan Schoonover | https://github.com/altercation/solarized<br>https://raw.githubusercontent.com/altercation/solarized/master/README.md<br>https://raw.githubusercontent.com/altercation/solarized/master/LICENSE |
| Tokyo Night (`tokyonight`) | `night` (dark), `storm` (dark), `day` (light) | Apache-2.0, folke/tokyonight.nvim (LICENSE text fetched is the unfilled Apache template; copyright holder folke not stated in it) | https://github.com/folke/tokyonight.nvim/tree/main/extras/lua<br>https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/lua/tokyonight_night.lua<br>https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/lua/tokyonight_storm.lua<br>https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/lua/tokyonight_day.lua |

## Licence notes

- MIT: the permission notice is "Permission is hereby granted, free of charge, to any person
  obtaining a copy of this software and associated documentation files, to deal in the software
  without restriction, subject to the copyright notice and this permission notice being included
  in copies or substantial portions of it. The software is provided as is, without warranty of
  any kind." The copyright line for each is in the table above.
- Gruvbox: the repository README declares MIT/X11, but no LICENSE file or copyright line was found
  when the palette was captured. Re-check the repository before redistributing outside this shell.
- Tokyo Night: Apache-2.0. The LICENSE text fetched was the unfilled Apache template, so the
  copyright holder (folke) is not stated in it. A copy of the Apache-2.0 text is at
  <https://www.apache.org/licenses/LICENSE-2.0>.
- Atom One Dark / One Light: MIT, Copyright (c) 2011-2022 GitHub Inc. (Atom). The palette is
  published as `hsl()` values in the two `colors.less` files, not as hex; the hex in `one.toml` is
  those values converted. The Atom UI themes build their panel greys with Less functions
  (`lighten`/`darken`), so the surface ramp in `one.toml` is derived from the syntax background and
  `mono-3`, as the comments say.
- Ayu: taken from ayu-theme/ayu-vim, which lists plain hex per variant. Its LICENSE text is the
  unfilled Apache-2.0 template (no copyright holder or year), like Tokyo Night above. The newer
  ayu-theme/ayu-colors repository (MIT, Copyright (c) Konstantin Pschera) defines its palette as
  generated shade steps, with no hex for most colours, so it was not used; its accent and surface
  colours differ slightly from ayu-vim (for example dark background `0D1017` against `0F1419`).
- Nightfox: MIT, Copyright (c) 2021 James Simpson. Only the base colour of each shade and the
  `bg`/`fg`/`sel`/`comment` entries are used; the bright and dim shades are computed by the plugin
  at runtime. Carbonfox, terafox and nordfox are not included (carbonfox's palette is computed
  from blends in its file and gave no plain hex).
- Oxocarbon: MIT per the oxocarbon.nvim README; its LICENSE file names "Copyright (c) 2022
  Riccardo Mazzarini", recorded as fetched. The nvim palette computes several greys by blending,
  so those come from the explicit hex of the official base16-oxocarbon yaml files (which show no
  licence of their own; the greys are IBM Carbon greys).
- Moonfly: MIT, "Copyright (c) 2017-present vim-moonfly-colors authors" as the LICENSE file reads.
- Night Owl: MIT, Copyright (c) 2018 Sarah Drasner. Only the dark theme is included. The repo
  publishes a VS Code theme, so colours are read off its workbench keys.
- Poimandres: MIT, Copyright (c) 2023 drcmda. Colours are read off the VS Code theme JSON.
- Cyberdream: MIT, Copyright (c) 2023 Scott McKendry (dark palette only).
- Solarized: MIT, Copyright (c) 2011 Ethan Schoonover (the repository LICENSE file; the README
  itself carries no licence line).
- Material Palenight is not included: the Material Theme repository's footer reads "Copyright (c)
  Vira Software. All rights reserved" and no open licence file could be fetched.
