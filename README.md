# listen
Automatically record instrument audio and MIDI

![GitHub](https://img.shields.io/github/license/danieljweinberg/listen?color=3d9fbf&style=plastic)
![GitHub last commit](https://img.shields.io/github/last-commit/danieljweinberg/listen?style=plastic)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/danieljweinberg/listen?color=dea92c&style=plastic)
![GitHub top language](https://img.shields.io/github/languages/top/danieljweinberg/listen?color=3aa64c&style=plastic)

After years of composing music on my digital piano, and recording it only sometimes, I realized that I make some of my best work when I don't even think to record. That's why I designed this program. It was written for a Raspberry Pi connected via USB Audio Interface to the instrument. Once started, _listen_ will run in the background, automatically saving both a MP3 and a MIDI for each stretch of time that the attached instrument is played. By default, it stops after 30 seconds of a silence. _listen_ can also send or receive an audio stream with another network-connected device.

## Requirements
### Hardware
- Linux system with root access, may run with 200 MHz and 100 MB RAM, recommended 1 GHz and 500 MB RAM
- USB Audio interface or internal sound card
  - Audio input(s), e.g. 1/4 inch phone jack(s), required to record audio
  - MIDI in port(s) required to record MIDI
  - I started with a [Roland Rubix22](https://www.roland.com/us/products/rubix22/).
### Software  
- [sox](http://sox.sourceforge.net/) (for WAV recording or streaming)
- [lame](https://lame.sourceforge.io/) (to convert WAV to MP3)
- [abrainstorm](http://www.sreal.com/~div/midi-utilities/) (to record MIDI)
- [netcat](http://netcat.sourceforge.net/) ("nc", to stream)

## Setup
Before first use: open the _listen.sh_ in a text editor and edit the file paths and other parameters to match your environment.

### Configurable Parameters
Path to directories for: saving audio, buffering audio, the log file, and the temporary configuration file. (On first run, _listen_ creates these latter three files.)

Minimum hard disk space required to save: if the program detects there is less than this amount free it will not start up, so that your disk isn't filled. The default is 500 MB, which is a few hours of audio.

MIDI port: identifier of your soundcard for MIDI recording purposes, run the progress with _devices_ option to find out what it is, and put it into the parameter, replacing colon with space. (e.g. 20 0)

Wait in seconds: stop recording after the instrument is silent for this long. The default is 30 seconds.

## Usage
$	listen.sh \[primary_required_option\] \[secondary_optional_option\]

Run _listen_ with sudo privileges.


### Primary options (1 is required)
  **record**	begin recording WAV and MIDI in the background
  **send**		start an audio stream
  **receive**	receive an audio stream, from $SEND_IP if configured
  **like**		put a timestamped zero-byte text file in the SAVE directory, a bookmark which can remind you to keep a recording
  **devices**	list available audio and MIDI recording devices (see below for device configuration notes)
  **recent**	show last 20 lines of the log file
  **status**	show what _listen_ is currently doing (e.g. recording, streaming, receiving, not running)
  **stop**		stop what _listen_ is currently doing
  
Note: _listen_ can record and send or record and receive at the same time, just run the command twice sequentially changing the option each time. Option **stop** will stop all actions at once.
  
### Second option (optional)
  **live**		sox will run in foreground, not background, so you can see what it's doing as it records
  			(usage: listen.sh record live)
  **debug**		terminal shows all commands, running _set -o xtrace_ first

## Notes on setting up devices
MIDI recording will use the MIDI PORT parameter.
Audio recording will use the default device according to your system.
Set the default audio device for recording by creating /etc/asound.conf with following two lines. Replace "1" with number of your card determined with **devices** option.

- defaults.pcm.card 1
- defaults.ctl.card 1

[listen is licensed under the GNU General Public License v3.0](../LICENSE.txt)

[Repository Code of Conduct](../CODE_OF_CONDUCT.md)
