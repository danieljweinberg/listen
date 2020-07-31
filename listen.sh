#!/usr/bin/env bash
#set -o xtrace
#set -o errexit
#set -o nounset

# ===================================================================
# Program Name:      listen
# Purpose:           Automatically record instrument audio and MIDI 
# Website:           https://github.com/danieljweinberg/listen
# Author:            Daniel Weinberg, 2020
# License:           GNU General Public License v3.0
# \./././.
# ===================================================================

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"	#/../../	, directory where the file is saved
__FILE="${__DIR}/$(basename "${BASH_SOURCE[0]}")"	#/../../...sh	, full path and filename
__BASE="$(basename ${__FILE} .sh)"			#...		, filename before extension, used for referring to the program in terminal messages
# above thanks to https://kvz.io/bash-best-practices.html

# All directories below can be the same or different.
SAVE_DIR=/save/audio-and-midi/here	# folder for completed recordings
BUFFER_DIR=/audio/buffer/here		# temporary file while the instrument is being played
LOG_DIR=/keep/log/here			# file for program events
CONFIG_DIR=/keep/temp/file/here		# file with process group ID, necessary to kill processes

BUFFER_FILE="$BUFFER_DIR/${__BASE}_buffer.wav"
LOG_FILE="$LOG_DIR/$__BASE.log"			
CONFIG_FILE="$CONFIG_DIR/$__BASE.cfg"

SAVE_low_disk_space="500"		# if free space is under this many MB, program won't record
BUFFER_low_disk_space="500"		# if free space is under this many MB, program won't record

ABRAINSTORM_PATH=/home/pi/midi-utilities/bin/abrainstorm	# path to binary

CPU_SCALING_GOVERNOR_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

MIDI_PORT="20 0"			# MIDI port to use, with space instead of colon

SEND_IP=10.0.0.2			# IP address of computer connected to instrument, needed in receiving computer

WAIT_IN_SECONDS=30.0		# time to wait after end of playing to start 
				# saving a WAV and MIDI, must specify tenths of
				# seconds or sox treats as 0 seconds

# exists function from https://stackoverflow.com/posts/34143401/revisions
# sed below from https://stackoverflow.com/questions/2464760/modify-config-file-using-bash-script

# README

# Setting the default device
# Find your desired card with:
#   cat /proc/asound/cards
# and then create /etc/asound.conf with following:
#   defaults.pcm.card 1
#   defaults.ctl.card 1
# Replace "1" with number of your card determined above.

# MIDI takes 1-3 seconds even when 30 minutes of playing
# LAME takes about 0.5 of the time spent playing (e.g. 15 min to encode 30 min)

exists(){ command -v "$1" >/dev/null 2>&1; }
unwritable_directory(){ a="$1_DIR"; [[ ( ! -w ${!a} ) || ( ! -d ${!a} ) ]]; }
file_inaccessible(){ a="$1_FILE"; [[ "$(touch "${!a}" 2>&1)" != "" ]]; }
low_disk_space(){ a="$1_DIR"; b="$1_low_disk_space"; [ $(df -m ${!a} | tail -1 | tr -s ' ' | cut -d' ' -f4) -lt ${!b} ]; }
status(){ echo -e "$DATE\t$TYPE $ACTION"; }
pgid(){ ps -o pgid= $1 | grep -o '[0-9]*' ; }
squash(){ if cfg_haskey "$1"; then kill -9 -"$(cfg_read $1)"; fi; }
check_root(){
  if [[ $(/usr/bin/id -u -u) != "0" ]]; then
    error "This function requires that you run $__BASE as root user."
  fi
}

warn() {
  echo >&2 "$*"
  return 1
}

error() {
  echo >&2 "$*"
  echo >&2 "$__BASE will exit."
  exit 1
}

sed_escape() { # this and below from https://unix.stackexchange.com/a/433816
  sed -e 's/[]\/$*.^[]/\\&/g'1
}

cfg_write() { # key, value
  cfg_delete "$CONFIG_FILE" "$1"
  echo "$1=$2" >> "$CONFIG_FILE"
}

cfg_read() { # key -> value
  grep "^$(echo "$1" | sed_escape)=" "$CONFIG_FILE" | sed "s/^$(echo "$1" | sed_escape)=//" | tail -1
}

