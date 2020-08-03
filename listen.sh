#!/usr/bin/env bash
#set -o xtrace
#set -o errexit
#set -o nounset

# ==============================================================================
#
# Program Name:      listen
# Purpose:           Automatically record instrument audio and MIDI 
# Website:           https://github.com/danieljweinberg/listen
# Author:            Daniel Weinberg, 2020
# License:           GNU General Public License v3.0
# 
# ==============================================================================

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"	#/../../	, directory where the file is saved
__FILE="${__DIR}/$(basename "${BASH_SOURCE[0]}")"	#/../../...sh	, full path and filename
__BASE="$(basename ${__FILE} .sh)"			#...		, filename before extension, used for referring to the program in terminal messages
# above thanks to https://kvz.io/bash-best-practices.html
# BASE is the name of the program, i.e. listen, unless you have changed it. 

# FUNCTIONS FOR SETTING AND RETRIEVING VARIABLES FROM CONFIGURATION FILE

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

cfg_point() { # key -> value
  grep "^$(echo "$1" | sed_escape)=" "$POINTER_FILE" | sed "s/^$(echo "$1" | sed_escape)=//" | tail -1
}

cfg_delete() { # (path), key
  sed -i "/^$(echo "$2" | sed_escape).*$/d" "$CONFIG_FILE"
}

cfg_haskey() { # key
  grep "^$(echo "$1" | sed_escape)=" "$CONFIG_FILE" > /dev/null 2>&1 || return 1
}

exists(){ command -v "$1" >/dev/null 2>&1; }	# from https://stackoverflow.com/posts/34143401/revisions

# SET LOCATION OF CONFIG FILE, USING POINTER FILE IF APPLICABLE

# ------------------------------------------------------------------------------
#
# listen relies on a CONFIG_FILE in the same directory as listen. If you need
#   CONFIG_FILE to live elsewhere (e.g. due to file permissions or to support
#   multiple users or implementations), then a POINTER_FILE in the same
#   directory as listen will tell listen where to find the CONFIG_FILE. 
#
# ------------------------------------------------------------------------------

POINTER_FILE="$__DIR/${__BASE}_config_pointer.cfg"

if exists "$POINTER_FILE"; then
  CONFIG_DIR=$(cfg_point CONFIG_DIR)
else
  CONFIG_DIR="$__DIR"
fi

CONFIG_FILE="$CONFIG_DIR/$__BASE.cfg"	

# PULL LOCATIONS FROM CONFIG FILE

for a in SAVE_DIR BUFFER_DIR LOG_DIR BACKUP_DIR
  do eval $a=$(cfg_read $a); done 

# ------------------------------------------------------------------------------
#
# In $CONFIG_FILE you can specify the respective locations for:
# 
# (SAVE) the folder for completed recordings
# (BUFFER) temporary files while the instrument is being played
# (LOG) log for program events
# (BACKUP) optional backup of this script each time it's run, for debugging
#
# The $CONFIG_FILE will also be populated with the process group ID, necessary
#   to kill processes
#
# ------------------------------------------------------------------------------

# PULL SETTINGS FROM CONFIG FILE

SAVE_low_disk_space=$(cfg_read SAVE_low_disk_space)		# if free space is under this many MB, program won't record
BUFFER_low_disk_space=$(cfg_read BUFFER_low_disk_space)		# if free space is under this many MB, program won't record
ABRAINSTORM_PATH=$(cfg_read ABRAINSTORM_PATH)			# path to binary
CPU_SCALING_GOVERNOR_FILE=$(cfg_read CPU_SCALING_GOVERNOR_FILE)
MIDI_PORT=$(cfg_read MIDI_PORT)					# MIDI port to use, with space instead of colon
SEND_IP=$(cfg_read SEND_IP)					# IP address of computer connected to instrument, needed in receiving computer
WAIT_IN_SECONDS=$(cfg_read WAIT_IN_SECONDS)			# time to wait after end of playing to start saving a WAV and MIDI, must specify tenths of seconds or sox treats as 0 seconds
WATCHDOG=$(cfg_read WATCHDOG)					# on or off: write to log the running processes every X time (interpreted by sleep command)
WATCHDOG_INTERVAL=$(cfg_read WATCHDOG_INTERVAL)			# X for above. Default is 30m
BACKUP_SCRIPT=$(cfg_read BACKUP_SCRIPT)				# on or off: make a backup of the script at runtime (for debugging)
SAVE_FORMAT=$(cfg_read SAVE_FORMAT)				# if mp3, wavs will be saved in BUFFER_DIR and mp3s in SAVE_DIR. if wav, only the BUFFER_FILE will be saved in BUFFER_DIR -- the final wav will be saved in SAVE_DIR
LOGGING=$(cfg_read LOGGING)
CAMUSER=$(cfg_read CAMUSER)
CAMPWD=$(cfg_read CAMPWD)
CAMIP=$(cfg_read CAMIP)

