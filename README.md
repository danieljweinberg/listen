# listen
Automatically record instrument audio and MIDI

After years of composing music on my digital piano, and recording it only sometimes, I realized that I make some of my best work when I don't even think to record. That's why I designed this program. It was written for a Raspberry Pi connected via USB Audio Interface to the instrument. Once started, _listen_ will run in the background, automatically saving both a MP3 and a MIDI for each stretch of time that the attached instrument is played. _listen_ can also send or receive an audio stream with another network-connected device.

## Required files & things
- listen.sh
- Linux system with root access, may run with 200 MHz and 100 MB RAM, recommended 1 GHz and 500 MB RAM
- External USB Audio interface or internal sound card (some variety of this is required for all features)
  - Audio input(s), e.g. 1/4 inch phone jack(s), required to record audio
  - MIDI in port(s) required to record MIDI
- [sox](http://sox.sourceforge.net/) (for WAV recording or streaming)
- [lame](https://lame.sourceforge.io/) (to convert WAV to MP3)
- [abrainstorm](http://www.sreal.com/~div/midi-utilities/) (to record MIDI)
- [netcat](http://netcat.sourceforge.net/) ("nc", to stream)

On first run, _listen_ creates a buffer WAV file, a temporary file, and a log file.