cfg_delete() { # (path), key
  sed -i "/^$(echo "$2" | sed_escape).*$/d" "$CONFIG_FILE"
}

cfg_haskey() { # key
  grep "^$(echo "$1" | sed_escape)=" "$CONFIG_FILE" > /dev/null 2>&1 || return 1
}

record_wav(){
  while true; do
    sox -t alsa -d -c 2 -r 48000 -b 24 "$BUFFER_FILE" silence 1 0 -70d 1 $WAIT_IN_SECONDS -70d
    DATE=$(date +%Y-%m-%d--%H-%M-%S)
    TYPE="recording"
    ACTION="done"
    [ -w "$LOG_DIR" ] && status | tee -a "$LOG_FILE"	# writes to log that a recording was done
    mv "$BUFFER_FILE" "$SAVE_DIR"/$DATE.recording.wav
    if exists lame; then
      encode_mp3 &
    else
      warn "\"lame\" not installed so wav could not be encoded to mp3."
    fi
  done
}

encode_mp3(){
  nice -10 lame --preset extreme "$SAVE_DIR"/$DATE.recording.wav "$SAVE_DIR"/$DATE.recording.mp3	# de-prioritizes lame encoding so that sox will have plenty of cycles to record again if needed during encoding
  rm "$SAVE_DIR"/$DATE.recording.wav	# comment out to keep original WAV file
}

log(){		# for debugging, watchdog function to record that program was running at a certain point in time
  while [ -w "$LOG_DIR" ]; do
    DATE=$(date +%Y-%m-%d--%H-%M-%S)
    TYPE=$(cfg_read TYPE)
    ACTION=""
    status >> "$LOG_FILE"
    echo -e "\nRunning Processes:\n$(ps | grep sox)\n$(sudo ps | grep abrainstorm)\n$(ps | grep lame)" >> "$LOG_FILE"
    sleep 30m
  done
}

record_midi(){
  if [[ "${MIDI_PORT-undefined}" == "undefined" ]]; then
    warn "\$MIDI_PORT not supplied, so MIDI will not be recorded."
  elif exists "$ABRAINSTORM_PATH"; then
    cd "$SAVE_DIR"
    "$ABRAINSTORM_PATH" --timeout $WAIT_IN_SECONDS --connect $MIDI_PORT &
  else
    warn "abrainstorm not found. MIDI will not be recorded."
  fi
  cfg_write PGID_RECORD $(pgid $!)
}

stream_receive(){
  nc $SEND_IP 3333|play -c 1 -b 16 -e signed -t raw -r 48k - &
  cfg_write PGID_STREAM_RECEIVE $(pgid $!)
}

stream_send(){
  rec -c 1 -t raw - |nc -l 3333 &
  cfg_write PGID_STREAM_SEND $(pgid $!)
}

record(){
  for check in unwritable_directory low_disk_space
  do
    if $check SAVE; then
      error "${!a} : ${check//_/ }, no audio or MIDI can be saved." 
    elif $check BUFFER; then
      warn "${!a} : ${check//_/ }, no buffer audio can be saved. Only MIDI will be saved." 
    fi
  done

  if exists sox; then
    # on Raspberry Pi zero, disables CPU speed shifting which can cause audio crackle.
    cfg_write CPU_SCALING_GOVERNOR_OLD $(cat "$CPU_SCALING_GOVERNOR_FILE")
    sh -c "echo -n performance > $CPU_SCALING_GOVERNOR_FILE"
    if [[ "$live" = "true" ]]; then
      record_wav 2>&1 &
    else
      record_wav >/dev/null 2>&1 &
    fi
    echo "$how_to_stop"
  else
    warn "Sox not found. Audio will not be recorded."
  fi

  record_midi &			# wav then midi works best for $DATE congruence
  # [ -w "$LOG_FILE" ] && log &	# for debugging, watchdog function to record that program was running at a certain point in time
}

# PROGRAM STARTS

if [[ "$2" == "debug" ]]; then set -o xtrace; fi
if cfg_haskey TYPE; then TYPE=$(cfg_read TYPE); else TYPE="not running"; fi
DATE=$(date +%Y-%m-%d--%H-%M-%S)
status

# BACKUP PROGRAM, for debugging code modifications, saves a copy of program each time any action taken
# mkdir -p "$__DIR/${__BASE}_backups" && cp "$__FILE" "$__DIR/${__BASE}_backups/${__BASE}_${DATE}.sh.bak"