# MIDI takes 1-3 seconds even when 30 minutes of playing
# LAME takes about 0.5 of the time spent playing (e.g. 15 min to encode 30 min)

BUFFER_FILE="$BUFFER_DIR/${__BASE}_buffer.wav"
LOG_FILE="$LOG_DIR/$__BASE.log"	

unwritable_directory(){ a="$1_DIR"; [[ ( ! -w ${!a} ) || ( ! -d ${!a} ) ]]; }
file_inaccessible(){ a="$1_FILE"; [[ "$(touch "${!a}" 2>&1)" != "" ]]; }
low_disk_space(){ a="$1_DIR"; b="$1_low_disk_space"; [ $(df -m ${!a} | tail -1 | tr -s ' ' | cut -d' ' -f4) -lt ${!b} ]; }
status(){ echo -e "$DATE\t$TYPE $ACTION"; }
pgid(){ ps -o pgid= $1 | grep -o '[0-9]*' ; }
squash(){ if cfg_haskey "$1"; then kill -15 -"$(cfg_read $1)"; fi; }	# sig9 leaves buffer.wav at 0 bytes, sig15 leaves buffer.wav at 80 bytes
check_root(){ if [[ $(/usr/bin/id -u -u) != "0" ]]; then error "This function requires that you run $__BASE as root user."; fi }

warn() {
  ACTION_PRIOR="$ACTION"
  ACTION="$ACTION_PRIOR (attempted) - WARNING"
  if [[ "$LOGGING" == "on" ]]; then
    status | tee -a "$LOG_FILE"
    echo 2>&1 "$*" | tee -a "$LOG_FILE"
  elif [[ "$LOGGING" == "off" ]]; then
    status
    echo 2>&1 "$*"
  fi
  ACTION="$ACTION_PRIOR"
  return 1
}

error() {
  ACTION_PRIOR="$ACTION"
  ACTION="$ACTION_PRIOR (attempted) - FATAL ERROR"
  if [[ "$LOGGING" == "on" ]]; then
    status | tee -a "$LOG_FILE"
    echo 2>&1 "$*" | tee -a "$LOG_FILE"
    echo 2>&1 "$__BASE will exit." | tee -a "$LOG_FILE"
  elif [[ "$LOGGING" == "off" ]]; then
    status
    echo 2>&1 "$*"
    echo 2>&1 "$__BASE will exit."
  fi
  ACTION="$ACTION_PRIOR"
  exit 1
}

record_wav(){
  while true; do
    sox -t alsa -d -c 2 -r 48000 -b 24 "$BUFFER_FILE" silence 1 0 -70d 1 $WAIT_IN_SECONDS -70d
    DATE=$(date +%Y-%m-%d--%H-%M-%S)
    TYPE="recording"
    ACTION="done"
    if [[ "$LOGGING" == "on" ]]; then
      [ -w "$LOG_DIR" ] && status | tee -a "$LOG_FILE"	# writes to log that a recording was done
    fi
    if [[ "$SAVE_FORMAT" == "mp3" ]]; then
      if exists lame; then
        mv "$BUFFER_FILE" "$BUFFER_DIR"/$DATE.recording.wav
        encode_mp3 &
      else
        mv "$BUFFER_FILE" "$SAVE_DIR"/$DATE.recording.wav
        warn "\"lame\" not installed so wav could not be encoded to mp3, so a wav file is in $SAVE_DIR"
      fi
    elif [[ "$SAVE_FORMAT" == "wav" ]]; then
      mv "$BUFFER_FILE" "$SAVE_DIR"/$DATE.recording.wav
    else
      error "invalid \$SAVE_FORMAT specified. Valid options are wav or mp3. Buffer can not be saved." 
    fi
  done
}

