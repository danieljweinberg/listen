# listen
Automatically record instrument audio and MIDI

![GitHub](https://img.shields.io/github/license/danieljweinberg/listen?color=3d9fbf&style=plastic)
![GitHub last commit](https://img.shields.io/github/last-commit/danieljweinberg/listen?style=plastic)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/danieljweinberg/listen?color=dea92c&style=plastic)
![GitHub top language](https://img.shields.io/github/languages/top/danieljweinberg/listen?color=3aa64c&style=plastic)

After years of composing music on my digital piano, and recording it only sometimes, I realized that I make some of my best work when I don't even think to record. That's why I designed this program. Once started, _listen_ will run in the background, automatically saving both a MP3 and a MIDI for each stretch of time that the attached instrument is played. By default, it stops after 30 seconds of silence. _listen_ can also send or receive an audio stream with another network-connected device, as well as automatically record video from a specified IP camera upon instrument play and stop after specified length of silence.

## Requirements
### Hardware
- Linux system with root access, recommended 1 GHz and 500 MB RAM
  - This program was written for a Raspberry Pi Zero with the above specs.
- USB Audio interface or internal sound card
  - Audio input(s), e.g. 3.5mm phone jack(s), required to record audio
  - MIDI in port(s) required to record MIDI
  - I started with a [Roland Rubix22](https://www.roland.com/us/products/rubix22/).
### Software  
- [sox](http://sox.sourceforge.net/) (for WAV recording or streaming)
- [lame](https://lame.sourceforge.io/) (to convert WAV to MP3)
- [abrainstorm](http://www.sreal.com/~div/midi-utilities/) (to record MIDI)
- [netcat](http://netcat.sourceforge.net/) ("nc", to stream)

## Setup
The only files required for _listen_ to run are _listen.sh_ and _listen.cfg_. Before first use: open _listen.cfg.template_ in a text editor and edit the file paths and other parameters to match your environment. Then rename file to _listen.cfg_.

### Configurable Parameters
Path to directories for: saving audio, buffering audio, the log file, and the temporary configuration file. (On first run, _listen_ creates the buffer and log.)

Minimum hard disk space required to save: if the program detects there is less than this amount free it will not start up, so that your disk isn't filled. The default is 500 MB, which is a few hours of audio.

MIDI port: identifier of your soundcard for MIDI recording purposes, run the progress with _devices_ option to find out what it is, and put it into the parameter, replacing colon with space. (e.g. 20 0)

Wait in seconds: stop recording after the instrument is silent for this long. The default is 30 seconds.

More parameters described in _listen.cfg.template_.

## Usage
```
listen.sh [primary_required_option] [secondary_optional_option]
```

Run _listen_ with superuser (sudo) privileges. Except for video option, which requires that you NOT run _listen_ as superuser.


### Primary options (1 is required)
  **record**	begin listening for audio in the background, record MP3 and MIDI for any audio played
  
  **send**		start an audio stream
  
  **receive**	receive an audio stream, from $SEND_IP if configured

  **video**	begin listening for audio in the background, record MP4 video from an IP camera when audio is played
  
  **like**		put a timestamped zero-byte text file in the SAVE directory, a bookmark which can remind you to keep a recording
  
  **devices**	list available audio and MIDI recording devices (see below for device configuration notes)
  
  **recent**	show last 20 lines of the log file
  
  **status**	show what _listen_ is currently doing (e.g. recording, streaming, receiving, not running)
  
  **stop**		stop what _listen_ is currently doing
  
Note: _listen_ can record and send or record and receive at the same time, just run the command twice sequentially changing the option each time. Option **stop** will stop all actions at once.
  
### Second option (optional)
  **live**		sox will run in foreground, not background, so you can see what it's doing as it records and/or streams
        
  **debug**		terminal shows all commands, running _set -o xtrace_ first
  
### Debugging and Logging

_listen_ has a few debug methods. In addition to the above secondary command which prints all commands to the terminal, there are two other features. Enable by uncommenting the relevant lines in the script.
1. Make a backup copy of the script each time the script is run with any option. This is useful if you change something in the script which alters the functionality, and you want to use an earlier version of the script. **In main program flow, default: off**
2. Every 30 minutes, write a list of all of _listen_'s running processes to the log file. Useful to track if the program was recording when you wanted it to be. **In record function, default: off**

## Notes on setting up devices
MIDI recording will use the MIDI PORT parameter. 
Audio recording will use the default device according to your system.
Set the default audio device for recording by creating /etc/asound.conf with following two lines. 
Replace "1" with number of your card determined with **devices** option.

```
defaults.pcm.card 1
defaults.ctl.card 1
```
The number of your audio device may change if it is disconnected and reconnected while the computer is on.
If the number in asound.conf refers to a now-absent device, listen will tell you with an error.
Be sure to use 'listen.sh devices' to check the current numbers for your device and edit both 
listen.cfg and /etc/asound.conf accordingly.

[listen is licensed under the GNU General Public License v3.0](../LICENSE.txt)

[Repository Code of Conduct](../CODE_OF_CONDUCT.md)