case "$1" in
  "record" | "send" | "receive" | "stop" | "status")
    for check in unwritable_directory file_inaccessible
    do
      if $check CONFIG; then
        error "${!a} : ${check//_/ }, configuration cannot be saved." 
      fi
    done
  ;;
esac

CPU_SCALING_GOVERNOR_OLD=$(cfg_read CPU_SCALING_GOVERNOR_OLD)

case "$2" in
  "live")
    live="true"
    how_to_stop="Ctrl+C to end recording and immediately start another one. Ctrl+C twice quickly to stop program and return to shell prompt."
  ;;
  *)
    how_to_stop="To end this program, run \"sudo $__FILE stop\""
  ;;
esac

case "$1" in
  "stop")
    check_root
    running_tasks=0
    for PGID in PGID_RECORD PGID_STREAM_SEND PGID_STREAM_RECEIVE
      do
        if cfg_haskey $PGID; then (( running_tasks+=1 )); else continue; fi
        squash $PGID
        cfg_delete "$CONFIG_FILE" $PGID
      done
    if [[ $running_tasks = 0 ]]; then error "$__BASE was not running anyway, so there was nothing to terminate."; fi
    # return CPU scaling governor to what it was before running program
    sh -c "echo -n $CPU_SCALING_GOVERNOR_OLD > $CPU_SCALING_GOVERNOR_FILE"
  ;;
  "like")
    touch "$SAVE_DIR"/$DATE\.txt
    TYPE="timestamp"
  ;;
  "record")
    check_root
    if [[ "$TYPE" == "not running" ]]; then
      TYPE="recording"
    elif [[ "$TYPE" == "streaming (sending)" ]]; then
      TYPE="recording & $TYPE"
    else
      error "$__BASE is already $TYPE."
    fi
    record
  ;;
  "send")
    check_root
    if ! exists nc || ! exists sox; then
      error "nc or sox not present."
    elif [[ "$TYPE" == "recording" ]] ; then
      stream_send >/dev/null 2>&1 &
      TYPE="$TYPE & streaming (sending)"
    elif [[ "$TYPE" == "not running" ]] ; then
      stream_send >/dev/null 2>&1 &
      TYPE="streaming (sending)"
    else
      error "$__BASE is already $TYPE."
    fi
  ;;
  "receive")
    check_root
    if ! exists nc || ! exists sox; then
      error "nc or sox not present."
    elif [[ $(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1) == "$SEND_IP" ]]; then		# https://unix.stackexchange.com/questions/8518/how-to-get-my-own-ip-address-and-save-it-to-a-variable-in-a-shell-script
      error "This computer is already configured to send stream (\$SEND_IP is this computer's IP address), so receiving won't work."
    elif [[ "$TYPE" == "not running" ]]; then
      stream_receive >/dev/null 2>&1 &
      TYPE="streaming (receiving)"
    else
      error "$__BASE is already $TYPE."
    fi
  ;;
  "recent")
    if [ -f "$LOG_FILE" ]; then
      echo -e "$__BASE recent events:\n"
      tail -n 20 "$LOG_FILE"
    else
      error "Log file not found."
    fi
    exit 0
  ;;
  "status")      
    ACTION=""
    status
    exit 0
  ;;
  "devices")
    check_root
    echo "Audio recording devices on this system:"
    arecord -l
    echo "MIDI recording devices on this system:"
    arecordmidi -l
    exit 0
  ;;
  *)
    error "Invalid option. Valid options for $__BASE: record | send | receive | like | devices | recent | status | stop"
  ;;
esac

# LOG ACTION PERFORMED
case "$1" in
  "record" | "send" | "receive")
    ACTION="started"
    cfg_write TYPE "$TYPE"
  ;;
  "stop")
    ACTION="stopped"
  ;;
  "like")
    ACTION="saved"
  ;;           
esac   

if [[ "$1" == "stop" ]]; then cfg_write TYPE "not running"; fi

for check in unwritable_directory file_inaccessible
  do
    if $check LOG; then
      warn "${!a} : ${check//_/ }, $__BASE will continue as normal but no events will be logged."
      status; exit 0
    fi
  done

status | tee -a "$LOG_FILE"

exit 0