encode_mp3(){
  nice -10 lame --preset extreme "$BUFFER_DIR"/$DATE.recording.wav "$SAVE_DIR"/$DATE.recording.mp3	# de-prioritizes lame encoding so that sox will have plenty of cycles to record again if needed during encoding
  rm "$BUFFER_DIR"/$DATE.recording.wav
}

log(){		# for debugging, watchdog function to record that program was running at a certain point in time
  while [ -w "$LOG_DIR" ]; do
    DATE=$(date +%Y-%m-%d--%H-%M-%S)
    TYPE=$(cfg_read TYPE)
    ACTION=""
    status >> "$LOG_FILE"
    echo -e "\nRunning Processes:\n$(ps | grep sox)\n$(sudo ps | grep abrainstorm)\n$(ps | grep lame)" >> "$LOG_FILE"
    sleep "$WATCHDOG_INTERVAL"
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

  case "$SAVE_FORMAT" in
    "wav" | "mp3")
    ;;
    *)
    error "Invalid SAVE_FORMAT specified. Valid options are wav or mp3. Buffer can not be saved." 
    ;;
  esac

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
  if [[ $WATCHDOG == "on" ]]; then
    [ -w "$LOG_FILE" ] && log &	# for debugging, watchdog function to record that program was running at a certain point in time
  fi
}

video(){
  # IF LISTEN BUFFER HAS DATA, PIANO IS BEING PLAYED, SO START RECORDING VIDEO
  cfg_write PGID_VIDEO $(pgid $!)
  while true; do
  VIDEO_BUFFER_FILE="/home/pi/buffer.mp4"
    if [ $(ls "$BUFFER_FILE" -l | tr -s ' ' | cut -d' ' -f5) -gt 0 ]; then
      # LISTEN BUFFER IS NOT EMPTY, SO START VLC   
      rtsp &> /dev/null &
      until [ $(ls "$BUFFER_FILE" -l | tr -s ' ' | cut -d' ' -f5) -eq 0 ]
      # WAIT UNTIL LISTEN BUFFER IS EMPTY AGAIN, BEFORE EVALUATING
      do
        # LISTEN BUFFER IS STILL NOT EMPTY, DON'T START VLC AGAIN WHICH WOULD OVERWRITE BUFFER VIDEO FILE
        sleep 1
      done
    else
      ps cax | grep vlc > /dev/null	# source: https://stackoverflow.com/a/9118509
      if [ $? -eq 0 ]; then
	# LISTEN BUFFER IS EMPTY, BUT VLC IS STILL RUNNING, SO KILL VLC
        DATE=$(date +%Y-%m-%d--%H-%M-%S)
        killall -2 vlc
        A=0
        until [ $A -eq 1 ]
        do
          ps cax | grep vlc > /dev/null
          A=$?
          sleep 0.1
        done
        mv "$VIDEO_BUFFER_FILE" "$SAVE_DIR/$DATE.mp4"
      fi
      # KEEP LISTENING
      sleep 1
    fi
  done 
}

rtsp(){
  vlc -I dummy rtsp://"$CAMUSER":"$CAMPWD"@"$CAMIP":8554/live --sout "#duplicate{dst=std{access=file,mux=mp4,dst='$VIDEO_BUFFER_FILE'},dst=nodisplay}"
}

# PROGRAM STARTS

if [[ "$2" == "debug" ]]; then set -o xtrace; fi
if cfg_haskey TYPE; then TYPE=$(cfg_read TYPE); else TYPE="not running"; fi
DATE=$(date +%Y-%m-%d--%H-%M-%S)
status

# BACKUP PROGRAM, for debugging code modifications, saves a copy of program each time any action taken

if [[ $BACKUP_SCRIPT == "on" ]]; then
  if ! unwritable_directory BACKUP; then
    mkdir -p "$BACKUP_DIR" && cp "$__FILE" "$BACKUP_DIR/${__BASE}_${DATE}.sh.bak"
    echo "$__BASE backup saved"
  else
    warn "${!a} unwritable : $__BASE backup could not be saved."
  fi  
