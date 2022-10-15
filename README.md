# Playwrite

Experimental word processor for Playdate. Requires a dedicated keyboard adapter, see [playwrite-dock](https://www.github.com/t0mg/playwrite-dock).

**Overview thread with demo videos: https://twitter.com/t0m_fr/status/1576949261849149440**

Playwrite is a siple text editor for [Playdate](https://play.date). This console doesn't normally support keyboards or any kind of USB accessory, but the Playwrite project uses a bespoke dock relying on USB serial to proxy the input commands to the Plalydate.

This repository is dedicated to the software to be sideloaded on Playdate; it contains the Lua code for the Playwrite app. It's pretty much useless on its own without the dock.
For source and documentation on how to build the playdate dock, see [the other repository](https://www.github.com/t0mg/playwrite-dock).

## Features & future development

The app is a proof of concept but quite usable as is, with cursor movement, insertion and deletion support. It has menu option to load, save and export but currenly only supports a single document (no file naming options). The export function flattens the Lua table of the working document into an `export.txt` file that can then be retrieved in USB data disk mode (Settings > System > Reboot to Data Disk).

Possible improvement ideas:

- supporting more than one file, via a dedicated load/save menu
- font type and size options (quite trivial)
- text styling eg bold, italic, size (much less trivial)
- exporting to the Playwrite dock (in the SD card of the Teensy)

## Credits

The Playwrite app uses

- [PDFontTool](https://github.com/abenokobo/PDFontTool) by abenokobo
- [Noto Sans font](https://fonts.google.com/noto/specimen/Noto+Sans)