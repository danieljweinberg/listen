# listen
Automatically record instrument audio and MIDI

![GitHub](https://img.shields.io/github/license/danieljweinberg/listen?color=3d9fbf&style=plastic)
![GitHub last commit](https://img.shields.io/github/last-commit/danieljweinberg/listen?style=plastic)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/danieljweinberg/listen?color=dea92c&style=plastic)
![GitHub top language](https://img.shields.io/github/languages/top/danieljweinberg/listen?color=3aa64c&style=plastic)

After years of composing music on my digital piano, and recording it only sometimes, I realized that I make some of my best work when I don't even think to record. That's why I designed this program. It was written for a Raspberry Pi connected via USB Audio Interface to the instrument. Once started, _listen_ will run in the background, automatically saving both a MP3 and a MIDI for each stretch of time that the attached instrument is played. _listen_ can also send or receive an audio stream with another network-connected device.

## Required files & things
- listen.sh
- Linux system with root access, may run with 200 MHz and 100 MB RAM, recommended 1 GHz and 500 MB RAM
- USB Audio interface or internal sound card
  - Audio input(s), e.g. 1/4 inch phone jack(s), required to record audio
  - MIDI in port(s) required to record MIDI
  - I started with a [Roland Rubix22](https://www.roland.com/us/products/rubix22/).
- [sox](http://sox.sourceforge.net/) (for WAV recording or streaming)
- [lame](https://lame.sourceforge.io/) (to convert WAV to MP3)
- [abrainstorm](http://www.sreal.com/~div/midi-utilities/) (to record MIDI)
- [netcat](http://netcat.sourceforge.net/) ("nc", to stream)

On first run, _listen_ creates a buffer WAV file, a temporary file, and a log file.

[listen is licensed under the GNU General Public License v3.0](../LICENSE.txt)

[Repository Code of Conduct](../CODE_OF_CONDUCT.md)