fi

# CHECK IF CONFIGURATION FILE IS WRITABLE

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

# CAPTURE CURRENT CPU SCALING GOVERNOR VALUE

CPU_SCALING_GOVERNOR_OLD=$(cfg_read CPU_SCALING_GOVERNOR_OLD)

# DETERMINE WHETHER TO RUN SOX IN FOREGROUND (LIVE) OR BACKGROUND

case "$2" in
  "live")
    live="true"
    how_to_stop="To end this program, run \"sudo $__FILE stop\" in the same window or another terminal."
  ;;
  *)
    how_to_stop="To end this program, run \"sudo $__FILE stop\""
  ;;
esac

# DETERMINE WHICH ACTIVITY TYPE TO PERFORM

case "$1" in
  "stop")
    check_root
    running_tasks=0
    for PGID in PGID_RECORD PGID_STREAM_SEND PGID_STREAM_RECEIVE PGID_VIDEO
      do
        if cfg_haskey $PGID; then (( running_tasks+=1 )); else continue; fi
        squash $PGID
        cfg_delete "$CONFIG_FILE" $PGID
      done
    if [[ $running_tasks = 0 ]]; then error "$__BASE was not running anyway, so there was nothing to terminate."; fi
    # return CPU scaling governor to what it was before running program
    sh -c "echo -n $CPU_SCALING_GOVERNOR_OLD > $CPU_SCALING_GOVERNOR_FILE"

    if [ $(ls "$BUFFER_FILE" -l | tr -s ' ' | cut -d' ' -f5) -gt 1024 ]; then	# if more than 1 KB in buffer, make copy before closing
#   if [ -s "$BUFFER_FILE" ]; then 
      mv "$BUFFER_FILE" "$BUFFER_DIR"/$DATE.recording.wav      
      warn "Buffer was not empty on stopping, saved to $BUFFER_DIR/$DATE.recording.wav"
    fi
    rm "$BUFFER_FILE" 2>/dev/null; touch "$BUFFER_FILE"
  ;;
  "like")
    if unwritable_directory SAVE; then
      error "${!a} : unwritable directory, no timestamp can be saved." 
    else
      touch "$SAVE_DIR"/$DATE\.txt
      TYPE="timestamp"
    fi
  ;;
  "video")
    if [[ $(/usr/bin/id -u -u) == "0" ]]; then error "This function requires that you NOT run $__BASE as root user."; fi

    if ! exists vlc; then
      error "vlc not present."
    elif [[ "$TYPE" == "recording" ]] ; then
      TYPE="$TYPE & video"
    elif [[ "$TYPE" == "not running" ]] ; then
      TYPE="video"
    else
      error "$__BASE is already $TYPE."
    fi
    video &
  ;;
  "record")
    check_root
    if [[ "$TYPE" == "not running" ]]; then
      TYPE="recording"
    elif [[ "$TYPE" == "streaming (sending)" ]]; then
      TYPE="recording & $TYPE"
    elif [[ "$TYPE" == "video" ]]; then
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
    error "Invalid option. Valid options for $__BASE: record | send | receive | video | like | devices | recent | status | stop"
  ;;
esac

# NOTE WHICH ACTION WAS DONE TO THE ACTIVITY TYPE

case "$1" in
  "record" | "send" | "receive" | "video")
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

# PRINT TO TERMINAL AND LOG WHAT WAS DONE, IF LOG FILE IS ACCESSIBLE

for check in unwritable_directory file_inaccessible
  do
    if $check LOG; then
      echo >&2 "${!a} : ${check//_/ }, $__BASE will continue as normal but no events will be logged."
      LOGGING=off
      #cfg_write LOGGING "$LOGGING"
    fi
  done

if [[ "$LOGGING" == "on" ]]; then
  status | tee -a "$LOG_FILE"
elif [[ "$LOGGING" == "off" ]]; then
  status
else
  echo >&2 "Invalid LOGGING option. Valid options are on or off. $__BASE will exit."
  exit 1
fi

exit 0
