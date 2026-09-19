--
-- Arturia KeyLab Essential mk3 (AKM) - Renoise Tool
-- Fork of the original Arturia KeyLab mk3 (Pro-line) tool by foma / ulneiz,
-- reworked specifically for the Essential 49/61/88 mk3, which uses a genuinely
-- different MIDI protocol from the Pro-line hardware the original tool targeted.
--
-- READ THIS FIRST if you're new to this file:
--
-- 1) SINGLE FILE ON PURPOSE.
--    This used to be split into akm.lua + akm_actions.lua (loaded via two
--    require() calls in main.lua). That split caused an unresolved cross-file
--    load-order bug: some functions defined in the second file weren't yet
--    visible as globals by the time GUI widgets in the first file tried to use
--    them at construction time (fader tostring/tonumber callbacks). Recombining
--    into one file fixed it immediately. Don't re-split without understanding
--    why that happened - see the git history around that point for the details.
--
-- 2) Essential mk3 sends plain Control Change (0xB0) messages for transport,
--    knobs, faders, and dial - NOT the Note-On (0x90) messages the Pro-line
--    hardware uses. Its pads are Note-On on MIDI channel 10 though. All of this
--    arrives on ONE plain MIDI port ("... mk3 MIDI"), not a separate DAW port -
--    the MCU/HUI port this device also exposes stays completely silent and is
--    not used by this tool at all. See midi_callback (search "local function
--    midi_callback") for the actual dispatch table this drives.
--
-- 3) TWO DIFFERENT KNOB BEHAVIOURS, ON PURPOSE:
--    - Knobs that pick a VALUE FROM A RANGE (note, instrument, volume, panning,
--      delay, fx-val, fx-amount) use DIRECT POSITION MAPPING: the knob's raw
--      0-127 reading maps straight onto the target's range every time
--      (akm_knob_*_val functions). This is deliberate - an earlier version used
--      relative step-counting (turn = +1/-1) and it got stuck whenever the
--      physical knob hit its own firmware limit (0 or 127), since turning
--      further past that point produces no new MIDI data at all to react to.
--    - Knobs that perform a RELATIVE MOVE with no sensible "position" concept
--      (NC/EC column navigation, step-length) still use step-counting
--      (akm_knob_dir + previous/next pairs) because there's nothing to map a
--      knob position onto. These two still exhibit the "stuck at the physical
--      limit until you reverse" behaviour - that's an accepted, understood
--      limitation, not a bug to chase.
--
-- 4) LED FEEDBACK (Play/Rec/Loop/Quant/Part/Tap) needs a one-time "DAW connect"
--    SysEx handshake before the device will accept LED colour commands at all
--    (akm_essential_daw_connect, sent automatically on first use). LEDs are
--    kept in sync via Renoise's *_observable properties (akm_essential_attach_led_observers),
--    not by only updating on button press - that way they stay correct even if
--    you change state with the mouse instead of the hardware.
--
-- 5) Renoise's Lua sandbox caps a single chunk at 200 top-level locals. All
--    action functions here are plain globals (no "local") specifically to stay
--    well under that ceiling as the tool grows - keep doing that for new
--    top-level functions rather than reaching for "local function".
--
-- 6) The dead Pro-line-only subsystem (note-based button/LED rules, akm_tbl_rules,
--    akm_fun_gen/akm_fun_rules, rewind/forward/live-part/read/write buttons) has
--    been removed entirely - none of it is reachable from Essential mk3 hardware.
--

----------------------------------------
--collectgarbage<top>
 --collectgarbage("stop")
----------------------------------------

-------------------------------------------------------------------------------------------------
--local global variables/tables
-------------------------------------------------------------------------------------------------
--persisted tool preferences (survives across Renoise sessions)
renoise.tool().preferences = renoise.Document.create("AkmPreferences") {
  essential_setup_shown=false,
  default_device_index=5 --5 = "KeyLab Essential 61 mk3 (DAW)"
  ,saved_in_device=""
  ,saved_out_device=""
}

AKM_MAIN_DIALOG=nil
AKM_MAIN_CONTENT=nil
akm_main_title="Arturia KeyLab mk3"
akm_version="1.0"
akm_build="build 43"
rns_version=string.sub(renoise.RENOISE_VERSION,1,5)
api_version=renoise.API_VERSION
vb=renoise.ViewBuilder()
vws=vb.views
rna=renoise.app()
rnt=renoise.tool()
aw=renoise.ApplicationWindow

--about
local AKM_ABOUT_TTP=
  "VERSION: "..akm_version.." "..akm_build.." \n"..
  "HARDWARE: Arturia KeyLab Essential 49/61/88 mk3\n"..
  "COMPATIBILITY: Renoise 3.5.x (Lua API 6)\n"..
  "LICENSE: GNU General Public License\n"..
  "ORIGINAL AUTHORS: foma; Original MKII version by ulneiz\n"..
  "ESSENTIAL PORT: this fork\n"..
  "\n"..
  "SETUP (one-time):\n"..
  "- On the keyboard, load the \"DAWs Program\" (press Prog until the screen shows it);\n"..
  "- In this tool, select your model (49/61/88 Essential) and the plain 'MIDI' In/Out\n"..
  "  device (NOT the MCU/HUI port - this model doesn't use it);\n"..
  "- Edit > Preferences > MIDI > \"Ignore specific controllers\": paste this list so\n"..
  "  Renoise doesn't record buttons/knobs into your patterns as raw commands:\n"..
  "  20,21,22,24,25,26,27,40,42,43,96,97,98,99,100,101,102,103,104,105,106,107,\n"..
  "  108,109,110,111,112,113,116,117,118\n"..
  "- On the instrument(s) you play, set MIDI Input > Channel to 1 (instead of Any)\n"..
  "  so pads (channel 10) aren't recorded as notes."

--global song
song=nil
  local function akm_sng() song=renoise.song() end --define global "song"
  rnt.app_new_document_observable:add_notifier(akm_sng) --catching start renoise or new song
  pcall(akm_sng) --catching installation



--variables
local AKM_DEVICE_NAME={" KeyLab 49 mk3 (DAW)"," KeyLab 61 mk3 (DAW)"," KeyLab 88 mk3 (DAW)"," KeyLab Essential 49 mk3 (DAW)"," KeyLab Essential 61 mk3 (DAW)"," KeyLab Essential 88 mk3 (DAW)"}
local AKM_INPUTS={}
local AKM_OUTPUTS={}
local AKM_LOCK_IO_DEVICES=false
local AKM_ACTIVATE=false
local AKM_STOP_STATUS=false
AKM_TAP_LAST_TIME=nil
AKM_TAP_INTERVALS={}


local AKM_TRK_REPEAT={70,300,true,true}
local AKM_SEQ_REPEAT={70,300,true,true}
local AKM_LNE_REPEAT={30,300}
AKM_INS_REPEAT={30,300,true,true}
local AKM_VPD_VALUES={111, 127,64,0, 127}
AKM_VAL_LOCK={true,true,true,true,true,true,true,true,true}

local function akm_trim_device_name(value)
  if (value == nil) then return "" end
  value=tostring(value)
  value=value:gsub("^%s+", "")
  value=value:gsub("%s+$", "")
  return value
end

local function akm_normalize_device_name(value)
  local normalized=akm_trim_device_name(value)
  normalized=normalized:lower()
  normalized=normalized:gsub("%s+", " ")
  return normalized
end

local function akm_find_device_by_name(device_list, wanted_name)
  local wanted=akm_normalize_device_name(wanted_name)
  if (wanted=="") then return nil, nil end

  for index=1,#device_list do
    local candidate=akm_trim_device_name(device_list[index])
    if (akm_normalize_device_name(candidate)==wanted) then
      return candidate, index
    end
  end

  for index=1,#device_list do
    local candidate=akm_trim_device_name(device_list[index])
    if (string.find(akm_normalize_device_name(candidate), wanted, 1, true)) then
      return candidate, index
    end
  end

  return nil, nil
end

local function akm_validate_device_name(device_name, device_list)
  if (device_name == nil) then return nil end
  local trimmed=akm_trim_device_name(device_name)
  if (trimmed=="") then return nil end

  if (device_list ~= nil) then
    local found_name = akm_find_device_by_name(device_list, trimmed)
    if (found_name ~= nil) then
      local exact_name=akm_trim_device_name(found_name)
      if (exact_name ~= "") then return exact_name end
    end
  end

  return nil
end

local function akm_store_selected_devices()
  if (vws.AKM_PP_DEVICE_IN and vws.AKM_PP_DEVICE_IN.value and AKM_INPUTS[vws.AKM_PP_DEVICE_IN.value]) then
    renoise.tool().preferences.saved_in_device.value=akm_trim_device_name(AKM_INPUTS[vws.AKM_PP_DEVICE_IN.value])
  end
  if (vws.AKM_PP_DEVICE_OUT and vws.AKM_PP_DEVICE_OUT.value and AKM_OUTPUTS[vws.AKM_PP_DEVICE_OUT.value]) then
    renoise.tool().preferences.saved_out_device.value=akm_trim_device_name(AKM_OUTPUTS[vws.AKM_PP_DEVICE_OUT.value])
  end
end

local AKM_AUTOSTART=true
local AKM_HIDE_ON_START=true
local AKM_REMAP_PADS=true
local AKM_AUTO_INJECT_MAPPINGS=false

--colors
local AKM_CLR={
  BLACK={001,000,000},
  WHITE={235,235,235},
  DEFAULT={000,000,000},
  MARKER={235,235,235},
  RED={199,000,000}
}
  
--capture the native color of marker(for Windows: C:\Users\USER_NAME\AppData\Roaming\Renoise\V3.1.1\Config.xml)
local function akm_capture_clr_mrk()
  --print(os.currentdir())

  --Config.xml path:
    --Windows: %appdata%\Renoise\V3.1.1\Config.xml
    --MacOS: ~/Library/Preferences/Renoise/V3.1.1/Config.xml
    --Linux: ~/.renoise/V3.1.1/Config.xml

  local filename=""
  if (os.platform()=="WINDOWS") then
    filename=("%s\\Renoise\\V%s\\Config.xml"):format(os.getenv("APPDATA"),rns_version)
    --print("Windows:",filename)
  elseif (os.platform()=="MACINTOSH") then
    filename=("%s/Library/Preferences/Renoise/V%s/Config.xml"):format(os.getenv("HOME"),rns_version)
    --print("MacOS:",filename)
  elseif (os.platform()=="LINUX") then
    filename=("%s/.config/Renoise/V%s/Config.xml"):format(os.getenv("HOME"),rns_version)
    --print("Linux:",filename)
  end
  --print(filename)
  
  --RenoisePrefs
    --SkinColors
      --Selected_Button_Back

  if (io.exists(filename)) then
    local pref_data=renoise.Document.create("RenoisePrefs"){SkinColors={Selected_Button_Back=""}}
    pref_data:load_from(filename)
    local rgb=tostring(pref_data.SkinColors.Selected_Button_Back)
    local one,two,thr=rgb:match("([^,]+),([^,]+),([^,]+)")
    AKM_CLR.MARKER[1]=tonumber(one)
    AKM_CLR.MARKER[2]=tonumber(two)
    AKM_CLR.MARKER[3]=tonumber(thr)
  end
end

-------------------------------------------------------------------------------------------------
--diginal monitor status
-------------------------------------------------------------------------------------------------
--monitor 1
akm_tbl_dm1={
  --
  "Solo Off Current Track",
  "Solo On Current Track",

  "Off Current Track",
  "Mute Current Track",
  "On Current Track",

  "Hide Sample Recorder\n(mod insert sample)",
  "Show Sample Recorder\n(mod insert sample)",

  "Show Upper Track\nScopes",
  "Show Upper Spectrum",
  "Hide Upper Frame",

  "Show Lower Track DSP",
  "Show Lower Track\nAutomation Editor",
  "Hide Lower Frame",
  --
  "Show Save Song Window",
  "Song Not Saved!",
  "Song Saved!",
  
  "Undo",
  "Nothing to Undo!",
  "Redo",
  "Nothing to Redo!",
  
  "Disable Metronome",
  "Enable Metronome",
  
  "Disable Follow",
  "Enable Follow",

  "Previous Track",
  "Next Track",
  
  "Stop Song\n(mod play modes)",
  "Panic Sound!\n(mod play modes)",
  
  "Play From Playback\nPosition Of Song",
  "Replay Current\nPattern Sequence",
  
  "Off Edit Mode",
  "On Edit Mode",
  
  "Loop Off\nCurrent Pattern",
  "Loop On\nCurrent Pattern",
  
  "Previous Pattern\nSequence",
  "Next Pattern\nSequence",
  
  "Show Pattern Editor",
  "Show Mixer Editor",
  "Show Sampler Phrases",
  "Show Sampler Keyzones",
  "Show Sampler Waveform",
  "Show Sampler Modulation",
  "Show Sampler Effects", 
  "Show Plugin Editor",
  "Show MIDI Monitor",
  
  "Previous Line",
  "Next Line",
  
  "Previous Instrument",
  "Next Instrument"
}



-------------------------------------------------------------------------------------------------
--general functions
-------------------------------------------------------------------------------------------------

--- ---convert values
--note convert tostring

--note convert tonumber



--instrument convert tostring

--instrument convert tonumber



--volume convert tostring

--volume convert tonumber



--panning convert tostring

--panning convert tonumber



--delay convert tostring

--delay convert tonumber



AKM_SFX={"00","0A","0U","0D","0G","0V","0I","0O","0T","0C","0S","0B","0E","0N"}
AKM_EFF={"00","0A","0U","0D","0G","0V","0I","0O","0T","0C","0S","0B","0E","0N", "0M","0Z","0Q","0Y","0R", "0L","0P","0W","0X","0J", "ZT","ZL","ZK","ZG","ZB","ZD"}

--sfx/fx value convert tostring

--sfx/fx value convert tonumber

--amount effect convert tostring

--amount effect convert tonumber

--note/effect column convert tostring

--note/effect column convert tonumber

--step length convert tostring

--step length convert tonumber

--4 read --> (upper frame view)







--5 write --> (lower frame view)



------ Pads (Bank A). Unused since they don't consume MIDI events and only come from (MIDI) device.














--- ---global controls (1:save, 2:in, 3:out, 4:metro, 5:undo)
--1 save


--2 in  --> (undo)
local function akm_in()
  if (song:can_undo()) then
    song:undo()
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[17]
  else
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[18]
  end
end

--3 out --> (redo)
local function akm_out()
  if (song:can_redo()) then
    song:redo()
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[19]
  else
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[20]
  end
end

--4 metro

--5 undo (follow the player's position)

--5b real undo/redo, bound to the dedicated Undo/Redo buttons




--- ---transport controls (1:rewind, 2:fast_forward, 3:stop, 4:play/pause, 5:record, 6:loop)
--1 previous track


--2 next track


--3 stop song (& panic)



--4 play song


--5 edit mode

--6 block loop


--- ---browses center controls (1:center knob left, 2:center knob right, 3:center knob button | 1:left arrow, 2:right arrow)
--1 left button --> (previous pattern sequence)




--2 right button --> (next pattern sequence)




--3 button dial --> (main tabs navigador)






AKM_WINDOW_FRAME=3
--4 left dial --> (main tabs left navigador)



--5 right dial --> (main tabs right navigador)



--- ---live/bank circular buttons
--1 previous line




--2 next line




--3 bank next --> (previous instrument)




--4 bank previous --> (next instrument)




--- ---encoders (8+1 rotary knobs)




--1 knob for note







--2 knob for instrument







--3 knob for volume





--4 knob for panning







--delay convert tostring

--delay convert tonumber



--5 fader --> (delay value)








--6 knob for sfx-fx








--7 knob for amount







--8 knob for note/effect columns navigation






--9 knob for step length


--- ---faders (8+1 rotary knobs)
--1 fader --> (note value)

--2 fader --> (instrument value)

--3 fader --> (volume value)

--4 fader --> (panning value)

--5 fader --> (delay value)

--6 fader --> (sfx/fx)

--7 fader --> (amount effect)

--8 fader --> (note/effect column)

--9 fader --> (step length)

--- ---filter/select buttons (8+1 multicolor buttuns)



-------------------------------------------------------------------------------------------------
--output device
-------------------------------------------------------------------------------------------------
local AKM_MIDI_DEVICE_OUT=nil
local function akm_output_midi(out_device_name)
  if not table.is_empty(AKM_OUTPUTS) then
    if not out_device_name then
      return
    end
    local valid_name=akm_validate_device_name(out_device_name, AKM_OUTPUTS)
    if not valid_name then
      if (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open) then
        AKM_MIDI_DEVICE_OUT:close()
      end
      AKM_MIDI_DEVICE_OUT=nil
      return
    end
    if (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open and AKM_MIDI_DEVICE_OUT.name==valid_name) then
      return
    end
    if (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open) then
      AKM_MIDI_DEVICE_OUT:close()
      AKM_MIDI_DEVICE_OUT=nil
    end
    AKM_MIDI_DEVICE_OUT=renoise.Midi.create_output_device(valid_name)
  end
end


local function akm_output_midi_invoke(tbl)
  if (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open) then
    local msg = tbl[1]  -- the actual midi message table
    AKM_MIDI_DEVICE_OUT:send(msg)
    print(("%X %X %X | %s"):format(msg[1], msg[2], msg[3], AKM_MIDI_DEVICE_OUT.name))
  end
end


AKM_ESSENTIAL_DAW_CONNECTED=false

-- One-time SysEx handshake the Essential mk3 requires before it will accept ANY
-- LED colour command. Called automatically by akm_essential_set_led below - you
-- shouldn't need to call this directly.
function akm_essential_daw_connect()
  if not (AKM_ESSENTIAL_DAW_CONNECTED) and (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open) then
    AKM_MIDI_DEVICE_OUT:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x0F,0x40,0x5A,0x01,0xF7})
    AKM_ESSENTIAL_DAW_CONNECTED=true
  end
end

-- Colours all 16 pad LEDs using Renoise's own current skin accent colour
-- (AKM_CLR.MARKER, populated by akm_capture_clr_mrk from the user's real
-- Config.xml - orange by default, whatever they've actually customised
-- otherwise). Renoise stores that as 0-255 per channel; our hardware LED
-- protocol wants 0-127, hence the halving. Pad LED ids run 0x1C-0x2B
-- (16 consecutive ids) per the programming guide's table.
function akm_essential_set_pad_leds_to_skin_color()
  local r=math.floor((AKM_CLR.MARKER[1] or 235)/2)
  local g=math.floor((AKM_CLR.MARKER[2] or 235)/2)
  local b=math.floor((AKM_CLR.MARKER[3] or 235)/2)
  for i=0,15 do
    akm_essential_set_led(0x1C+i,r,g,b)
  end
end

-- Pad LED reactivity (flash on press) was tried two ways - real press/release
-- timing, then a fixed-delay timer - and both eventually caused the ALSA
-- sequencer to flood with "Bad address"/"Invalid argument" errors during
-- fast pad playing, badly enough that Renoise gave up logging them. Removed
-- entirely rather than keep tuning the timing. Pads now only get the static
-- skin-colour set once when the tool turns on (akm_essential_set_pad_leds_to_skin_color)
-- and otherwise are untouched by anything LED-related.
function akm_pad_led_on(pad_index)
end

function akm_pad_led_off(pad_index)
end

-- Sets one hardware button's LED to an RGB colour (0-0x7F per channel).
-- button_id is the device's own LED-addressing id (NOT the CC number the
-- button sends when pressed - those are two separate numbering schemes).
function akm_essential_set_led(button_id,r,g,b)
  if (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open) then
    akm_essential_daw_connect()
    AKM_MIDI_DEVICE_OUT:send({0xF0,0x00,0x20,0x6B,0x7F,0x42,0x04,0x01,0x16,button_id,r,g,b,0xF7})
  end
end

-- akm_essential_*_led_sync: one per LED-backed toggle (Play/Rec/Loop/Mixer).
-- These are attached as notifiers on the real Renoise property (see
-- akm_essential_attach_led_observers below) rather than only being called from
-- the button-press functions, so the LED stays correct even if the state
-- changes some other way (mouse, keyboard shortcut, song reaching that state
-- on its own).
function akm_essential_play_led_sync()
  if (song.transport.playing) then
    akm_essential_set_led(0x15,0x00,0x7F,0x00)
  else
    akm_essential_set_led(0x15,0x00,0x18,0x00)
  end
end

function akm_essential_edit_led_sync()
  if (song.transport.edit_mode) then
    akm_essential_set_led(0x16,0x7F,0x00,0x00)
  else
    akm_essential_set_led(0x16,0x18,0x00,0x00)
  end
end

function akm_essential_loop_led_sync()
  if (song.transport.loop_pattern) then
    akm_essential_set_led(0x10,0x7F,0x7F,0x00)
  else
    akm_essential_set_led(0x10,0x18,0x18,0x00)
  end
end

function akm_essential_mixer_led_sync()
  local mfm=renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
  if (rna.window.active_middle_frame==mfm) then
    akm_essential_set_led(0x07,0x7F,0x7F,0x7F)
  else
    akm_essential_set_led(0x07,0x18,0x18,0x18)
  end
end

-- Attaches the four LED-sync functions above as permanent notifiers on the
-- real Renoise properties. Called once at load and again on every new-song
-- event (see the app_new_document_observable hook further down) since a fresh
-- song document needs its own notifiers re-attached. Safe to call repeatedly -
-- has_notifier guards against attaching the same one twice.
function akm_essential_attach_led_observers()
  if (song and song.transport) then
    if not (song.transport.playing_observable:has_notifier(akm_essential_play_led_sync)) then
      song.transport.playing_observable:add_notifier(akm_essential_play_led_sync)
    end
    if not (song.transport.edit_mode_observable:has_notifier(akm_essential_edit_led_sync)) then
      song.transport.edit_mode_observable:add_notifier(akm_essential_edit_led_sync)
    end
    if not (song.transport.loop_pattern_observable:has_notifier(akm_essential_loop_led_sync)) then
      song.transport.loop_pattern_observable:add_notifier(akm_essential_loop_led_sync)
    end
  end
  if (rna and rna.window and rna.window.active_middle_frame_observable) then
    if not (rna.window.active_middle_frame_observable:has_notifier(akm_essential_mixer_led_sync)) then
      rna.window.active_middle_frame_observable:add_notifier(akm_essential_mixer_led_sync)
    end
  end
end

rnt.app_new_document_observable:add_notifier(akm_essential_attach_led_observers)
akm_essential_attach_led_observers()






--state x3 buttons

--general functions

-------------------------------------------------------------------------------------------------
--keylab mk3 49. rules
-------------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------------
--midi functions
-------------------------------------------------------------------------------------------------
-- This is the heart of the tool: akm_input_midi opens the raw MIDI input device
-- and installs midi_callback below as its handler. Every message from the
-- keyboard passes through midi_callback's long if/then chain, matched by exact
-- status byte + CC/note number. This is a completely separate, parallel
-- listener from Renoise's own "Preferences > MIDI" input on the same port -
-- see the "Ignore specific controllers" setup step for why that matters
-- (both listeners see every message; Renoise's own one will happily record
-- unmapped CCs into the pattern as raw effect commands unless told not to).
local AKM_MIDI_DEVICE_IN=nil

local function akm_input_midi(in_device_name)
  if not table.is_empty(AKM_INPUTS) then
    local valid_name=akm_validate_device_name(in_device_name, AKM_INPUTS)
    if (in_device_name==nil or valid_name==nil) then
      if (AKM_MIDI_DEVICE_IN and AKM_MIDI_DEVICE_IN.is_open) then AKM_MIDI_DEVICE_IN:close() end
      AKM_MIDI_DEVICE_IN=nil
      return
    end

    -- akm_knob_last: remembers each knob's previous raw reading so akm_knob_dir
    -- (used only by the two relative-movement knobs, NC/EC-nav and step-length -
    -- see the file header) can tell which direction it moved.
    local akm_knob_last = {}
    local function midi_callback(message)
      assert(#message>=1)
      for i=1,#message do assert(message[i]>=0 and message[i]<=0xFF) end

      --- ---invoke commands
      --pads (Essential mk3): Note-On on channel 11 (0x9A - NOT channel 10/0x99
      --as tested much earlier in this project; confirmed via raw MIDI sniffing
      --that the actual channel had shifted since). Real note layout isn't a
      --simple contiguous range either - confirmed the same way. Bank A:
      --pads 1-4 = notes 40-43, pads 5-8 = notes 36-39. Bank B: pads 1-4 =
      --notes 48-51, pads 5-8 = notes 44-47. LED index (0-15) follows physical
      --pad/bank position, not the note number itself.
      --flash the pad's LED on press only - no other mapping, note passes
      --through untouched to Renoise's own note input for sound.

      if (message[1]==0x9A and message[2]==40) then
        if (message[3]>0) then akm_pad_led_on(0) else akm_pad_led_off(0) end
        return
      end
      if (message[1]==0x8A and message[2]==40) then akm_pad_led_off(0) return end
      if (message[1]==0x9A and message[2]==41) then
        if (message[3]>0) then akm_pad_led_on(1) else akm_pad_led_off(1) end
        return
      end
      if (message[1]==0x8A and message[2]==41) then akm_pad_led_off(1) return end
      if (message[1]==0x9A and message[2]==42) then
        if (message[3]>0) then akm_pad_led_on(2) else akm_pad_led_off(2) end
        return
      end
      if (message[1]==0x8A and message[2]==42) then akm_pad_led_off(2) return end
      if (message[1]==0x9A and message[2]==43) then
        if (message[3]>0) then akm_pad_led_on(3) else akm_pad_led_off(3) end
        return
      end
      if (message[1]==0x8A and message[2]==43) then akm_pad_led_off(3) return end
      if (message[1]==0x9A and message[2]==36) then
        if (message[3]>0) then akm_pad_led_on(4) else akm_pad_led_off(4) end
        return
      end
      if (message[1]==0x8A and message[2]==36) then akm_pad_led_off(4) return end
      if (message[1]==0x9A and message[2]==37) then
        if (message[3]>0) then akm_pad_led_on(5) else akm_pad_led_off(5) end
        return
      end
      if (message[1]==0x8A and message[2]==37) then akm_pad_led_off(5) return end
      if (message[1]==0x9A and message[2]==38) then
        if (message[3]>0) then akm_pad_led_on(6) else akm_pad_led_off(6) end
        return
      end
      if (message[1]==0x8A and message[2]==38) then akm_pad_led_off(6) return end
      if (message[1]==0x9A and message[2]==39) then
        if (message[3]>0) then akm_pad_led_on(7) else akm_pad_led_off(7) end
        return
      end
      if (message[1]==0x8A and message[2]==39) then akm_pad_led_off(7) return end
      if (message[1]==0x9A and message[2]==48) then
        if (message[3]>0) then akm_pad_led_on(8) else akm_pad_led_off(8) end
        return
      end
      if (message[1]==0x8A and message[2]==48) then akm_pad_led_off(8) return end
      if (message[1]==0x9A and message[2]==49) then
        if (message[3]>0) then akm_pad_led_on(9) else akm_pad_led_off(9) end
        return
      end
      if (message[1]==0x8A and message[2]==49) then akm_pad_led_off(9) return end
      if (message[1]==0x9A and message[2]==50) then
        if (message[3]>0) then akm_pad_led_on(10) else akm_pad_led_off(10) end
        return
      end
      if (message[1]==0x8A and message[2]==50) then akm_pad_led_off(10) return end
      if (message[1]==0x9A and message[2]==51) then
        if (message[3]>0) then akm_pad_led_on(11) else akm_pad_led_off(11) end
        return
      end
      if (message[1]==0x8A and message[2]==51) then akm_pad_led_off(11) return end
      if (message[1]==0x9A and message[2]==44) then
        if (message[3]>0) then akm_pad_led_on(12) else akm_pad_led_off(12) end
        return
      end
      if (message[1]==0x8A and message[2]==44) then akm_pad_led_off(12) return end
      if (message[1]==0x9A and message[2]==45) then
        if (message[3]>0) then akm_pad_led_on(13) else akm_pad_led_off(13) end
        return
      end
      if (message[1]==0x8A and message[2]==45) then akm_pad_led_off(13) return end
      if (message[1]==0x9A and message[2]==46) then
        if (message[3]>0) then akm_pad_led_on(14) else akm_pad_led_off(14) end
        return
      end
      if (message[1]==0x8A and message[2]==46) then akm_pad_led_off(14) return end
      if (message[1]==0x9A and message[2]==47) then
        if (message[3]>0) then akm_pad_led_on(15) else akm_pad_led_off(15) end
        return
      end
      if (message[1]==0x8A and message[2]==47) then akm_pad_led_off(15) return end

      --play, record, loop (Essential mk3: plain CC, channel 1, 127=press/0=release)
      if (message[1]==0xB0 and message[2]==21 and message[3]==0x00) then return akm_play() end
      if (message[1]==0xB0 and message[2]==22 and message[3]==0x00) then return akm_edit_mode() end
      if (message[1]==0xB0 and message[2]==24 and message[3]==0x00) then return akm_loop() end
      
      --metro, undo, redo
      if (message[1]==0xB0 and message[2]==27 and message[3]==0x00) then return akm_metro() end
      if (message[1]==0xB0 and message[2]==20 and message[3]==0x00) then return akm_stop() end
      if (message[1]==0xB0 and message[2]==23 and message[3]==0x7F) then return akm_tap_tempo() end
      if (message[1]==0xB0 and message[2]==41 and message[3]==0x00) then return akm_quantize() end
      if (message[1]==0xB0 and message[2]==119 and message[3]==0x00) then return akm_toggle_mixer() end
      --Save button -> quick-save if the song already has a file, else prompt
      if (message[1]==0xB0 and message[2]==40 and message[3]==0x00) then
        if (song.file_name~=nil and song.file_name~="" and type(rna.save_song)=="function") then
          rna:save_song()
        else
          akm_save_off()
        end
        return
      end
      if (message[1]==0xB0 and message[2]==25 and message[3]==0x00) then return akm_pad6() end --previous track
      if (message[1]==0xB0 and message[2]==26 and message[3]==0x00) then return akm_pad7() end --next track
      --dedicated Undo/Redo buttons -> real Renoise undo/redo
      if (message[1]==0xB0 and message[2]==42 and message[3]==0x00) then return akm_song_undo() end
      if (message[1]==0xB0 and message[2]==43 and message[3]==0x00) then return akm_song_redo() end
      
      --browses center controls, dial (instruments navigator) - press=CC117, turn=CC116
      if (message[1]==0xB0 and message[2]==117 and message[3]==0x7F) then return akm_button_dial_add_timer() end
      if (message[1]==0xB0 and message[2]==117 and message[3]==0x00) then return akm_button_dial_remove_timer() end
      if (message[1]==0xB0 and message[2]==116 and message[3]>=0x41) then return akm_left_dial() end
      if (message[1]==0xB0 and message[2]==116 and message[3]<=0x40) then return akm_right_dial() end
      
      --Essential mk3 knobs send ABSOLUTE 0-127 values (CC 96-104), not relative turns.
      --This tracks the last value per knob and derives a direction from it. Only
      --used by knobs 8 (NC/EC nav) and 9 (step length) now - every other knob
      --was converted to direct position-mapping (akm_knob_*_val functions
      --below) once we found this approach gets stuck at the knob's own 0/127
      --firmware limit until you reverse direction. The delta wraparound
      --correction (+-128) below is a safety net for endless/continuous
      --encoders that roll over; it's a no-op for a normal bounded turn.
      local function akm_knob_dir(cc, value, prev_fn, next_fn)
        local last = akm_knob_last[cc]
        akm_knob_last[cc] = value
        if (last == nil) then return end
        local delta = value - last
        if (delta > 64) then delta = delta - 128
        elseif (delta < -64) then delta = delta + 128
        end
        if (delta > 0) then return next_fn() end
        if (delta < 0) then return prev_fn() end
      end
      
      --knob 1 note
      if (message[1]==0xB0 and message[2]==96) then return akm_knob_note_val(message[3]) end
      
      --knob 2 instrument
      if (message[1]==0xB0 and message[2]==97) then return akm_knob_instrument_val(message[3]) end
      
      --knob 3 volume
      if (message[1]==0xB0 and message[2]==98) then return akm_knob_volume_val(message[3]) end
      
      --knob 4 panning
      if (message[1]==0xB0 and message[2]==99) then return akm_knob_panning_val(message[3]) end
      
      --knob 5 delay
      if (message[1]==0xB0 and message[2]==100) then return akm_knob_delay_val(message[3]) end
      
      --knob 6 sample fx
      if (message[1]==0xB0 and message[2]==101) then return akm_knob_fx_val(message[3]) end
      
      --knob 7 effects
      if (message[1]==0xB0 and message[2]==102) then return akm_knob_fx_amo_val(message[3]) end

      --knob 8 note columns navigation
      if (message[1]==0xB0 and message[2]==103) then return akm_knob_dir(103,message[3],akm_previous_nc_ec,akm_next_nc_ec) end
      
      --knob 9 step length
      if (message[1]==0xB0 and message[2]==104) then return akm_knob_dir(104,message[3],function() akm_step_length(1) end,function() akm_step_length(-1) end) end
      
      --fader 1 note
      if (message[1]==0xB0 and message[2]==105 and message[2]<=0x7F and message[3]>=0x64) then return akm_nc_note_val(vws.AKM_VFD_VAL_1_1.value,1) end
      if (message[1]==0xB0 and message[2]==105 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_nc_note_val(vws.AKM_VFD_VAL_1_2.value,2) end
      if (message[1]==0xB0 and message[2]==105 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_nc_note_val(vws.AKM_VFD_VAL_1_3.value,3) end
      if (message[1]==0xB0 and message[2]==105 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_nc_note_val(vws.AKM_VFD_VAL_1_4.value,4) end
      if (message[1]==0xB0 and message[2]==105 and message[2]<=0x7F and message[3]<0x19) then return akm_nc_note_val(vws.AKM_VFD_VAL_1_5.value,5) end
      
      --fader 2 instrument
      --if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]>=0x40) then return akm_nc_instrument_val(AKM_VPD_VALUES[1]) end
      --if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]<0x40) then return  akm_nc_instrument_val(255) end
      if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]>=0x64) then return akm_nc_instrument_val(vws.AKM_VFD_VAL_2_1.value,1) end
      if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_nc_instrument_val(vws.AKM_VFD_VAL_2_2.value,2) end
      if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_nc_instrument_val(vws.AKM_VFD_VAL_2_3.value,3) end
      if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_nc_instrument_val(vws.AKM_VFD_VAL_2_4.value,4) end
      if (message[1]==0xB0 and message[2]==106 and message[2]<=0x7F and message[3]<0x19) then return akm_nc_instrument_val(vws.AKM_VFD_VAL_2_5.value,5) end
      
      --fader 3 volume
      --if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]>=0x40) then return akm_nc_volume_val(AKM_VPD_VALUES[1]) end
      --if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]<0x40) then return akm_nc_volume_val(255) end
      if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]>=0x64) then return akm_nc_volume_val(vws.AKM_VFD_VAL_3_1.value,1) end
      if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_nc_volume_val(vws.AKM_VFD_VAL_3_2.value,2) end
      if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_nc_volume_val(vws.AKM_VFD_VAL_3_3.value,3) end
      if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_nc_volume_val(vws.AKM_VFD_VAL_3_4.value,4) end
      if (message[1]==0xB0 and message[2]==107 and message[2]<=0x7F and message[3]<0x19) then return akm_nc_volume_val(vws.AKM_VFD_VAL_3_5.value,5) end
      
      --fader 4 panning
      --if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]>=0x5F) then return akm_nc_panning_val(AKM_VPD_VALUES[2]) end
      --if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x5F and message[3]>=0x3F) then return akm_nc_panning_val(AKM_VPD_VALUES[3]) end
      --if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x3F and message[3]>=0x0F) then return akm_nc_panning_val(AKM_VPD_VALUES[4]) end
      --if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x0F) then return akm_nc_panning_val(255) end
      if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]>=0x64) then return akm_nc_panning_val(vws.AKM_VFD_VAL_4_1.value,1) end
      if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_nc_panning_val(vws.AKM_VFD_VAL_4_2.value,2) end
      if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_nc_panning_val(vws.AKM_VFD_VAL_4_3.value,3) end
      if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_nc_panning_val(vws.AKM_VFD_VAL_4_4.value,4) end
      if (message[1]==0xB0 and message[2]==108 and message[2]<=0x7F and message[3]<0x19) then return akm_nc_panning_val(vws.AKM_VFD_VAL_4_5.value,5) end
      
      --fader 5 delay
      --if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]>=0x40) then return akm_nc_delay_val(AKM_VPD_VALUES[5]) end
      --if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]<0x40) then return akm_nc_delay_val(0) end
      if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]>=0x64) then return akm_nc_delay_val(vws.AKM_VFD_VAL_5_1.value,1) end
      if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_nc_delay_val(vws.AKM_VFD_VAL_5_2.value,2) end
      if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_nc_delay_val(vws.AKM_VFD_VAL_5_3.value,3) end
      if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_nc_delay_val(vws.AKM_VFD_VAL_5_4.value,4) end
      if (message[1]==0xB0 and message[2]==109 and message[2]<=0x7F and message[3]<0x19) then return akm_nc_delay_val(vws.AKM_VFD_VAL_5_5.value,5) end
      
      --fader 6 sfx/fx
      if (message[1]==0xB0 and message[2]==110 and message[2]<=0x7F and message[3]>=0x64) then return akm_sfx_fx_val(vws.AKM_VFD_VAL_6_1.value,1) end
      if (message[1]==0xB0 and message[2]==110 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_sfx_fx_val(vws.AKM_VFD_VAL_6_2.value,2) end
      if (message[1]==0xB0 and message[2]==110 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_sfx_fx_val(vws.AKM_VFD_VAL_6_3.value,3) end
      if (message[1]==0xB0 and message[2]==110 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_sfx_fx_val(vws.AKM_VFD_VAL_6_4.value,4) end
      if (message[1]==0xB0 and message[2]==110 and message[2]<=0x7F and message[3]<0x19) then return akm_sfx_fx_val(vws.AKM_VFD_VAL_6_5.value,5) end

      --fader 7 amount sfx/fx
      if (message[1]==0xB0 and message[2]==111 and message[2]<=0x7F and message[3]>=0x64) then return akm_amount_val(vws.AKM_VFD_VAL_7_1.value,1) end
      if (message[1]==0xB0 and message[2]==111 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_amount_val(vws.AKM_VFD_VAL_7_2.value,2) end
      if (message[1]==0xB0 and message[2]==111 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_amount_val(vws.AKM_VFD_VAL_7_3.value,3) end
      if (message[1]==0xB0 and message[2]==111 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_amount_val(vws.AKM_VFD_VAL_7_4.value,4) end
      if (message[1]==0xB0 and message[2]==111 and message[2]<=0x7F and message[3]<0x19) then return akm_amount_val(vws.AKM_VFD_VAL_7_5.value,5) end
              
      --fader 8 note/effect column
      if (message[1]==0xB0 and message[2]==112 and message[2]<=0x7F and message[3]>=0x64) then return akm_nc_ec_val(vws.AKM_VFD_VAL_8_1.value,1) end
      if (message[1]==0xB0 and message[2]==112 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_nc_ec_val(vws.AKM_VFD_VAL_8_2.value,2) end
      if (message[1]==0xB0 and message[2]==112 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_nc_ec_val(vws.AKM_VFD_VAL_8_3.value,3) end
      if (message[1]==0xB0 and message[2]==112 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_nc_ec_val(vws.AKM_VFD_VAL_8_4.value,4) end
      if (message[1]==0xB0 and message[2]==112 and message[2]<=0x7F and message[3]<0x19) then return akm_nc_ec_val(vws.AKM_VFD_VAL_8_5.value,5) end
      
      --fader 9 step length
      if (message[1]==0xB0 and message[2]==113 and message[2]<=0x7F and message[3]>=0x64) then return akm_sq_step_val(vws.AKM_VFD_VAL_9_1.value,1) end
      if (message[1]==0xB0 and message[2]==113 and message[2]<=0x7F and message[3]<0x64 and message[3]>=0x4B) then return akm_sq_step_val(vws.AKM_VFD_VAL_9_2.value,2) end
      if (message[1]==0xB0 and message[2]==113 and message[2]<=0x7F and message[3]<0x4B and message[3]>=0x32) then return akm_sq_step_val(vws.AKM_VFD_VAL_9_3.value,3) end
      if (message[1]==0xB0 and message[2]==113 and message[2]<=0x7F and message[3]<0x32 and message[3]>=0x19) then return akm_sq_step_val(vws.AKM_VFD_VAL_9_4.value,4) end
      if (message[1]==0xB0 and message[2]==113 and message[2]<=0x7F and message[3]<0x19) then return akm_sq_step_val(vws.AKM_VFD_VAL_9_5.value,5) end
      
      
      --text sysex
      --if (message[1]==0xB0 and message[2]==0x74 and message[3]==0x7F) then print("Category") end
      --if (message[1]==0xB0 and message[2]==0x75 and message[3]==0x7F) then print("Preset") end
      --if (message[1]==0xB0 and message[2]==0x76 and message[3]==0x7F) then print("Analog Lab") end
      --{0xF0,0x00,0x20,0x6B,0x7F,0x42,0x02,0x00,0x00,0x15,0x7F,0xF7}

      --pitch bend and mod wheel (CC1) are left untouched, so they can be freely macro-mapped per-instrument in Renoise
    end
    if (AKM_MIDI_DEVICE_IN and AKM_MIDI_DEVICE_IN.is_open and AKM_MIDI_DEVICE_IN.name==valid_name) then
      return
    end
    if (AKM_MIDI_DEVICE_IN and AKM_MIDI_DEVICE_IN.is_open) then
      AKM_MIDI_DEVICE_IN:close()
      AKM_MIDI_DEVICE_IN=nil
    end
    AKM_MIDI_DEVICE_IN=renoise.Midi.create_input_device(valid_name,midi_callback)
  end
end


local function akm_check_midi_on()
  local function show_mess()
    AKM_ON_OFF=true akm_on_off()
    if (vws.AKM_PP_DEVICE_NAME.value==1) then
      return rna:show_warning("AKM: The in device \"KeyLab 49 mk3 (DAW)\" is not connected!\n\n"
                            .."Do you have the \"KeyLab 49 mk3\" MIDI controller\nconnected correctly?")
    end
    if (vws.AKM_PP_DEVICE_NAME.value==2) then
      return rna:show_warning("AKM: The in device \"KeyLab 61 mk3 (DAW)\" is not connected!\n\n"
                            .."Do you have the \"KeyLab 61 mk3\" MIDI controller\nconnected correctly?")
    end
    if (vws.AKM_PP_DEVICE_NAME.value==3) then
      return rna:show_warning("AKM: The in device \"KeyLab 88 mk3 (DAW)\" is not connected!\n\n"
                            .."Do you have the \"KeyLab 88 mk3\" MIDI controller\nconnected correctly?")
    end
    if (vws.AKM_PP_DEVICE_NAME.value==4) then
      return rna:show_warning("AKM: The in device \"KeyLab Essential 49 mk3 (DAW)\" is not connected!\n\n"
                            .."Do you have the \"KeyLab Essential 49 mk3\" MIDI controller\nconnected correctly?")
    end
    if (vws.AKM_PP_DEVICE_NAME.value==5) then
      return rna:show_warning("AKM: The in device \"KeyLab Essential 61 mk3 (DAW)\" is not connected!\n\n"
                            .."Do you have the \"KeyLab Essential 61 mk3\" MIDI controller\nconnected correctly?")
    end
    if (vws.AKM_PP_DEVICE_NAME.value==6) then
      return rna:show_warning("AKM: The in device \"KeyLab Essential 88 mk3 (DAW)\" is not connected!\n\n"
                            .."Do you have the \"KeyLab Essential 88 mk3\" MIDI controller\nconnected correctly?")
    end
  end

  local input_devices=renoise.Midi.available_input_devices()
  local output_devices=renoise.Midi.available_output_devices()

  AKM_INPUTS={}
  AKM_OUTPUTS={}

  for i=1,#input_devices do
    AKM_INPUTS[i]=input_devices[i]
  end

  for i=1,#output_devices do
    AKM_OUTPUTS[i]=output_devices[i]
  end

  if not table.is_empty(AKM_INPUTS) then
    vws.AKM_PP_DEVICE_IN.items=AKM_INPUTS
  end

  if not table.is_empty(AKM_OUTPUTS) then
    vws.AKM_PP_DEVICE_OUT.items=AKM_OUTPUTS
  end

  local function open_input_by_name(saved_name)
    local valid_name=akm_validate_device_name(saved_name, AKM_INPUTS)
    if (not valid_name) then return false end
    local _, found_index=akm_find_device_by_name(AKM_INPUTS, valid_name)
    if (found_index ~= nil) then vws.AKM_PP_DEVICE_IN.value=found_index end
    AKM_ACTIVATE=true
    akm_input_midi(valid_name)
    renoise.tool().preferences.saved_in_device.value=valid_name
    return true
  end

  local function open_output_by_name(saved_name)
    local valid_name=akm_validate_device_name(saved_name, AKM_OUTPUTS)
    if (not valid_name) then return false end
    local _, found_index=akm_find_device_by_name(AKM_OUTPUTS, valid_name)
    if (found_index ~= nil) then vws.AKM_PP_DEVICE_OUT.value=found_index end
    AKM_ACTIVATE=true
    akm_output_midi(valid_name)
    renoise.tool().preferences.saved_out_device.value=valid_name
    return true
  end

  if (AKM_LOCK_IO_DEVICES) then
    if not table.is_empty(AKM_INPUTS) then
      local current_in=AKM_INPUTS[vws.AKM_PP_DEVICE_IN.value] or AKM_INPUTS[1]
      local in_name=akm_validate_device_name(current_in, AKM_INPUTS)
      if (in_name ~= nil) then
        vws.AKM_PP_DEVICE_IN.value=(vws.AKM_PP_DEVICE_IN.value or 1)
        renoise.tool().preferences.saved_in_device.value=in_name
        AKM_ACTIVATE=true
        akm_input_midi(in_name)
      end
    end
    if not table.is_empty(AKM_OUTPUTS) then
      local current_out=AKM_OUTPUTS[vws.AKM_PP_DEVICE_OUT.value] or AKM_OUTPUTS[1]
      local out_name=akm_validate_device_name(current_out, AKM_OUTPUTS)
      if (out_name ~= nil) then
        vws.AKM_PP_DEVICE_OUT.value=(vws.AKM_PP_DEVICE_OUT.value or 1)
        renoise.tool().preferences.saved_out_device.value=out_name
        AKM_ACTIVATE=true
        akm_output_midi(out_name)
      end
    end
    return
  end

  if (table.is_empty(AKM_INPUTS) or table.is_empty(AKM_OUTPUTS)) then
    return show_mess()
  end

  local saved_in_device=akm_trim_device_name(renoise.tool().preferences.saved_in_device.value)
  local saved_out_device=akm_trim_device_name(renoise.tool().preferences.saved_out_device.value)

  if (not open_input_by_name(saved_in_device)) then
    local first=AKM_INPUTS[1]
    if (first == nil) then return show_mess() end
    local first_name=akm_trim_device_name(first)
    vws.AKM_PP_DEVICE_IN.value=1
    renoise.tool().preferences.saved_in_device.value=first_name
    AKM_ACTIVATE=true
    akm_input_midi(first_name)
  end

  if (not open_output_by_name(saved_out_device)) then
    local first=AKM_OUTPUTS[1]
    if (first == nil) then return show_mess() end
    local first_name=akm_trim_device_name(first)
    vws.AKM_PP_DEVICE_OUT.value=1
    renoise.tool().preferences.saved_out_device.value=first_name
    AKM_ACTIVATE=true
    akm_output_midi(first_name)
  end

  akm_store_selected_devices()
end

local function akm_check_midi_off()
  --midi in
  if (AKM_MIDI_DEVICE_IN and AKM_MIDI_DEVICE_IN.is_open) then
    AKM_MIDI_DEVICE_IN:close()
    AKM_MIDI_DEVICE_IN=nil
    --print("AKM: dev_in: off")
  else
    --print("AKM: dev_in: this in device not exist!")
  end 
  --midi out 
  if (AKM_MIDI_DEVICE_OUT and AKM_MIDI_DEVICE_OUT.is_open) then
    AKM_MIDI_DEVICE_OUT:close()
    AKM_MIDI_DEVICE_OUT=nil
    --print("AKM dev_out: off")
  else
    --print("AKM dev_out: this out device not exist!")
  end
end



-------------------------------------------------------------------------------------------------
--api notifiers
-------------------------------------------------------------------------------------------------
local function akm_ntf_play()
  local play_on={{0x90,0x5E,0x7F}, "play_on"}
  local play_off={{0x90,0x5E,0x00}, "play_off"}
  if (song.transport.playing) then
    akm_output_midi_invoke(play_on)
    vws.AKM_BTT_DAW_B_4.color=AKM_CLR.MARKER
  else
    akm_output_midi_invoke(play_off)
    vws.AKM_BTT_DAW_B_4.color=AKM_CLR.DEFAULT
  end
end

local function akm_ntf_rec()
  local rec_on={{0x90,0x5F,0x7F}, "rec_on"}
  local rec_off={{0x90,0x5F,0x00}, "rec_off"}
  if (song.transport.edit_mode) then
    akm_output_midi_invoke(rec_on)
    vws.AKM_BTT_DAW_B_5.color=AKM_CLR.MARKER
  else
    akm_output_midi_invoke(rec_off)
    vws.AKM_BTT_DAW_B_5.color=AKM_CLR.DEFAULT
  end
end

local function akm_ntf_loop()
  local loop_on={{0x90,0x56,0x7F}, "loop_on"}
  local loop_off={{0x90,0x56,0x00}, "loop_off"}
  if (song.transport.loop_pattern) then
    akm_output_midi_invoke(loop_on)
    vws.AKM_BTT_DAW_B_6.color=AKM_CLR.MARKER
  else
    akm_output_midi_invoke(loop_off)
    vws.AKM_BTT_DAW_B_6.color=AKM_CLR.DEFAULT
  end
end

local function akm_ntf_metro()
  local metro_on={{0x90,0x59,0x7F}, "metro_on"}
  local metro_off={{0x90,0x59,0x00}, "metro_off"}
  if (vws.AKM_BTT_DAW_A_9 ~= nil) then
    if (song.transport.metronome_enabled) then
      akm_output_midi_invoke(metro_on)
      vws.AKM_BTT_DAW_A_9.color=AKM_CLR.MARKER
    else
      akm_output_midi_invoke(metro_off)
      vws.AKM_BTT_DAW_A_9.color=AKM_CLR.DEFAULT
    end
  end
end

local function akm_ntf_follow()
  if (song.transport.follow_player) then
    vws.AKM_BTT_DAW_A_10.color=AKM_CLR.MARKER
  else
    vws.AKM_BTT_DAW_A_10.color=AKM_CLR.DEFAULT
  end
end

local function akm_ntf_middle_frame()
  if not (rna.window.instrument_editor_is_detached) then
    for sel=1,9 do
      if (rna.window.active_middle_frame==sel) then
        vws.AKM_ROT_DIAL.value=sel-1
        break
      end
    end
  else
    if (rna.window.active_middle_frame<=2) then
      vws.AKM_ROT_DIAL.value=rna.window.active_middle_frame-1
    else
      --for 3 to 9 NOT WORK!! API bug
      --vws.AKM_ROT_DIAL.value=AKM_WINDOW_FRAME
    end
  end
end

local AKM_SRV=false
local function akm_ntf_sample_record_visible()
end


local function akm_check_notifiers_on()
  --1 check song play
  if not song.transport.playing_observable:has_notifier(akm_ntf_play) then
    song.transport.playing_observable:add_notifier(akm_ntf_play)
  end
  akm_ntf_play()
  --2 check rec
  if not song.transport.edit_mode_observable:has_notifier(akm_ntf_rec) then
    song.transport.edit_mode_observable:add_notifier(akm_ntf_rec)
  end
  akm_ntf_rec()
  --3 check loop
  if not song.transport.loop_pattern_observable:has_notifier(akm_ntf_loop) then
    song.transport.loop_pattern_observable:add_notifier(akm_ntf_loop)
  end
  akm_ntf_loop()
  
  --4 check metro
  if not song.transport.metronome_enabled_observable:has_notifier(akm_ntf_metro) then
    song.transport.metronome_enabled_observable:add_notifier(akm_ntf_metro)
  end
  akm_ntf_metro()
  --5 check undo (follow the player's position)
  if not song.transport.follow_player_observable:has_notifier(akm_ntf_follow) then
    song.transport.follow_player_observable:add_notifier(akm_ntf_follow)
  end
  akm_ntf_follow()
  
  --6 check middle frame selection
  if not rna.window.active_middle_frame_observable:has_notifier(akm_ntf_middle_frame) then
    rna.window.active_middle_frame_observable:add_notifier(akm_ntf_middle_frame)
  end
  akm_ntf_middle_frame()
  
  --7 check sample recording window
  if not rnt:has_timer(akm_ntf_sample_record_visible) then
    rnt:add_timer(akm_ntf_sample_record_visible,100)
  end
end

local function akm_check_notifiers_off()
  --1 check song play
  if song.transport.playing_observable:has_notifier(akm_ntf_play) then
    song.transport.playing_observable:remove_notifier(akm_ntf_play)
  end
  --2 check rec
  if song.transport.edit_mode_observable:has_notifier(akm_ntf_rec) then
    song.transport.edit_mode_observable:remove_notifier(akm_ntf_rec)
  end
  --3 check loop
  if song.transport.loop_pattern_observable:has_notifier(akm_ntf_loop) then
    song.transport.loop_pattern_observable:remove_notifier(akm_ntf_loop)
  end
  
  --4 check metro
  if song.transport.metronome_enabled_observable:has_notifier(akm_ntf_metro) then
    song.transport.metronome_enabled_observable:remove_notifier(akm_ntf_metro)
  end  
  --5 check undo --> (follow the player's position)
  if song.transport.follow_player_observable:has_notifier(akm_ntf_follow) then
    song.transport.follow_player_observable:remove_notifier(akm_ntf_follow)
  end
  --6 check middle frame selection
  if rna.window.active_middle_frame_observable:has_notifier(akm_ntf_middle_frame) then
    rna.window.active_middle_frame_observable:remove_notifier(akm_ntf_middle_frame)
  end
  --7 check sample recording window
  if rnt:has_timer(akm_ntf_sample_record_visible) then
    rnt:remove_timer(akm_ntf_sample_record_visible)
  end 
end



local function akm_force_daw_mode()
end


local function akm_first_select_on()
end


local function akm_restore_controls()
  vws.AKM_TXT_DIGITAL_1.text="Daw\nStandard   MCU"
  vws.AKM_TXT_DIGITAL_2.text="Arturia KeyLab\nmk3"
  
  -- vws.AKM_BTT_LEFT.color=AKM_CLR.DEFAULT
  -- vws.AKM_BTT_RIGHT.color=AKM_CLR.DEFAULT
  vws.AKM_ROT_DIAL.visible=true
  
  for num=6,10 do
    vws[("AKM_BTT_DAW_A_%s"):format(num)].color=AKM_CLR.DEFAULT
  end
  for num=1,6 do
    vws[("AKM_BTT_DAW_B_%s"):format(num)].color=AKM_CLR.DEFAULT
  end
  
end


-------------------------------------------------------------------------------------------------
--viewbuilder
-------------------------------------------------------------------------------------------------
AKM_ON_OFF=false
function akm_on_off()
  if (AKM_ON_OFF) then
    --akm_test_off()
    akm_check_notifiers_off()
    akm_check_midi_off()
    akm_restore_controls()
    vws.AKM_BT_ON_OFF.text="OFF"
    vws.AKM_BT_ON_OFF.color=AKM_CLR.DEFAULT
    AKM_ON_OFF=false
    AKM_ACTIVATE=false
    AKM_STOP_STATUS=false
  else
    akm_check_midi_on()
    if (AKM_ACTIVATE) then
      akm_check_notifiers_on()
      akm_first_select_on()
      --akm_force_daw_mode()
      vws.AKM_BT_ON_OFF.text="ON"
      vws.AKM_BT_ON_OFF.color=AKM_CLR.MARKER
      AKM_ON_OFF=true
      akm_essential_set_pad_leds_to_skin_color()
    end
  end
end


local function akm_lock_io_devices()
  if (AKM_LOCK_IO_DEVICES) then
    AKM_LOCK_IO_DEVICES=false
    vws.AKM_BT_LOCK_IO_DEVICES.bitmap="ico/padlock_close_ico.png"
    vws.AKM_BT_LOCK_IO_DEVICES.color=AKM_CLR.MARKER
    vws.AKM_PP_DEVICE_IN.active=false
    vws.AKM_PP_DEVICE_OUT.active=false
  else
    AKM_LOCK_IO_DEVICES=true
    vws.AKM_BT_LOCK_IO_DEVICES.color=AKM_CLR.DEFAULT
    vws.AKM_BT_LOCK_IO_DEVICES.bitmap="ico/padlock_open_ico.png"
    vws.AKM_PP_DEVICE_IN.active=true
    vws.AKM_PP_DEVICE_OUT.active=true
  end
end



local AKM_SHOW_HIDE=true
local function akm_show_hide()
  if (AKM_SHOW_HIDE) then
    vws.AKM_ROW_TOP_1.visible=false
    vws.AKM_ROW_TOP_2.visible=false
    vws.AKM_MAIN_PANELS.visible=false
    vws.AKM_BT_SHOW_HIDE.bitmap="ico/compact_off_ico.png"
    vws.AKM_BT_SHOW_HIDE.color=AKM_CLR.MARKER
    AKM_SHOW_HIDE=false  
  else
    vws.AKM_ROW_TOP_1.visible=true
    vws.AKM_ROW_TOP_2.visible=true
    vws.AKM_MAIN_PANELS.visible=true
    vws.AKM_BT_SHOW_HIDE.bitmap="ico/compact_on_ico.png"
    vws.AKM_BT_SHOW_HIDE.color=AKM_CLR.DEFAULT
    AKM_SHOW_HIDE=true
  end
end



local function akm_about()
  if (vws.AKM_PNL_LOWER.visible) then
    vws.AKM_BT_ABOUT.color=AKM_CLR.DEFAULT
    vws.AKM_PNL_LOWER.visible=false
  else    
    vws.AKM_BT_ABOUT.color=AKM_CLR.MARKER
    vws.AKM_PNL_LOWER.visible=true
  end
end



local function akm_upper_panel()
  local top_panel=vb:row{
    --margin=2,
    id="AKM_PNL_TOP",
    vb:button{
      id="AKM_BT_ON_OFF",
      height=21,
      width=37,
      text="OFF",
      notifier=function() akm_on_off() end,
      tooltip="On/off to make a bridge between the selected device & Renoise."
    },
    vb:space{width=18},
    vb:button{
      id="AKM_BT_INJECT_TO_COPY",
      height=21,
      width=45,
      bitmap="ico/patch_mappings_copy_ico.png",
      notifier=function() patch_and_reload(true) end,
      tooltip="Inject Pad MIDI mappings to a copy of this song with _keylab postfix."
    },
    vb:button{
      id="AKM_BT_INJECT_HERE",
      height=21,
      width=45,
      bitmap="ico/patch_mappings_ico.png",
      notifier=function() patch_and_reload(false) end,
      tooltip="Inject Pad MIDI mappings to this song and save"
    },
    vb:text{
      height=21,
      width=54,
      align="right",
      text="Name "
    },
    vb:popup{
      id="AKM_PP_DEVICE_NAME",
      height=21,
      width=181,
      value=renoise.tool().preferences.default_device_index.value,
      items=AKM_DEVICE_NAME,
      notifier=function(v)
        renoise.tool().preferences.default_device_index.value=v
        if (AKM_ON_OFF) then return akm_check_midi_off(), akm_check_midi_on() end
      end,
      tooltip="List of the names of supported devices. Your choice is remembered across restarts."
    },
    vb:row{
      id="AKM_ROW_TOP_1",
      vb:text{
        height=21,
        width=71,
        align="right",
        font="bold",
        text="In Device "
      },
      vb:popup{
        id="AKM_PP_DEVICE_IN",
        active=false,
        height=21,
        width=183,
        value=1,
        items=AKM_INPUTS,
        notifier=function() if (AKM_ON_OFF) then return akm_check_midi_off(), akm_check_midi_on() end end,
        tooltip="List of available in devices."
      },
      vb:text{
        height=21,
        width=81,
        align="right",
        font="bold",
        text="Out Device "
      },
      vb:popup{
        id="AKM_PP_DEVICE_OUT",
        active=false,
        height=21,
        width=183,
        value=1,
        items=AKM_OUTPUTS,
        notifier=function() if (AKM_ON_OFF) then return akm_check_midi_off(), akm_check_midi_on() end end,
        tooltip="List of available out devices."
      },
      vb:button{
        id="AKM_BT_LOCK_IO_DEVICES",
        height=21,
        width=37,
        bitmap="ico/padlock_close_ico.png",
        color=AKM_CLR.MARKER,
        notifier=function() akm_lock_io_devices() end,
        tooltip="Lock/unlock the selection of in/out devices.\nAlways use the \"KeyLab mk3 (DAW)\" in this window.\n"..
                "Do not use the the \"KeyLab mk3 (DAW)\" in:\nReniose: Edit / Preferences / MIDI: \"In device X...\" & \"Out device...\"."
      }
    },
    vb:button{
      id="AKM_BT_SHOW_HIDE",
      height=21,
      width=37,
      bitmap="ico/compact_on_ico.png",
      notifier=function() akm_show_hide() end,
      tooltip="Show/hide the controls."
    },
    vb:row{
      id="AKM_ROW_TOP_2",
      vb:space{width=4},
      vb:button{
        id="AKM_BT_ABOUT",
        height=21,
        width=37,
        bitmap="ico/question_ico.png",
        notifier=function() akm_about() end,
        tooltip=("Show/hide about %s info panel."):format(akm_main_title)
      }
    }
  }
  return top_panel
end


--[[
local function akm_mp_pads()
  local pads_panel=vb:row{
    id="AKM_PNL_PADS",
  }
  return pads_panel
end
]]


local function akm_mp_daw()
  class "Akm_Button_A"
  function Akm_Button_A:__init(num)
    local tbl_txt_a={"Solo","Mute","Record","u View","l View","Save","Undo","Redo","Metro","Follow"}
    local tbl_tlt_a={
      "Select 1: Solo On/Off current track.\n"..
      "Select 2: Clear current row.\n"..
      "Select 3: n/a.\n"..
      "Select 4: n/a.\n"..
      "Select 5: n/a.\n"..
      "Select 6: n/a.\n"..
      "Select 7: n/a.\n"..
      "Select 8: n/a.",
      
      "Select 1: Mute/On/Off current track.\n"..
      "Select 2: Clear current note/effect column.\n"..
      "Select 3: n/a.\n"..
      "Select 4: n/a.\n"..
      "Select 5: n/a.\n"..
      "Select 6: n/a.\n"..
      "Select 7: n/a.\n"..
      "Select 8: n/a.",
      
      "Select 1: Show/hide \"Sample Recorder\" window. Press & hold to insert new sample.\n"..
      "Select 2: Clear current pattern-track.\n"..
      "Select 3: n/a.\n"..
      "Select 4: n/a.\n"..
      "Select 5: n/a.\n"..
      "Select 6: n/a.\n"..
      "Select 7: n/a.\n"..
      "Select 1: n/a.",
      
      "u View: Show/hide (& permute) upper panel (Scope/Spectrum views).\nStart: Start/stop recording take.",
      "l View: Show/hide (& permute) lower panel (DSP/Automation Editor views).\nCancel: Cancel recording take.",
      --- ---
      "Save: Show \"Save current Song as\" window.",
      "Undo: Back operation.",
      "Redo: Recover operation.",
      "Metro: Enable/disable Metronome.",
      "Follow: Enable/disable follow the player's position."
    }
    local BTT_DAW=vb:button{
      id=("AKM_BTT_DAW_A_%s"):format(num),
      active=false,
      height=25,
      width=57,
      text=tbl_txt_a[num],
      tooltip=tbl_tlt_a[num]
    }
    self.cnt=BTT_DAW
  end

  class "Akm_Button_B"
  function Akm_Button_B:__init(num)
    local tbl_tlt_b={
    "Previous track.",
    "Next track.",
    "Stop Song.\nPress & hold with \"Restore Song\" to playing song from the current line.",
    "Restore Song.\nAfter, press & hold with \"Stop Song\" to playing song from the current line.",
    "On/off Edit Mode for Pattern Editor.",
    "On/off Loop Mode to repeat the current pattern."
    }
    local BTT_DAW=vb:button{
      id=("AKM_BTT_DAW_B_%s"):format(num),
      active=false,
      height=29,
      width=50,
      bitmap=("ico/transport_%s_ico.png"):format(num),
      tooltip=tbl_tlt_b[num]
    }
    self.cnt=BTT_DAW
  end
  local FILE_2=vb:row{margin=8,spacing=8}
  local FILE_3=vb:row{spacing=6}

  for num=6,10 do
    FILE_2:add_child(
      Akm_Button_A(num).cnt
    )
  end

  for num=1,6 do
    FILE_3:add_child(
      Akm_Button_B(num).cnt
    )
  end
  local daw_panel=vb:column{
    id="AKM_PNL_DAW",
    spacing=5,
    vb:column{
      vb:horizontal_aligner{
        mode="center",
        vb:text{
          height=21,
          font="bold",
          text="GLOBAL CONTROLS"
        }
      },
      FILE_2
    },
    vb:space{height=3},
    vb:column{
      vb:horizontal_aligner{
        mode="center",
        vb:text{
          height=21,
          font="bold",
          text="TRANSPORT"
        }
      },
      FILE_3
    },
    vb:space{height=14}
  }
  return daw_panel
end

local function akm_mp_dial()
  local dial_panel=vb:column{
    style="group",
    id="AKM_PNL_DIAL",
    vb:column{
      spacing=-256,
      vb:bitmap{
        active=false,
        mode="body_color",
        height=256,
        width=256,
        bitmap="ico/arturia_background_ico.png"
      },
      vb:column{
        margin=4,
        vb:horizontal_aligner{
          margin=2,
          mode="center",
          vb:row{
            style="plain",
            margin=2,
            spacing=-3,
            height=48,
            vb:column{
              --style="group",
              width=155,
              vb:text{
                id="AKM_TXT_DIGITAL_1",
                width=209,
                height=41,
                font="big",
                text="Daw\nStandard   MCU"
              }
            },
            vb:space{width=5},
            vb:column{
              --style="group",
              width=153,
              vb:text{
                id="AKM_TXT_DIGITAL_2",
                width=153,
                height=41,
                align="right",
                font="big",
                text="Arturia KeyLab\nmk3"
              }
            },
            vb:space{width=5}
          }
        },
        vb:column{
          spacing=-55,
          width=333,
          vb:horizontal_aligner{
            margin=4,
            mode="center",
            height=55,
            vb:row{
              spacing=9,
              vb:column{
                spacing=0,
                width=53,
                vb:rotary{
                  id="AKM_ROT_DIAL",
                  active=false,
                  min=0,
                  max=8,
                  value=0,
                  height=53,
                  width=53,
                  tooltip="Main tabs navigation.\nSwitch between the different Renoise panels, turning right or left. "..
                          "Press the central button for two shortcuts (Pattern Editor or Plugin panel).\n"..
                          "Press & hold the central button to unttach/tach the Instrument Editor panel."
                },
              },
            }
          },
        },
        akm_mp_daw()
      }
    }
  }
  return dial_panel
end

local AKM_RTY_TOOLTIP={
  "Note value.\nRange=C-0 to B-9, OFF or EMP.",
  "Instrument value.\nRange=00 to FE, or EMP.",
  "Volume value.\nRange=00 to 7F or EMP.",
  "Panning value.\nRange=00 to 80 or EMP.",
  "Delay value.\nRange=01 to FF or EMP",
  "sFX/FX parameter.\n"..
    --sample
    "   A: Set arpeggio, x/y = first/second note offset in semitones, 00 = repeat.\n"..
    "   U: Slide pitch up by xx 1/16ths of a semitone, 00 = repeat.\n"..
    "   D: Slide pitch down by xx 1/16ths of a semitone, 00 = repeat.\n"..
    "   G: Glide towards given note by xx 1/16ths of a semitone, 00 = repeat.\n"..
    "   V: Set vibrato (regular pitch variation), x = speed, y = depth, 00 = repeat.\n"..
    "   I: Fade volume in by xx volume units, 00 = repeat.\n"..
    "   O: Fade volume out by xx volume units, 00 = repeat.\n"..
    "   T: Set tremolo (regular volume variation), x = speed, y = depth, 00 = repeat.\n"..
    "   C: Cut volume to x after y ticks (x = volume factor: 0=0%, F=100%).\n"..
    "   S: Trigger sample slice number xx or offset xx.\n"..
    "   B: Play sample backwards (xx = 00) or forwards (xx = 01).\n"..
    "   E: Set the position of all active Envelope, AHDSR & Fader Modulation devices...\n"..
    "   N: Set auto pan (regular pan variation), x = speed, y = depth, 00 = repeat\n\n"..
    --instrument
    "   M: Set channel volume level, 00 = -60dB, FF = +3dB.\n"..
    "   Z: Trigger phrase number xx (01 - 7E, 00 = no phrase, 7F = keymap mode).\n"..
    "   Q: Delay playback of the line by xx ticks (00 - TPL).\n"..
    "   Y: MaYbe trigger the line with probability xx. 00 = mutually exclusive mode...\n"..
    "   R: Retrigger instruments that are currently playing.\n\n"..
    --device
    "   L: Set track pre-mixer's volume level, 00 = -INF, C0 = 0dB, FF = +3dB.\n"..
    "   P: Set track pre-mixer's panning, 00 = left, 80 = center, FF = right.\n"..
    "   W: Set track pre-mixer's surround width, 00 = off, 01 - FF.\n"..
    "   X: Stop all notes & FX (X00), or a specific effect (Xxx, where xx > 00).\n"..
    "   J: Set track's output routing to channel xx, 00 = Master, 01 = hardware, FF = parent group.\n\n"..
    --global
    "   ZT: BPM, set tempo (20 - FF, 00 = stop song).\n"..
    "   ZL: LPB, set Lines Per Beat (01 - FF, 00 = stop song).\n"..
    "   ZK: TPL, set Ticks Per Line (01 - 10).\n"..
    "   ZG: Toggle song Groove on/off (00 = turn off, 01 or higher = turn on).\n"..
    "   ZB: Break pattern. The pattern finishes & jumps to next pattern at line xx (hex).\n"..
    "   ZD: Delay (pause) pattern playback by xx lines.\n",--..
    --"Empty."
  "sFX/FX amount.\nRange=00 to FF, according to the effect parameter.",
  "Note/effect column.\nRange=N1 to N12 or E1 to E8.",
  "Step length.\nRange=00 to 64 lines.\nChange the value to jump of \"Step length used in the pattern editor\"."
}



local function akm_btt_val_lock(num)
  for i=1,9 do
    if (i==num) then
      if (AKM_VAL_LOCK[num]) then
        vws[("AKM_BTT_VAL_LOCK_%s"):format(num)].bitmap="ico/padlock_close_ico.png"
        vws[("AKM_BTT_VAL_LOCK_%s"):format(num)].color=AKM_CLR.MARKER
        AKM_VAL_LOCK[num]=false
      else
        vws[("AKM_BTT_VAL_LOCK_%s"):format(num)].bitmap="ico/padlock_open_ico.png"
        vws[("AKM_BTT_VAL_LOCK_%s"):format(num)].color=AKM_CLR.DEFAULT
        AKM_VAL_LOCK[num]=true
      end
      return
    end
  end
end

local function akm_btt_val_lock_state()
  local state={1,2,6,7}
  for i=1,#state do
    akm_btt_val_lock(state[i])
  end
end



local function akm_mp_faders()
  local text_val={"Note","Instr.","Volume","Panning","Delay", "sFX-FX","Amo","NC-EC", "Step"}
  local vfd_val_val={
    {121,120,060,048,036}, --note
    {255,255,000,000,000}, --instrument
    {255,127,096,064,032}, --volume
    {255,255,128,064,000}, --panning
    {000,128,096,064,032}, --delay
    
    {002,006,009,013,001}, --sfx/fx
    {004,003,002,001,000}, --amount
    {001,002,003,004,013}, --nc/ec
    
    {000,016,032,048,063}  --step
  }
  local sld_min_val={000,000,000,000,000, 000,000,000, 000 }
  local sld_max_val={121,255,255,255,255, 030,255,127, 127 }
  local sld_val_val={121,255,255,255,255, 000,000,000, 127 }

  class "Akm_Fader"
  function Akm_Fader:__init(num)
    local function fdr_tostring(val,num)
      if (num==1) then
        return akm_note_tostring(val)
      elseif (num==2) then
        return akm_instrument_tostring(val)
      elseif (num==3) then
        return akm_volume_tostring(val)
      elseif (num==4) then
        return akm_panning_tostring(val)
      elseif (num==5) then
        return akm_delay_tostring(val)
      elseif (num==6) then
        return akm_sfx_fx_tostring(val)
      elseif (num==7) then
        return akm_amount_tostring(val)
      elseif (num==8) then
        return akm_nc_ec_tostring(val)
      elseif (num==9) then
        return akm_step_tostring(val)
      end
    end
    local function fdr_tonumber(val,num)
      if (num==1) then
        return akm_note_tonumber(val)
      elseif (num==2) then
        return akm_instrument_tonumber(val)
      elseif (num==3) then
        return akm_volume_tonumber(val)
      elseif (num==4) then
        return akm_panning_tonumber(val)
      elseif (num==5) then
        return akm_delay_tonumber(val)
      elseif (num==6) then
        return akm_sfx_fx_tonumber(val)
      elseif (num==7) then
        return akm_amount_tonumber(val)
      elseif (num==8) then
        return akm_nc_ec_tonumber(val)
      elseif (num==9) then
        return akm_step_tonumber(val)
      end
    end
    local FDR_MAIN=vb:column{margin=4}
    local FDR_VAL=vb:column{spacing=21}
    FDR_MAIN:add_child(FDR_VAL)
    local lvl={5,4,3,2,1}
    for i=1,5 do
      FDR_VAL:add_child(
        vb:valuefield{
          id=("AKM_VFD_VAL_%s_%s"):format(num,i),
          height=21,
          width=37,
          align="right",
          min=sld_min_val[num],
          max=sld_max_val[num],
          value=vfd_val_val[num][i],
          tostring=function(val) return fdr_tostring(val,num) end,
          tonumber=function(val) return fdr_tonumber(val,num) end,
          notifier=function(val) end,
          tooltip=("Level %s to \"%s\" panel"):format(lvl[i],text_val[num])
        }
      )
    end
    FDR_MAIN:add_child(
      vb:button{
        id=("AKM_BTT_VAL_LOCK_%s"):format(num),
        height=20,
        width=28,
        bitmap="ico/padlock_open_ico.png",
        notifier=function() akm_btt_val_lock(num) end,
        tooltip=("Lock/unlock the rotary & slider controls of panel %s."):format(num)
      }
    )

    local MAIN_FDR=vb:column{
      width=55,
      style="group",
      margin=4,
      vb:column{
        width=55,
        vb:text{
          height=21,
          width=55,
          align="center",
          font="bold",
          text=text_val[num]
        }
      },
      vb:horizontal_aligner{
        mode="center",
        vb:rotary{
          id=("AKM_ROT_%s"):format(num),
          active=false,
          height=41,
          width=41, 
          min=sld_min_val[num],
          max=sld_max_val[num],
          value=sld_val_val[num],
          tooltip=AKM_RTY_TOOLTIP[num]
        }
      },
      vb:row{
        spacing=-4,

        FDR_MAIN,
        vb:slider{
          id=("AKM_SLD_%s"):format(num),
          active=false,
          height=209,
          width=21,
          min=sld_min_val[num],
          max=sld_max_val[num],
          value=sld_val_val[num],
          tooltip=("Fader %s"):format(num)
        }
      },
    }
    self.cnt=MAIN_FDR
  end
  local FADERS=vb:row{
    spacing=4
  }
  for num=1,#sld_min_val do
    FADERS:add_child(
      Akm_Fader(num).cnt
    )
  end

  local faders_panel=vb:column{
    id="AKM_PNL_FADERS",
    spacing=9,
    FADERS
  }
  akm_btt_val_lock_state()
  return faders_panel
end

local function akm_middle_panel()
  local middle_panel=vb:row{
    id="AKM_PNL_MIDDLE",
    spacing=9,
    --akm_mp_pads(),
    akm_mp_dial(),
    akm_mp_faders()
  }
  return middle_panel
end


local function akm_lower_panel()
  local lower_panel=vb:column{
    id="AKM_PNL_LOWER",
    width="100%",
    margin=5,
    style="group",
    visible=false,
    vb:row{
      vb:text{
        text=AKM_ABOUT_TTP
      },
      vb:bitmap{
        height=175,
        width=569,
        bitmap="ico/keylab_essential_ico.png"
      }
    }
  }
  return lower_panel
end

local function akm_main_content()
  AKM_MAIN_CONTENT=vb:column{
    style="panel",
    margin=5,
    spacing=5,
    akm_upper_panel(),
    vb:column{
      id="AKM_MAIN_PANELS",
      spacing=5,
      akm_middle_panel(),
      akm_lower_panel()
    }
  }
  return AKM_MAIN_CONTENT
end

---------------- Pads MIDI Mapping Injection -----------------

local INJECTED_MAPPINGS = [[
    <ActionMappings>
      <ActionMapping>
        <Action>GUI:Middle Frame:Show Pattern Matrix [Toggle]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>44</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>GUI:Upper Frame:Show Upper Frame [Toggle]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>45</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>GUI:Lower Frame:Show Lower Frame [Toggle]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>46</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>GUI:Middle Frame:Show Pattern Advanced Edit [Toggle]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>47</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Sequencer:Select Previous Sequence Pos [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>40</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Tracks:Select Previous Track [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>41</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Tracks:Select Next Track [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>42</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Instruments:Decrease Current Instrument [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>43</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Sequencer:Select Next Sequence Pos [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>36</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Columns:Select Previous Column [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>37</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Columns:Select Next Column [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>38</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
      <ActionMapping>
        <Action>Navigation:Instruments:Increase Current Instrument [Trigger]</Action>
        <MidiMappings><MidiMapping><MappingMode>Notes</MappingMode><ControllerMode>Absolute 7 bit</ControllerMode><NoteMode>Trigger</NoteMode><Channel>9</Channel><CCNumberOrNote>39</CCNumberOrNote><Min>0.0</Min><Max>1.0</Max></MidiMapping></MidiMappings>
      </ActionMapping>
    </ActionMappings>]]

local TMP_SAVE    = "/tmp/akm_save.xrns"
local TMP_UNZIP   = "/tmp/akm_unzip"
local TMP_PATCHED = "/tmp/akm_patched.xrns"
local INJECTED_MARKER = "AKM_INJECTED"

local _app_ready = false
local _injecting = false
local _original_path = nil
local _save_as_copy = false

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*all")
  f:close()
  return s
end

local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

local function midi_mapper_has_content(xml)
  local block = xml:match("<MidiMapper>([%s%S]-)</MidiMapper>")
  if not block then return false end
  return block:find("<ActionMapping>") ~= nil
end

-- Patch the song with midi mappings for pads.
-- Either overwrite the current song or save a copy.
-- Does nothing if any midi mappings are already present.
function patch_and_reload(as_copy)
  local song_path = renoise.song().file_name
  print("[AKM] Song: '" .. song_path .. "'")

  -- check for existing mappings by reading directly from disk
  -- to avoid clobbering the tracked filepath with save_song_as
  local read_source
  if song_path ~= "" then
    read_source = song_path
  else
    renoise.app():save_song_as(TMP_SAVE)
    read_source = TMP_SAVE
  end

  os.execute(string.format('rm -rf "%s" && mkdir -p "%s"', TMP_UNZIP, TMP_UNZIP))
  os.execute(string.format('unzip -o "%s" -d "%s"', read_source, TMP_UNZIP))

  local xml = read_file(TMP_UNZIP .. "/Song.xml")
  if not xml then print("[AKM] ERROR: Could not read Song.xml") return end

  if midi_mapper_has_content(xml) then
    print("[AKM] Song already has MIDI mappings, skipping")
    return  -- nothing clobbered, filepath untouched
  end

  -- now safe to save_song_as since we're committed to patching
  _original_path = song_path
  _save_as_copy = as_copy
  renoise.app():save_song_as(TMP_SAVE)

  -- re-unzip from fresh save to capture any unsaved changes
  os.execute(string.format('rm -rf "%s" && mkdir -p "%s"', TMP_UNZIP, TMP_UNZIP))
  os.execute(string.format('unzip -o "%s" -d "%s"', TMP_SAVE, TMP_UNZIP))
  xml = read_file(TMP_UNZIP .. "/Song.xml")
  if not xml then print("[AKM] ERROR: Could not re-read Song.xml") return end

  local new_mapper = "<MidiMapper>\n  <!-- " .. INJECTED_MARKER .. " -->\n"
    .. INJECTED_MAPPINGS .. "\n  </MidiMapper>"

  local patched, n
  patched, n = xml:gsub("<MidiMapper%s*/>", new_mapper)
  if n == 0 then
    patched, n = xml:gsub("<MidiMapper>[%s%S]-</MidiMapper>", new_mapper)
  end
  if n == 0 then
    patched, n = xml:gsub("</RecordManager>", "</RecordManager>\n" .. new_mapper)
  end
  if n == 0 then
    print("[AKM] ERROR: Could not find insertion point in Song.xml")
    _original_path = nil
    _save_as_copy = false
    return
  end

  write_file(TMP_UNZIP .. "/Song.xml", patched)

  os.execute(string.format('rm -f "%s"', TMP_PATCHED))
  os.execute(string.format('cd "%s" && zip -r "%s" .', TMP_UNZIP, TMP_PATCHED))

  local check = io.open(TMP_PATCHED, "r")
  if not check then
    print("[AKM] ERROR: TMP_PATCHED not created")
    _original_path = nil
    _save_as_copy = false
    return
  end
  check:close()
  print("[AKM] Patched xrns ready, loading...")

  _injecting = true
  renoise.app():load_song(TMP_PATCHED)
end

-- dedicated always-on completion notifier, separate from the auto-inject one
rnt.app_new_document_observable:add_notifier(function()
  if not _injecting then return end
  _injecting = false
  if _original_path and _original_path ~= "" then
    local save_path = _save_as_copy
      and _original_path:gsub("%.xrns$", "_keylab.xrns")
      or _original_path
    print("[AKM] Saving to: " .. save_path)
    renoise.app():save_song_as(save_path)
  end
  _original_path = nil
  _save_as_copy = false
end)

-- defer notifier registration until app is ready
rnt.app_idle_observable:add_notifier(function()
  _app_ready = true
end)

rnt.app_new_document_observable:add_notifier(function()
  if not _app_ready then
    print("Skipping, app not ready yet")
    return
  end
  if AKM_AUTO_INJECT_MAPPINGS then --it's off by default
    patch_and_reload(true)
  end
end)


---------- End Midi Mapping Injection ----------------


--auto-enable/disable for new song
local function akm_on_off_standby()
  if (AKM_AUTOSTART) then --turn on
    if not (AKM_ON_OFF) then
      akm_on_off()
    end
  else
    if (AKM_ON_OFF) then --turn off
      akm_on_off()
    end
  end
end

-------------------------------------------------------------------------------------------------
--one-time setup reminder for KeyLab Essential mk3 (Renoise can't be configured from a script)
-------------------------------------------------------------------------------------------------
-- Shown once ever (tracked in renoise.tool().preferences, see top of file).
-- Exists because two things this hardware needs are genuinely NOT settable via
-- the Lua API - Preferences > MIDI > "Ignore specific controllers" (global app
-- setting) and an instrument's MIDI Input > Channel (per-instrument setting).
-- Without the first, Renoise records every unmapped button/knob CC straight
-- into the pattern as a raw effect command while Edit Mode is on. Without the
-- second, pads (which are on MIDI channel 10) get recorded as real notes on
-- whatever instrument you're playing.
local function akm_essential_first_run_setup()
  if (renoise.tool().preferences.essential_setup_shown.value) then return end

  local cc_list="20,21,22,24,25,26,27,40,42,43,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,116,117,118"

  local vb2=renoise.ViewBuilder()
  local content=vb2:column{
    margin=10,
    spacing=8,
    vb2:text{
      text="One-time setup for KeyLab Essential mk3\n\nRenoise sometimes records this controller's buttons/knobs into the pattern as raw MIDI commands. Two quick settings fix this for good:",
      width=420
    },
    vb2:text{text="1) Edit > Preferences > MIDI > \"Ignore specific controllers\" - paste this list:"},
    vb2:multiline_textfield{
      text=cc_list,
      width=420,
      height=40
    },
    vb2:text{text="2) On the instrument(s) you play, set MIDI Input > Channel to 1 (instead of Any) so pads on channel 10 aren't recorded as notes."},
  }

  renoise.app():show_custom_prompt("Arturia KeyLab Essential mk3 setup",content,{"Got it"})
  renoise.tool().preferences.essential_setup_shown.value=true
end

-------------------------------------------------------------------------------------------------
--show main_dialog
-------------------------------------------------------------------------------------------------
local function akm_main_dialog()
  akm_essential_first_run_setup()
  --main content gui
  if (AKM_MAIN_CONTENT==nil) then
    akm_capture_clr_mrk()
    akm_main_content()
    require("lua/keyhandler")
  end
  --avoid showing the same window several times!
  if (AKM_MAIN_DIALOG) and (AKM_MAIN_DIALOG.visible) then AKM_MAIN_DIALOG:show() return end
  --custom dialog
  AKM_MAIN_DIALOG=rna:show_custom_dialog(("%s"):format(akm_main_title),AKM_MAIN_CONTENT,akm_keyhandler)
  --reload show_tool_dialog() in new song
  if not rnt.app_new_document_observable:has_notifier(akm_on_off_standby) then
    rnt.app_new_document_observable:add_notifier(akm_on_off_standby)
  end
end
_AUTO_RELOAD_DEBUG=function() akm_main_dialog() end

-------------------------------------------------------------------------------------------------
--register menu entry
-------------------------------------------------------------------------------------------------
rnt:add_menu_entry{
  name=("Main Menu:Tools:%s..."):format(akm_main_title),
  invoke=function() akm_main_dialog() end
}
rnt:add_menu_entry{
  name=("Main Menu:Song:Save with KeyLab Mappings"):format(akm_main_title),
  invoke=function() patch_and_reload(false) end
}
rnt:add_menu_entry{
  name=("Main Menu:Song:Save Copy with KeyLab Mappings"):format(akm_main_title),
  invoke=function() patch_and_reload(true) end
}

-------------------------------------------------------------------------------------------------
--register keybinding
-------------------------------------------------------------------------------------------------
rnt:add_keybinding{
  name=("Global:Tools:%s"):format(akm_main_title),
  invoke=function() akm_main_dialog() end
}
rnt:add_keybinding{
  name=("Global:Tools:%s - Save with Mappings"):format(akm_main_title),
  invoke=function() patch_and_reload(false) end
}
rnt:add_keybinding{
  name=("Global:Tools:%s - Save Copy with Mappings"):format(akm_main_title),
  invoke=function() patch_and_reload(true) end
}

local function akm_main_autostart()
  if (AKM_MAIN_CONTENT==nil) then
    akm_main_dialog()

    if (AKM_HIDE_ON_START) then
      AKM_MAIN_DIALOG:close()
    end
  end
end

--Turn on the tool on app start
if (AKM_AUTOSTART) then
  if not rnt.app_new_document_observable:has_notifier(akm_main_autostart) then
    rnt.app_new_document_observable:add_notifier(akm_main_autostart)
  end
end


----------------------------------------
--collectgarbage<bottom>
 --print("collectgarbage:",collectgarbage("count"),("KBytes(%s)"):format(akm_main_title))
 --collectgarbage("restart")
----------------------------------------
--rprint(_G)

-----------------------------------------------------------------------------------------------
-- ACTION FUNCTIONS
-- Everything from here on is "what happens when a pad/knob/fader/transport
-- button is pressed or turned" - the functions midi_callback (up near the top
-- of this file, search "local function midi_callback") actually calls.
-- All plain globals rather than "local function" - see point 5 in the file
-- header for why (Lua's 200-local-per-chunk limit).
-----------------------------------------------------------------------------------------------

function akm_tap_led_dim_callback()
  akm_essential_set_led(0x17,0x18,0x18,0x18)
  if (renoise.tool():has_timer(akm_tap_led_dim_callback)) then
    renoise.tool():remove_timer(akm_tap_led_dim_callback)
  end
end

-- Real hardware LED flash for the four one-shot action buttons, same
-- self-removing-timer pattern as Tap. Button ids per the programming guide's
-- table: Save=0x0C, Undo=0x0E, Redo=0x0F, Stop=0x14.
function akm_led_flash_save_dim()
  akm_essential_set_led(0x0C,0x18,0x18,0x18)
  if (renoise.tool():has_timer(akm_led_flash_save_dim)) then
    renoise.tool():remove_timer(akm_led_flash_save_dim)
  end
end

function akm_led_flash_undo_dim()
  akm_essential_set_led(0x0E,0x18,0x18,0x18)
  if (renoise.tool():has_timer(akm_led_flash_undo_dim)) then
    renoise.tool():remove_timer(akm_led_flash_undo_dim)
  end
end

function akm_led_flash_redo_dim()
  akm_essential_set_led(0x0F,0x18,0x18,0x18)
  if (renoise.tool():has_timer(akm_led_flash_redo_dim)) then
    renoise.tool():remove_timer(akm_led_flash_redo_dim)
  end
end

function akm_led_flash_stop_dim()
  akm_essential_set_led(0x14,0x18,0x18,0x18)
  if (renoise.tool():has_timer(akm_led_flash_stop_dim)) then
    renoise.tool():remove_timer(akm_led_flash_stop_dim)
  end
end


-- Tap the button in rhythm to set song.transport.bpm. Averages the last 4
-- gaps between taps (steadier than using only the single most recent gap),
-- and resets if you pause more than 2 seconds so an accidental long gap isn't
-- read as one very slow beat. Needs at least 2 taps before any BPM is set -
-- the first tap only marks a starting point.
function akm_tap_tempo()
  akm_essential_set_led(0x17,0x7F,0x7F,0x7F)
  if (renoise.tool():has_timer(akm_tap_led_dim_callback)) then
    renoise.tool():remove_timer(akm_tap_led_dim_callback)
  end
  renoise.tool():add_timer(akm_tap_led_dim_callback,2000)

  local now=os.clock()
  if (AKM_TAP_LAST_TIME~=nil) then
    local interval=now-AKM_TAP_LAST_TIME
    if (interval<2.0) then
      table.insert(AKM_TAP_INTERVALS,interval)
      if (#AKM_TAP_INTERVALS>4) then
        table.remove(AKM_TAP_INTERVALS,1)
      end
      local sum=0
      for _,v in ipairs(AKM_TAP_INTERVALS) do sum=sum+v end
      local avg=sum/#AKM_TAP_INTERVALS
      local bpm=60/avg
      if (bpm<32) then bpm=32 elseif (bpm>999) then bpm=999 end
      song.transport.bpm=math.floor(bpm+0.5)
      vws.AKM_TXT_DIGITAL_1.text=("BPM: %d"):format(song.transport.bpm)
    else
      AKM_TAP_INTERVALS={}
    end
  end
  AKM_TAP_LAST_TIME=now
end


function akm_note_tostring(val) --number return a string, range val: 0 to 119 & 120,121
  local note_name={"C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-"}
  if (val<120) then
    return ("%s%s"):format(note_name[math.floor(val) %12+1],math.floor(val/12))
  elseif (val==120) then
    return "OFF"
  elseif (val==121) then
    return "EMP"
  end
end


function akm_note_tonumber(val) --string return a number
  local nte_name_1={"C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-"}
  local nte_name_2={"c-","c#","d-","d#","e-","f-","f#","g-","g#","a-","a#","b-"}
  local nte_name_3={"C", "C#","D", "D#","E", "F" ,"F#","G", "G#","A", "A#","B" }
  local nte_name_4={"c", "c#","d", "d#","e", "f", "f#","g", "g#","a", "a#","b" }
  local nte_off   ={"o","O","of","oF","Of","OF","off","oFf","ofF","oFF","Off","OFf","OFF"}
  local nte_empty ={"em","Em","eM","emp","eMp","emP","eMP","Emp","EMp","EMP","empty","Empty","EMPTY"}
  for i=1,#nte_name_1 do
    for octave = 0,9 do
      if (val==("%s%s"):format(nte_name_1[i],octave)) or
         (val==("%s%s"):format(nte_name_2[i],octave)) or
         (val==("%s%s"):format(nte_name_3[i],octave)) or
         (val==("%s%s"):format(nte_name_4[i],octave)) then
        return i+(octave*12)-1
      end
    end
  end
  for i=1,#nte_off do
    if (val==("%s"):format(nte_off[i])) then
      return 120
    end
  end
  for i=1,#nte_empty do
    if (val==("%s"):format(nte_empty[i])) then
      return 121
    end
  end
end


function akm_instrument_tostring(val) --number return a string, range val: 0 to 254 & 255
  if (val<255) then
    return ("%.2X"):format(val)
  elseif (val==255) then
    return "EMP"
  end
end


function akm_instrument_tonumber(val) --string return a number
  local ins_empty ={"em","Em","eM","emp","eMp","emP","eMP","Emp","EMp","EMP","empty","Empty","EMPTY"}
  for i=1,#ins_empty do
    if (val==("%s"):format(ins_empty[i])) then
      return 255
    else
      return tonumber(val,16)
    end
  end
end


function akm_volume_tostring(val) --number return a string, range val: 0 to 127 & 255
  if (val<=127) then
    return ("%.2X"):format(val)
  elseif (val>127) then
    return "EMP"    
  end
end


function akm_volume_tonumber(val) --string return a number
  local vol_empty ={"em","Em","eM","emp","eMp","emP","eMP","Emp","EMp","EMP","empty","Empty","EMPTY"}
  for i=1,#vol_empty do
    if (val==("%s"):format(vol_empty[i])) then
      return 255
    else
      return tonumber(val,16)
    end
  end
end


function akm_panning_tostring(val) --number return a string, range val: 0 to 127 & 255
  if (val==128) then
    return ("%.2X R"):format(val) --right
  elseif (val<128 and val>64) then
    return ("%.2X ▶"):format(val)
  elseif (val==64) then
    return ("%.2X C"):format(val) --center
  elseif (val<64 and val>0) then
    return ("%.2X ◀"):format(val)
  elseif (val==0) then
    return ("%.2X L"):format(val) --left
  elseif (val>128) then
    return "EMP"
  end
end


function akm_panning_tonumber(val) --string return a number
  local pan_empty ={"em","Em","eM","emp","eMp","emP","eMP","Emp","EMp","EMP","empty","Empty","EMPTY"}
  local pan_left  ={"l","L","le","Le","LE","left","Left","LEFT"}
  local pan_center={"ce","Ce","CE","center","Center","CENTER"}
  local pan_right ={"r","R","ri","Ri","RI","right","Right","RIGHT"}
  for i=1,#pan_empty do
    if (val==("%s"):format(pan_empty[i])) then
      return 255
    end
  end
  for i=1,#pan_left do
    if (val==("%s"):format(pan_left[i])) then
      return 0
    end
  end
  for i=1,#pan_center do
    if (val==("%s"):format(pan_center[i])) then
      return 64
    end
  end
  for i=1,#pan_right do
    if (val==("%s"):format(pan_right[i])) then
      return 128
    end
  end
  return tonumber(val,16)
end


function akm_delay_tostring(val) --number return a string, range val: 1 to 255 & 0
  if (val<=255 and val>0) then
    return ("%.2X"):format(val)
  elseif (val==0) then
    return "EMP"
  end
end


function akm_delay_tonumber(val) --string return a number
  local vol_empty={"em","Em","eM","emp","eMp","emP","eMP","Emp","EMp","EMP","empty","Empty","EMPTY"}
  for i=1,#vol_empty do
    if (val==("%s"):format(vol_empty[i])) then
      return 0
    else
      return tonumber(val,16)
    end
  end
end


function akm_sfx_fx_tostring(val) --number return a string
  local AKM_SFX_0={"EMP","A","U","D","G","V","I","O","T","C","S","B","E","N"}
  local AKM_EFF_0={"EMP","A","U","D","G","V","I","O","T","C","S","B","E","N", "M","Z","Q","Y","R", "L","P","W","X","0J", "ZT","ZL","ZK","ZG","ZB","ZD"}
  local snc,sec=song.selected_note_column,song.selected_effect_column
  if (song.selected_track.type~=renoise.Track.TRACK_TYPE_MASTER) then
    if (snc) then
      return AKM_SFX_0[val]
    else
      return AKM_EFF_0[val]
    end
  else
    return AKM_EFF_0[val]
  end
end


function akm_sfx_fx_tonumber(val) --string return a number
  local snc,sec=song.selected_note_column,song.selected_effect_column
  local sfx_empty={"em","Em","eM","emp","eMp","emP","eMP","Emp","EMp","EMP","empty","Empty","EMPTY"}
  local akm_sfx_0={"0","a","u","d","g","v","i","o","t","c","s","b","e","n"}
  local AKM_SFX_0={"0","A","U","D","G","V","I","O","T","C","S","B","E","N"}
  local akm_eff_0={"0","a","u","d","g","v","i","o","t","c","s","b","e","n", "m","z","q","y","r", "l","p","w","x","j", "zt","zl","zk","zg","zb","zd"}
  local AKM_EFF_0={"0","A","U","D","G","V","I","O","T","C","S","B","E","N", "M","Z","Q","Y","R", "L","P","W","X","J", "ZT","ZL","ZK","ZG","ZB","ZD"}
  if (song.selected_track.type~=renoise.Track.TRACK_TYPE_MASTER) then
    if (snc) then
      for i=1,#akm_sfx_0 do
        if (val==("%s"):format(akm_sfx_0[i])) then
          return i
        end
      end
      for i=1,#AKM_SFX_0 do
        if (val==("%s"):format(AKM_SFX_0[i])) then
          return i
        end
      end
    else
      for i=1,#akm_eff_0 do
        if (val==("%s"):format(akm_eff_0[i])) then
          return i
        end
      end
      for i=1,#AKM_EFF_0 do
        if (val==("%s"):format(AKM_EFF_0[i])) then
          return i
        end
      end
    end
  else
    for i=1,#akm_eff_0 do
      if (val==("%s"):format(akm_eff_0[i])) then
        return i
      end
    end
    for i=1,#AKM_EFF_0 do
      if (val==("%s"):format(AKM_EFF_0[i])) then
        return i
      end
    end
  end
  for i=1,#sfx_empty do
    if (val==("%s"):format(sfx_empty[i])) then
      return 1
    end
  end
  return val
end


function akm_amount_tostring(val) --number return a string, range val: 0 to 255
  if (val<=255 and val>=0) then
    return ("%.2X"):format(val)
  end
end


function akm_amount_tonumber(val) --string return a number
  return tonumber(val,16)
end


function akm_nc_ec_tostring(val) --number return a string
  local NC_EC={"NC1","NC2","NC3","NC4","NC5","NC6","NC7","NC8","NC9","NC10","NC11","NC12","EC1","EC2","EC3","EC4","EC5","EC6","EC7","EC8"}
  return NC_EC[val]
end


function akm_nc_ec_tonumber(val) --string return a number
  local n_e=  {"n1","n2","n3","n4","n5","n6","n7","n8","n9","n10","n11","n12","e1","e2","e3","e4","e5","e6","e7","e8"}
  local nc_ec={"nc1","nc2","nc3","nc4","nc5","nc6","nc7","nc8","nc9","nc10","nc11","nc12","ec1","ec2","ec3","ec4","ec5","ec6","ec7","ec8"}
  local N_E=  {"N1","N2","N3","N4","N5","N6","N7","N8","N9","N10","N11","N12","E1","E2","E3","E4","E5","E6","E7","E8"}
  local NC_EC={"NC1","NC2","NC3","NC4","NC5","NC6","NC7","NC8","NC9","NC10","NC11","NC12","EC1","EC2","EC3","EC4","EC5","EC6","EC7","EC8"}
  for i=1,#n_e do
    if (val==("%s"):format(n_e[i])) then
      return i
    end
  end
  for i=1,#nc_ec do
    if (val==("%s"):format(nc_ec[i])) then
      return i
    end
  end
  for i=1,#N_E do
    if (val==("%s"):format(N_E[i])) then
      return i
    end
  end
  for i=1,#NC_EC do
    if (val==("%s"):format(NC_EC[i])) then
      return i
    end
  end
  return val
end


function akm_step_tostring(val) --number return a string, range val: 0 to 64
  if (val<=255 and val>64) then
    return ("%.2d"):format(64)
  elseif (val<64) then
    return ("%.2d"):format(val)
  end
end


function akm_step_tonumber(val) --string return a number
  return tonumber(val)
end


function akm_pad1() -- Toggle Pattern Matrix
  local mfp=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_MATRIX
  local mfe=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  if (rna.window.active_middle_frame==mfp) then
    rna.window.active_middle_frame=mfe
  else
    rna.window.active_middle_frame=mfp
  end
end


function akm_pad2() -- Toggle Upper Frame
  rna.window.upper_frame_is_visible=not rna.window.upper_frame_is_visible
end


function akm_pad3() -- Toggle Lower Frame
  rna.window.lower_frame_is_visible=not rna.window.lower_frame_is_visible
end


function akm_pad4() -- Toggle Pattern Advanced Edit
  local mfa=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_ADVANCED_EDIT
  local mfe=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  if (rna.window.active_middle_frame==mfa) then
    rna.window.active_middle_frame=mfe
  else
    rna.window.active_middle_frame=mfa
  end
end


function akm_toggle_mixer()
  local mfm=renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
  local mfe=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  if (rna.window.active_middle_frame==mfm) then
    rna.window.active_middle_frame=mfe
  else
    rna.window.active_middle_frame=mfm
  end
end


function akm_pad5() -- Select Previous Sequence Pos
  local t=song.transport
  t.playback_pos=renoise.SongPos(math.max(1,t.playback_pos.sequence-1),1)
end


function akm_pad6() -- Select Previous Track
  song.selected_track_index=math.max(1,song.selected_track_index-1)
end


function akm_pad7() -- Select Next Track
  song.selected_track_index=math.min(#song.tracks,song.selected_track_index+1)
end


function akm_pad8() -- Decrease Current Instrument
  song.selected_instrument_index=math.max(1,song.selected_instrument_index-1)
end


function akm_pad9() -- Select Next Sequence Pos
  local t=song.transport
  t.playback_pos=renoise.SongPos(math.min(#song.sequencer.pattern_sequence,t.playback_pos.sequence+1),1)
end


function akm_pad10() -- Select Previous Column
  song.selected_note_column_index=math.max(1,song.selected_note_column_index-1)
end


function akm_pad11() -- Select Next Column
  song.selected_note_column_index=math.min(12,song.selected_note_column_index+1)
end


function akm_pad12() -- Increase Current Instrument
  song.selected_instrument_index=math.min(#song.instruments,song.selected_instrument_index+1)
end


function akm_save_on()
  vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[14]
end


function akm_save_off()
  local filename=rna:prompt_for_filename_to_write("xrnx", "Save current Song as")
  if (filename=="") then
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[15]
  else
    rna:save_song_as(filename)
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[16]
  end
  vws.AKM_BTT_DAW_A_6.color=AKM_CLR.MARKER
  if (renoise.tool():has_timer(akm_gui_flash_save_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_save_dim)
  end
  renoise.tool():add_timer(akm_gui_flash_save_dim,300)
  akm_essential_set_led(0x0C,0x7F,0x7F,0x7F)
  if (renoise.tool():has_timer(akm_led_flash_save_dim)) then
    renoise.tool():remove_timer(akm_led_flash_save_dim)
  end
  renoise.tool():add_timer(akm_led_flash_save_dim,300)
end


function akm_metro()
  if (song.transport.metronome_enabled) then
    song.transport.metronome_enabled=false
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[21]
  else
    song.transport.metronome_enabled=true
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[22]
  end
end


function akm_undo()
  if (song.transport.follow_player) then
    song.transport.follow_player=false
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[23]
  else
    song.transport.follow_player=true
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[24]
  end
end


-- Momentary "this fired" flash for one-shot GUI buttons (Save/Undo/Redo/Stop)
-- that don't have an ongoing on/off state the way Play/Loop/Edit Mode do.
-- Same self-removing-timer pattern as the TAP button's LED dim, just one
-- callback per button since Renoise's timer API needs a stable function
-- reference per timer.
function akm_gui_flash_save_dim()
  vws.AKM_BTT_DAW_A_6.color=AKM_CLR.DEFAULT
  if (renoise.tool():has_timer(akm_gui_flash_save_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_save_dim)
  end
end

function akm_gui_flash_undo_dim()
  vws.AKM_BTT_DAW_A_7.color=AKM_CLR.DEFAULT
  if (renoise.tool():has_timer(akm_gui_flash_undo_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_undo_dim)
  end
end

function akm_gui_flash_redo_dim()
  vws.AKM_BTT_DAW_A_8.color=AKM_CLR.DEFAULT
  if (renoise.tool():has_timer(akm_gui_flash_redo_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_redo_dim)
  end
end

function akm_gui_flash_stop_dim()
  vws.AKM_BTT_DAW_B_3.color=AKM_CLR.DEFAULT
  if (renoise.tool():has_timer(akm_gui_flash_stop_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_stop_dim)
  end
end

function akm_song_undo()
  if (song.can_undo) then song:undo() end
  vws.AKM_BTT_DAW_A_7.color=AKM_CLR.MARKER
  if (renoise.tool():has_timer(akm_gui_flash_undo_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_undo_dim)
  end
  renoise.tool():add_timer(akm_gui_flash_undo_dim,300)
  akm_essential_set_led(0x0E,0x7F,0x7F,0x7F)
  if (renoise.tool():has_timer(akm_led_flash_undo_dim)) then
    renoise.tool():remove_timer(akm_led_flash_undo_dim)
  end
  renoise.tool():add_timer(akm_led_flash_undo_dim,300)
end


function akm_song_redo()
  if (song.can_redo) then song:redo() end
  vws.AKM_BTT_DAW_A_8.color=AKM_CLR.MARKER
  if (renoise.tool():has_timer(akm_gui_flash_redo_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_redo_dim)
  end
  renoise.tool():add_timer(akm_gui_flash_redo_dim,300)
  akm_essential_set_led(0x0F,0x7F,0x7F,0x7F)
  if (renoise.tool():has_timer(akm_led_flash_redo_dim)) then
    renoise.tool():remove_timer(akm_led_flash_redo_dim)
  end
  renoise.tool():add_timer(akm_led_flash_redo_dim,300)
end


function akm_stop()
  song.transport:stop()
  vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[27]
  if not (song.transport.playing) then
    song.transport:panic()
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[28]
    --print("panic")
  end
  vws.AKM_BTT_DAW_B_3.color=AKM_CLR.MARKER
  if (renoise.tool():has_timer(akm_gui_flash_stop_dim)) then
    renoise.tool():remove_timer(akm_gui_flash_stop_dim)
  end
  renoise.tool():add_timer(akm_gui_flash_stop_dim,300)
  akm_essential_set_led(0x14,0x7F,0x7F,0x7F)
  if (renoise.tool():has_timer(akm_led_flash_stop_dim)) then
    renoise.tool():remove_timer(akm_led_flash_stop_dim)
  end
  renoise.tool():add_timer(akm_led_flash_stop_dim,300)
end


function akm_essential_quant_led_sync()
  if (song.transport.record_quantize_enabled) then
    akm_essential_set_led(0x0D,0x7F,0x7F,0x7F)
  else
    akm_essential_set_led(0x0D,0x10,0x10,0x10)
  end
end

function akm_quantize()
  song.transport.record_quantize_enabled=not song.transport.record_quantize_enabled
  if (song.transport.record_quantize_enabled) then
    vws.AKM_TXT_DIGITAL_1.text=("Quantize: ON (%d lines)"):format(song.transport.record_quantize_lines)
  else
    vws.AKM_TXT_DIGITAL_1.text="Quantize: OFF"
  end
  akm_essential_quant_led_sync()
end


function akm_play()
  local prp=renoise.Transport.PLAYMODE_RESTART_PATTERN
  if (song.transport.playing) then
    song.transport:stop()
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[29]
  else
    song.transport:start(prp)
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[30]
  end
end


function akm_edit_mode()
  if (song.transport.edit_mode) then
    song.transport.edit_mode=false
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[31]
  else
    song.transport.edit_mode=true
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[32]
    local fpe=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
    if (rna.window.active_middle_frame~=fpe) then
      rna.window.active_middle_frame=fpe
    end
  end
end


function akm_loop()
  if (song.transport.loop_pattern) then
    song.transport.loop_pattern=false
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[33]
  else
    song.transport.loop_pattern=true
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[34]
  end
end


function akm_button_dial_add_timer()
  if not rnt:has_timer(akm_button_dial_add_timer) then
    rnt:add_timer(akm_button_dial_add_timer,700)
  else
    if (rna.window.instrument_editor_is_detached) then
      rna.window.instrument_editor_is_detached=false
      vws.AKM_TXT_DIGITAL_1.text="Instrument editor\nwindow tached"
    else
      rna.window.instrument_editor_is_detached=true
      vws.AKM_TXT_DIGITAL_1.text="Instrument editor\nwindow unttached"
    end
    if rnt:has_timer(akm_button_dial_add_timer) then
      rnt:remove_timer(akm_button_dial_add_timer)
    end
  end
end


function akm_button_dial_remove_timer()
  if rnt:has_timer(akm_button_dial_add_timer) then
    akm_button_dial()
    rnt:remove_timer(akm_button_dial_add_timer)
  end
end


function akm_left_dial()
  local mfp=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  local mfm=renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
  local mfi1=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PHRASE_EDITOR
  local mfi2=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_KEYZONES
  local mfi3=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
  local mfi4=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_MODULATION
  local mfi5=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EFFECTS
  local mfi6=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR
  local mfi7=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_MIDI_EDITOR
  if not (rna.window.instrument_editor_is_detached) then
    if (rna.window.active_middle_frame==mfi7) then
      rna.window.active_middle_frame=mfi6
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[44]
    elseif (rna.window.active_middle_frame==mfi6) then
      rna.window.active_middle_frame=mfi5
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[43]
    elseif (rna.window.active_middle_frame==mfi5) then
      rna.window.active_middle_frame=mfi4
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[42]
    elseif (rna.window.active_middle_frame==mfi4) then
      rna.window.active_middle_frame=mfi3
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[41]
    elseif (rna.window.active_middle_frame==mfi3) then
      rna.window.active_middle_frame=mfi2 
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[40]
    elseif (rna.window.active_middle_frame==mfi2) then
      rna.window.active_middle_frame=mfi1
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[39]
    elseif (rna.window.active_middle_frame==mfi1) then
      rna.window.active_middle_frame=mfm
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[38]
    elseif (rna.window.active_middle_frame==mfm) then
      rna.window.active_middle_frame=mfp
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[37]
    elseif (rna.window.active_middle_frame==mfp) then
      rna.window.active_middle_frame=mfi7
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[45]
    end
  else
    if (AKM_WINDOW_FRAME==mfi7) then
      AKM_WINDOW_FRAME=mfi6
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[44]
    elseif (AKM_WINDOW_FRAME==mfi6) then
      AKM_WINDOW_FRAME=mfi5
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[43]
    elseif (AKM_WINDOW_FRAME==mfi5) then
      AKM_WINDOW_FRAME=mfi4
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[42]
    elseif (AKM_WINDOW_FRAME==mfi4) then
      AKM_WINDOW_FRAME=mfi3
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[41]
    elseif (AKM_WINDOW_FRAME==mfi3) then
      AKM_WINDOW_FRAME=mfi2 
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[40]
    elseif (AKM_WINDOW_FRAME==mfi1) then
      AKM_WINDOW_FRAME=mfi7
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[45]
    end
    rna.window.active_middle_frame=AKM_WINDOW_FRAME
    vws.AKM_ROT_DIAL.value=AKM_WINDOW_FRAME-1
  end
end


function akm_right_dial()
  local mfp=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  local mfm=renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
  local mfi1=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PHRASE_EDITOR
  local mfi2=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_KEYZONES
  local mfi3=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
  local mfi4=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_MODULATION
  local mfi5=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EFFECTS
  local mfi6=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR
  local mfi7=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_MIDI_EDITOR
  if not (rna.window.instrument_editor_is_detached) then
    if (rna.window.active_middle_frame==mfp) then
      rna.window.active_middle_frame=mfi5
      rna.window.active_middle_frame=mfm
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[38]
    elseif (rna.window.active_middle_frame==mfm) then
      rna.window.active_middle_frame=mfi1
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[39]
    elseif (rna.window.active_middle_frame==mfi1) then
      rna.window.active_middle_frame=mfi2
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[40]
    elseif (rna.window.active_middle_frame==mfi2) then
      rna.window.active_middle_frame=mfi3
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[41]
    elseif (rna.window.active_middle_frame==mfi3) then
      rna.window.active_middle_frame=mfi4
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[42]
    elseif (rna.window.active_middle_frame==mfi4) then
      rna.window.active_middle_frame=mfi5
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[43]
    elseif (rna.window.active_middle_frame==mfi5) then
      rna.window.active_middle_frame=mfi6
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[44]
    elseif (rna.window.active_middle_frame==mfi6) then
      rna.window.active_middle_frame=mfi7
     vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[45]
    elseif (rna.window.active_middle_frame==mfi7) then
      rna.window.active_middle_frame=mfp
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[37]
    end
  else
    if (AKM_WINDOW_FRAME==mfi1) then
      AKM_WINDOW_FRAME=mfi2
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[40]
    elseif (AKM_WINDOW_FRAME==mfi2) then
      AKM_WINDOW_FRAME=mfi3
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[41]
    elseif (AKM_WINDOW_FRAME==mfi3) then
      AKM_WINDOW_FRAME=mfi4
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[42]
    elseif (AKM_WINDOW_FRAME==mfi4) then
      AKM_WINDOW_FRAME=mfi5
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[43]
    elseif (AKM_WINDOW_FRAME==mfi5) then
      AKM_WINDOW_FRAME=mfi6
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[44]
    elseif (AKM_WINDOW_FRAME==mfi6) then
      AKM_WINDOW_FRAME=mfi7
     vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[45]
    elseif (AKM_WINDOW_FRAME==mfi7) then
      AKM_WINDOW_FRAME=mfi1
      vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[37]
    end
    rna.window.active_middle_frame=AKM_WINDOW_FRAME
    vws.AKM_ROT_DIAL.value=AKM_WINDOW_FRAME-1
  end
end


function akm_bank_next()
  if (AKM_INS_REPEAT[3]) then
    if (song.selected_instrument_index>1) then
      song.selected_instrument_index=song.selected_instrument_index-1
    else
      song.selected_instrument_index=#song.instruments
    end
  end
  if (song.selected_instrument_index==1) then
    AKM_INS_REPEAT[3]=false
  end
end


function akm_bank_next_repeat(release)
  if not release then
    if rnt:has_timer(akm_bank_next_repeat) then
      rnt:remove_timer(akm_bank_next_repeat)
      if not (rnt:has_timer(akm_bank_next)) then
        rnt:add_timer(akm_bank_next,AKM_INS_REPEAT[1])
      end
    else
      if rnt:has_timer(akm_bank_next_repeat) then
        rnt:remove_timer(akm_bank_next_repeat)
      elseif rnt:has_timer(akm_bank_next) then
        rnt:remove_timer(akm_bank_next)
      end
      AKM_INS_REPEAT[3]=true
      akm_bank_next()
      rnt:add_timer(akm_bank_next_repeat,AKM_INS_REPEAT[2])
    end
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[48]
  else
    if rnt:has_timer(akm_bank_next_repeat) then
      rnt:remove_timer(akm_bank_next_repeat)
    elseif rnt:has_timer(akm_bank_next) then
      rnt:remove_timer(akm_bank_next)
    end
  end
end


function akm_bank_previous()
  if (AKM_INS_REPEAT[4]) then
    if (song.selected_instrument_index<#song.instruments) then
      song.selected_instrument_index=song.selected_instrument_index+1
    else
      song.selected_instrument_index=1
    end
  end
  if (song.selected_instrument_index==#song.instruments) then
    AKM_INS_REPEAT[4]=false
  end  
end


function akm_bank_previous_repeat(release)
  if not release then
    if rnt:has_timer(akm_bank_previous_repeat) then
      rnt:remove_timer(akm_bank_previous_repeat)
      if not (rnt:has_timer(akm_bank_previous)) then
        rnt:add_timer(akm_bank_previous,AKM_INS_REPEAT[1])
      end
    else
      if rnt:has_timer(akm_bank_previous_repeat) then
        rnt:remove_timer(akm_bank_previous_repeat)
      elseif rnt:has_timer(akm_bank_previous) then
        rnt:remove_timer(akm_bank_previous)
      end
      AKM_INS_REPEAT[4]=true
      akm_bank_previous()
      rnt:add_timer(akm_bank_previous_repeat,AKM_INS_REPEAT[2])
    end
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[49]
  else
    if rnt:has_timer(akm_bank_previous_repeat) then
      rnt:remove_timer(akm_bank_previous_repeat)
    elseif rnt:has_timer(akm_bank_previous) then
      rnt:remove_timer(akm_bank_previous)
    end
  end
end


function akm_mnt_nte_ins(nte,ins)
  vws.AKM_TXT_DIGITAL_2.text=("Note: %s\nInstrument: %s"):format(akm_note_tostring(nte),akm_instrument_tostring(ins))
end


function akm_mnt_vpd(vol,pan,dly)
  vws.AKM_TXT_DIGITAL_2.text=("Vol: %s  Pan: %s\nDelay: %s"):format(akm_volume_tostring(vol),akm_panning_tostring(pan),akm_delay_tostring(dly))
end


function akm_nc_previous_note()
  if (song.transport.edit_mode and AKM_VAL_LOCK[1]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.note_value<=121) then
        if (snc.note_value>0) then
          if (snc.note_value==120) then
            snc.note_value=48
          else
            snc.note_value=snc.note_value-1
          end
        end
      end
      if (snc.note_value<120) then
        snc.instrument_value=song.selected_instrument_index-1
      else
        snc.instrument_value=255
      end
      vws.AKM_ROT_1.value=snc.note_value
      akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
    end
  end
end


function akm_nc_next_note()
  if (song.transport.edit_mode and AKM_VAL_LOCK[1]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.note_value<=121) then
        if (snc.note_value<=120) then
          snc.note_value=snc.note_value+1
        end
      end
      if (snc.note_value<120) then
        snc.instrument_value=song.selected_instrument_index-1
      else
        snc.instrument_value=255
      end
      vws.AKM_ROT_1.value=snc.note_value
      akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
    end
  end
end


function akm_knob_note_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[1]) then
    local snc=song.selected_note_column
    if (snc) then
      local target=math.floor(raw/127*121+0.5)
      if (target<0) then target=0 elseif (target>121) then target=121 end
      snc.note_value=target
      if (target<120) then
        snc.instrument_value=song.selected_instrument_index-1
      else
        snc.instrument_value=255
      end
      if (vws and vws.AKM_ROT_1) then
        vws.AKM_ROT_1.value=target
      end
      akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
    end
  end
end


function akm_nc_previous_instrument()
  if (song.transport.edit_mode and AKM_VAL_LOCK[2]) then
    --print("previous_instrument")
    local snc=song.selected_note_column
    if (snc) then
      if (snc.instrument_value>0) and (snc.instrument_value<=#song.instruments) then
        snc.instrument_value=snc.instrument_value-1
        song.selected_instrument_index=snc.instrument_value+1
      elseif (snc.instrument_value>#song.instruments-1) then
        snc.instrument_value=#song.instruments-1
        song.selected_instrument_index=#song.instruments
      end
      vws.AKM_ROT_2.value=snc.instrument_value
      akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
    end
  end
end


function akm_nc_next_instrument()
  if (song.transport.edit_mode and AKM_VAL_LOCK[2]) then
    --print("next_instrument")
    local snc=song.selected_note_column
    if (snc) then
      if (snc.instrument_value<#song.instruments-1) then
        snc.instrument_value=snc.instrument_value+1
        song.selected_instrument_index=snc.instrument_value+1
      elseif (snc.instrument_value==#song.instruments-1) then
        snc.instrument_value=255
      end
      vws.AKM_ROT_2.value=snc.instrument_value
      akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
    end
  end
end


function akm_knob_instrument_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[2]) then
    local snc=song.selected_note_column
    if (snc) then
      local maxidx=#song.instruments-1
      if (maxidx<0) then maxidx=0 end
      local target=math.floor(raw/127*maxidx+0.5)
      if (target<0) then target=0 elseif (target>maxidx) then target=maxidx end
      snc.instrument_value=target
      song.selected_instrument_index=target+1
      if (vws and vws.AKM_ROT_2) then
        vws.AKM_ROT_2.value=raw*2
      end
      akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
    end
  end
end


function akm_nc_visible_volume()
  local sst=song.selected_track
  if not (sst.volume_column_visible) then
    sst.volume_column_visible=true
  end
end


function akm_nc_previous_volume()
  if (song.transport.edit_mode and AKM_VAL_LOCK[3]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.volume_value>0) and (snc.volume_value<=127) then
        snc.volume_value=snc.volume_value-1
      elseif (snc.volume_value==255) then
        snc.volume_value=127
      end
      akm_nc_visible_volume()
      if (snc.volume_value<=127) then
        vws.AKM_ROT_3.value=snc.volume_value*2
      elseif (snc.volume_value==255) then
        vws.AKM_ROT_3.value=snc.volume_value
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_nc_next_volume()
  if (song.transport.edit_mode and AKM_VAL_LOCK[3]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.volume_value<127) then
        snc.volume_value=snc.volume_value+1
      else
        snc.volume_value=255
      end
      akm_nc_visible_volume()
      if (snc.volume_value<=127) then
        vws.AKM_ROT_3.value=snc.volume_value*2
      elseif (snc.volume_value==255) then
        vws.AKM_ROT_3.value=snc.volume_value
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_knob_volume_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[3]) then
    local snc=song.selected_note_column
    if (snc) then
      local target
      if (raw>=127) then
        target=255
      else
        target=math.floor(raw/126*127+0.5)
        if (target<0) then target=0 elseif (target>127) then target=127 end
      end
      snc.volume_value=target
      akm_nc_visible_volume()
      if (vws and vws.AKM_ROT_3) then
        if (target<=127) then vws.AKM_ROT_3.value=target*2 else vws.AKM_ROT_3.value=target end
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_nc_visible_panning()
  local sst=song.selected_track
  if not (sst.panning_column_visible) then
    sst.panning_column_visible=true
  end
end


function akm_nc_previous_panning()
  if (song.transport.edit_mode and AKM_VAL_LOCK[4]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.panning_value>0) and (snc.panning_value<=127) then
        snc.panning_value=snc.panning_value-1
      elseif (snc.panning_value==255) then
        snc.panning_value=64--127
      end
      akm_nc_visible_panning()
      if (snc.panning_value<=127) then
        vws.AKM_ROT_4.value=snc.panning_value*2
      elseif (snc.panning_value==255) then
        vws.AKM_ROT_4.value=snc.panning_value
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_nc_next_panning()
  if (song.transport.edit_mode and AKM_VAL_LOCK[4]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.panning_value<127) then
        snc.panning_value=snc.panning_value+1
      else
        snc.panning_value=255
      end
      akm_nc_visible_panning()
      if (snc.panning_value<=127) then
        vws.AKM_ROT_4.value=snc.panning_value*2
      elseif (snc.panning_value==255) then
        vws.AKM_ROT_4.value=snc.panning_value
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_knob_panning_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[4]) then
    local snc=song.selected_note_column
    if (snc) then
      local target
      if (raw>=127) then
        target=255
      else
        target=math.floor(raw/126*127+0.5)
        if (target<0) then target=0 elseif (target>127) then target=127 end
      end
      snc.panning_value=target
      akm_nc_visible_panning()
      if (vws and vws.AKM_ROT_4) then
        if (target<=127) then vws.AKM_ROT_4.value=target*2 else vws.AKM_ROT_4.value=target end
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_nc_delay_val(val,lvl)
  if (AKM_VAL_LOCK[5]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      if (snc) then
        snc.delay_value=val
        akm_nc_visible_delay()
        akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
      end
    end
    if (lvl==1) then vws.AKM_SLD_5.value=vws.AKM_SLD_5.max
    elseif (lvl==2) then vws.AKM_SLD_5.value=vws.AKM_SLD_5.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_5.value=vws.AKM_SLD_5.max/2 
    elseif (lvl==4) then vws.AKM_SLD_5.value=vws.AKM_SLD_5.max/4
    elseif (lvl==5) then vws.AKM_SLD_5.value=vws.AKM_SLD_5.min
    end
  end
end


function akm_nc_visible_delay()
  local sst=song.selected_track
  if not (sst.delay_column_visible) then
    sst.delay_column_visible=true
  end
end


function akm_nc_previous_delay()
  if (song.transport.edit_mode and AKM_VAL_LOCK[5]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.delay_value>0) then
        snc.delay_value=snc.delay_value-1
      end
      akm_nc_visible_delay()
      if (vws and vws.AKM_ROT_5) then
        vws.AKM_ROT_5.value=snc.delay_value
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_nc_next_delay()
  if (song.transport.edit_mode and AKM_VAL_LOCK[5]) then
    local snc=song.selected_note_column
    if (snc) then
      if (snc.delay_value<255) then
        snc.delay_value=snc.delay_value+1
      end
      akm_nc_visible_delay()
      if (vws and vws.AKM_ROT_5) then
        vws.AKM_ROT_5.value=snc.delay_value
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_knob_delay_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[5]) then
    local snc=song.selected_note_column
    if (snc) then
      local target=math.floor(raw/127*255+0.5)
      if (target<0) then target=0 elseif (target>255) then target=255 end
      snc.delay_value=target
      akm_nc_visible_delay()
      if (vws and vws.AKM_ROT_5) then
        vws.AKM_ROT_5.value=target
      end
      akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
    end
  end
end


function akm_nc_visible_sfx()
  local sst=song.selected_track
  if not (sst.sample_effects_column_visible) then
    sst.sample_effects_column_visible=true
  end
end


function akm_previous_fx_val()
  if (song.transport.edit_mode and AKM_VAL_LOCK[6]) then
    local snc,sec=song.selected_note_column,song.selected_effect_column
    if (snc) then
      for val=#AKM_SFX,2,-1 do
        if (snc.effect_number_string==AKM_SFX[val]) then
          snc.effect_number_string=AKM_SFX[val-1]
          if (vws.AKM_ROT_6.max~=#AKM_SFX) then
            vws.AKM_ROT_6.max=#AKM_SFX-1
          end
          vws.AKM_ROT_6.value=val-2
          vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
          break
        end
      end
      akm_nc_visible_sfx()
    end
    if (sec) then
      for val=#AKM_EFF,2,-1 do
        if (sec.number_string==AKM_EFF[val]) then
          sec.number_string=AKM_EFF[val-1]
          if (vws.AKM_ROT_6.max~=#AKM_EFF) then
            vws.AKM_ROT_6.max=#AKM_EFF-1
          end
          vws.AKM_ROT_6.value=val-2
          if (string.sub(sec.number_string,1,1)=="Z") then
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
          else
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
          end
          break
        end
      end
    end
  end
end


function akm_next_fx_val()
  if (song.transport.edit_mode and AKM_VAL_LOCK[6]) then
    local snc,sec=song.selected_note_column,song.selected_effect_column
    if (snc) then
      for val=1,#AKM_SFX-1 do
        if (snc.effect_number_string==AKM_SFX[val]) then
          snc.effect_number_string=AKM_SFX[val+1]
          if (vws.AKM_ROT_6.max~=#AKM_SFX) then
            vws.AKM_ROT_6.max=#AKM_SFX-1
          end
          vws.AKM_ROT_6.value=val
          vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
          break

        end
      end
      akm_nc_visible_sfx()
    end
    if (sec) then
      for val=1,#AKM_EFF-1 do
        if (sec.number_string==AKM_EFF[val]) then
          sec.number_string=AKM_EFF[val+1]
          if (vws.AKM_ROT_6.max~=#AKM_EFF) then
            vws.AKM_ROT_6.max=#AKM_EFF-1
          end
          vws.AKM_ROT_6.value=val
          if (string.sub(sec.number_string,1,1)=="Z") then
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
          else
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
          end
          break
        end
      end
    end
  end
end


function akm_knob_fx_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[6]) then
    local snc,sec=song.selected_note_column,song.selected_effect_column
    if (snc) then
      local idx=math.floor(raw/127*(#AKM_SFX-1)+0.5)+1
      if (idx<1) then idx=1 elseif (idx>#AKM_SFX) then idx=#AKM_SFX end
      snc.effect_number_string=AKM_SFX[idx]
      if (vws and vws.AKM_ROT_6) then
        vws.AKM_ROT_6.max=#AKM_SFX-1
        vws.AKM_ROT_6.value=idx-1
      end
      vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
      akm_nc_visible_sfx()
    end
    if (sec) then
      local idx=math.floor(raw/127*(#AKM_EFF-1)+0.5)+1
      if (idx<1) then idx=1 elseif (idx>#AKM_EFF) then idx=#AKM_EFF end
      sec.number_string=AKM_EFF[idx]
      if (vws and vws.AKM_ROT_6) then
        vws.AKM_ROT_6.max=#AKM_EFF-1
        vws.AKM_ROT_6.value=idx-1
      end
      if (string.sub(sec.number_string,1,1)=="Z") then
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
      else
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
      end
    end
  end
end


function akm_previous_fx_amo()
  if (song.transport.edit_mode and AKM_VAL_LOCK[7]) then
    local snc,sec=song.selected_note_column,song.selected_effect_column
    if (snc) then
      if (snc.effect_amount_value>0) then
        snc.effect_amount_value=snc.effect_amount_value-1
      end
      vws.AKM_ROT_7.value=snc.effect_amount_value
      vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
      akm_nc_visible_sfx()
    end
    if (sec) then
      if (sec.amount_value>0) then
        sec.amount_value=sec.amount_value-1
      end
      vws.AKM_ROT_7.value=sec.amount_value
      if (string.sub(sec.number_string,1,1)=="Z") then
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
      else
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
      end
    end
  end
end


function akm_next_fx_amo()
  if (song.transport.edit_mode and AKM_VAL_LOCK[7]) then
    local snc,sec=song.selected_note_column,song.selected_effect_column
    if (snc) then
      if (snc.effect_amount_value<255) then
        snc.effect_amount_value=snc.effect_amount_value+1
      end
      vws.AKM_ROT_7.value=snc.effect_amount_value
      vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
      akm_nc_visible_sfx()
    end
   
   
   
    if (sec) then
      if (sec.amount_value<255) then
        sec.amount_value=sec.amount_value+1
      end
      vws.AKM_ROT_7.value=sec.amount_value
      if (string.sub(sec.number_string,1,1)=="Z") then
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
      else
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
      end
    end
  end
end


function akm_knob_fx_amo_val(raw)
  if (song.transport.edit_mode and AKM_VAL_LOCK[7]) then
    local snc,sec=song.selected_note_column,song.selected_effect_column
    local target=math.floor(raw/127*255+0.5)
    if (target<0) then target=0 elseif (target>255) then target=255 end
    if (snc) then
      snc.effect_amount_value=target
      if (vws and vws.AKM_ROT_7) then vws.AKM_ROT_7.value=target end
      vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
      akm_nc_visible_sfx()
    end
    if (sec) then
      sec.amount_value=target
      if (vws and vws.AKM_ROT_7) then vws.AKM_ROT_7.value=target end
      if (string.sub(sec.number_string,1,1)=="Z") then
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
      else
        vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
      end
    end
  end
end


-- NC/EC column navigation. Note: the widget-fill math below scales against
-- this TRACK's actual visible_note_columns/visible_effect_columns (not a fixed
-- assumption) so it stays correct on tracks with fewer columns than the
-- hardware max. It's wrapped in math.min/max clamps because that scaling can
-- push slightly past the widget's valid 0-127 range right at the top end -
-- learned that the hard way, don't remove the clamps.
function akm_previous_nc_ec()
  if (AKM_VAL_LOCK[8]) then
    if (song.selected_track.type==renoise.Track.TRACK_TYPE_SEQUENCER) then
      if (song.selected_note_column) then
        if (song.selected_note_column_index>1) then
          song.selected_note_column_index=song.selected_note_column_index-1
          vws.AKM_ROT_8.value=math.min(127,math.max(0,math.floor((song.selected_note_column_index-1)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))))
          vws.AKM_TXT_DIGITAL_2.text=("Note Column %s"):format(song.selected_note_column_index)
        end
      else
        if (song.selected_effect_column_index>1) then
          song.selected_effect_column_index=song.selected_effect_column_index-1
          vws.AKM_ROT_8.value=math.min(127,math.max(0,math.floor((song.selected_effect_column_index-1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))))
          vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
        end
      end
    else
      if (song.selected_effect_column_index>1) then
        song.selected_effect_column_index=song.selected_effect_column_index-1
        vws.AKM_ROT_8.value=math.min(127,math.max(0,math.floor((song.selected_effect_column_index-1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))))
        vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
      end
    end
    if (song.selected_note_column_index==1 or song.selected_effect_column_index==1) then
      akm_collapse_col_trk(true)
    end
  end
end


function akm_next_nc_ec()
  if (AKM_VAL_LOCK[8]) then
    if (song.selected_track.type==renoise.Track.TRACK_TYPE_SEQUENCER) then
      if (song.selected_note_column) then
        if (song.selected_track.visible_note_columns<12 and song.selected_track.visible_note_columns==song.selected_note_column_index) then
          song.selected_track.visible_note_columns=song.selected_note_column_index+1
        end
        if (song.selected_note_column_index<song.selected_track.visible_note_columns) then
          song.selected_note_column_index=song.selected_note_column_index+1
          vws.AKM_ROT_8.value=math.min(127,math.max(0,math.floor((song.selected_note_column_index+1)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))))
          vws.AKM_TXT_DIGITAL_2.text=("Note Column %s"):format(song.selected_note_column_index)
        end
      else
        if (song.selected_track.visible_effect_columns<8 and song.selected_track.visible_effect_columns==song.selected_effect_column_index) then
          song.selected_track.visible_effect_columns=song.selected_effect_column_index+1
        end
        if (song.selected_effect_column_index<song.selected_track.visible_effect_columns) then
          song.selected_effect_column_index=song.selected_effect_column_index+1
          vws.AKM_ROT_8.value=math.min(127,math.max(0,math.floor((song.selected_effect_column_index+1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))))
          vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
        end
      end
    else
      if (song.selected_track.visible_effect_columns<8 and song.selected_track.visible_effect_columns==song.selected_effect_column_index) then
        song.selected_track.visible_effect_columns=song.selected_effect_column_index+1
      end
      if (song.selected_effect_column_index<song.selected_track.visible_effect_columns) then
        song.selected_effect_column_index=song.selected_effect_column_index+1
        vws.AKM_ROT_8.value=math.min(127,math.max(0,math.floor((song.selected_effect_column_index+1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))))
        vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
      end
    end
  end
end


function akm_step_length(value)
  if (AKM_VAL_LOCK[9]) then
    local sli=song.selected_line_index
    local nol=song.selected_pattern.number_of_lines
    local edit_step=song.transport.edit_step
    if (value>0) then
      if (nol>=sli+edit_step) then
        song.selected_line_index=sli+edit_step
      else
        local difference=edit_step-(nol-sli)
        --print(difference)
        if (song.selected_sequence_index+1<=#song.sequencer.pattern_sequence) then
          song.selected_sequence_index=song.selected_sequence_index+1
          if (difference<=song.selected_pattern.number_of_lines) then
            song.selected_line_index=difference
          else
            song.selected_line_index=1
          end
        else
          song.selected_line_index=song.selected_pattern.number_of_lines
        end
      end
    else
      local difference=edit_step-sli
      --print(difference)
      if (sli>edit_step) then
        song.selected_line_index=song.selected_line_index-edit_step
      else
        if (song.selected_sequence_index-1>=1) then
          song.selected_sequence_index=song.selected_sequence_index-1
          if (1<=song.selected_pattern.number_of_lines-difference) then
            song.selected_line_index=song.selected_pattern.number_of_lines-difference
          end
        else
          song.selected_line_index=1
        end
      end
    end
    --vws.AKM_ROT_9.value=edit_step*127/64
    vws.AKM_TXT_DIGITAL_2.text=("Line %.2d"):format(song.selected_line_index-1)
  end
end


function akm_nc_note_val(val,lvl)
  if (AKM_VAL_LOCK[1]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      if (snc) then
        snc.note_value=val
        if (snc.note_value<120) then
          snc.instrument_value=song.selected_instrument_index-1
        else
          snc.instrument_value=255
        end
        akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
      end
    end
    if (lvl==1) then vws.AKM_SLD_1.value=vws.AKM_SLD_1.max
    elseif (lvl==2) then vws.AKM_SLD_1.value=vws.AKM_SLD_1.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_1.value=vws.AKM_SLD_1.max/2 
    elseif (lvl==4) then vws.AKM_SLD_1.value=vws.AKM_SLD_1.max
    end
  end
end


function akm_nc_instrument_val(val,lvl)
  if (AKM_VAL_LOCK[2]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      if (snc) then
        snc.instrument_value=val
        akm_mnt_nte_ins(snc.note_value,snc.instrument_value)
      end
    end
    if (lvl==1) then vws.AKM_SLD_2.value=vws.AKM_SLD_2.max
    elseif (lvl==2) then vws.AKM_SLD_2.value=vws.AKM_SLD_2.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_2.value=vws.AKM_SLD_2.max/2 
    elseif (lvl==4) then vws.AKM_SLD_2.value=vws.AKM_SLD_2.max/4
    elseif (lvl==5) then vws.AKM_SLD_2.value=vws.AKM_SLD_2.min
    end
  end
end


function akm_nc_volume_val(val,lvl)
  if (AKM_VAL_LOCK[3]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      if (snc) then
        if (val>127 and val<255) then
          snc.volume_value=127
        else
          snc.volume_value=val
        end
        akm_nc_visible_volume()
        akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
      end
    end
    if (lvl==1) then vws.AKM_SLD_3.value=vws.AKM_SLD_3.max
    elseif (lvl==2) then vws.AKM_SLD_3.value=vws.AKM_SLD_3.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_3.value=vws.AKM_SLD_3.max/2 
    elseif (lvl==4) then vws.AKM_SLD_3.value=vws.AKM_SLD_3.max/4
    elseif (lvl==5) then vws.AKM_SLD_3.value=vws.AKM_SLD_3.min
    end
  end
end


function akm_nc_panning_val(val,lvl)
  if (AKM_VAL_LOCK[4]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      if (snc) then
        if (val>127 and val<255) then
          snc.panning_value=128
        else
          snc.panning_value=val
        end
        akm_nc_visible_panning()
        akm_mnt_vpd(snc.volume_value,snc.panning_value,snc.delay_value)
      end
    end
    if (lvl==1) then vws.AKM_SLD_4.value=vws.AKM_SLD_4.max
    elseif (lvl==2) then vws.AKM_SLD_4.value=vws.AKM_SLD_4.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_4.value=vws.AKM_SLD_4.max/2 
    elseif (lvl==4) then vws.AKM_SLD_4.value=vws.AKM_SLD_4.max/4
    elseif (lvl==5) then vws.AKM_SLD_4.value=vws.AKM_SLD_4.min
    end
  end
end


function akm_sfx_fx_val(val,lvl)
  if (AKM_VAL_LOCK[6]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      local sec=song.selected_effect_column
      if (song.selected_track.type==renoise.Track.TRACK_TYPE_SEQUENCER) then
        if (snc) then
          if (vws.AKM_SLD_6.max~=#AKM_SFX) then
            vws.AKM_SLD_6.max=#AKM_SFX
          end
          if (val<=#AKM_SFX) then
            snc.effect_number_string=AKM_SFX[val]
          end
          akm_nc_visible_sfx()
          vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
        else
          if (vws.AKM_SLD_6.max~=#AKM_EFF) then
            vws.AKM_SLD_6.max=#AKM_EFF
          end
          sec.number_string=AKM_EFF[val]
          if (string.sub(sec.number_string,1,1)=="Z") then
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
          else
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
          end
        end
      else
        if (vws.AKM_SLD_6.max~=#AKM_EFF) then
          vws.AKM_SLD_6.max=#AKM_EFF
        end
        sec.number_string=AKM_EFF[val]
        if (string.sub(sec.number_string,1,1)=="Z") then
          vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
        else
          vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
        end
      end
    end
    if (lvl==1) then vws.AKM_SLD_6.value=vws.AKM_SLD_6.max
    elseif (lvl==2) then vws.AKM_SLD_6.value=vws.AKM_SLD_6.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_6.value=vws.AKM_SLD_6.max/2 
    elseif (lvl==4) then vws.AKM_SLD_6.value=vws.AKM_SLD_6.max/4
    elseif (lvl==5) then vws.AKM_SLD_6.value=vws.AKM_SLD_6.min
    end
  end
end


function akm_amount_val(val,lvl)
  if (AKM_VAL_LOCK[7]) then
    if (song.transport.edit_mode) then
      local snc=song.selected_note_column
      local sec=song.selected_effect_column
      if (song.selected_track.type==renoise.Track.TRACK_TYPE_SEQUENCER) then
        if (snc) then
          snc.effect_amount_value=val
          akm_nc_visible_sfx()
          vws.AKM_TXT_DIGITAL_2.text=("sFX: %s%.2X"):format(string.sub(snc.effect_number_string,2),snc.effect_amount_value)
        else
          sec.amount_value=val
          if (string.sub(sec.number_string,1,1)=="Z") then
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
          else
            vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
          end
        end
      else
        sec.amount_value=val
        if (string.sub(sec.number_string,1,1)=="Z") then
          vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(sec.number_string,sec.amount_value)
        else
          vws.AKM_TXT_DIGITAL_2.text=("FX: %s%.2X"):format(string.sub(sec.number_string,2),sec.amount_value)
        end
      end
    end
    if (lvl==1) then vws.AKM_SLD_7.value=vws.AKM_SLD_7.max
    elseif (lvl==2) then vws.AKM_SLD_7.value=vws.AKM_SLD_7.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_7.value=vws.AKM_SLD_7.max/2 
    elseif (lvl==4) then vws.AKM_SLD_7.value=vws.AKM_SLD_7.max/4
    elseif (lvl==5) then vws.AKM_SLD_7.value=vws.AKM_SLD_7.min
    end
  end
end


function akm_nc_ec_val(val,lvl)
  if (AKM_VAL_LOCK[8]) then
    local snc=song.selected_note_column
    local sec=song.selected_effect_column
    if (song.selected_track.type==renoise.Track.TRACK_TYPE_SEQUENCER) then
      if (val<=12) then
        if (song.selected_track.visible_note_columns<val) then
          song.selected_track.visible_note_columns=val
        end
        song.selected_note_column_index=val
        vws.AKM_TXT_DIGITAL_2.text=("Note Column %s"):format(song.selected_note_column_index)
      else
        if (song.selected_track.visible_effect_columns<val-12) then
          song.selected_track.visible_effect_columns=val-12
        end
        song.selected_effect_column_index=val-12
        vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
      end
    else
      if (val>=13) then
        if (song.selected_track.visible_effect_columns<val-12) then
          song.selected_track.visible_effect_columns=val-12
        end
        song.selected_effect_column_index=val-12
        vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
      end
    end
    if (val==1 or val==13) then
      akm_collapse_col_trk(true)
    end
    if (lvl==1) then vws.AKM_SLD_8.value=vws.AKM_SLD_8.max
    elseif (lvl==2) then vws.AKM_SLD_8.value=vws.AKM_SLD_8.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_8.value=vws.AKM_SLD_8.max/2 
    elseif (lvl==4) then vws.AKM_SLD_8.value=vws.AKM_SLD_8.max/4
    elseif (lvl==5) then vws.AKM_SLD_8.value=vws.AKM_SLD_8.min
    end
  end
end


function akm_sq_step_val(val,lvl)
  if (AKM_VAL_LOCK[9]) then
    local nol=song.selected_pattern.number_of_lines
    if (val<=nol) then
      song.selected_line_index=val+1
    else
      song.selected_line_index=nol
    end
    vws.AKM_TXT_DIGITAL_2.text=("Line %.2d"):format(song.selected_line_index-1)
    if (lvl==1) then vws.AKM_SLD_9.value=vws.AKM_SLD_9.max
    elseif (lvl==2) then vws.AKM_SLD_9.value=vws.AKM_SLD_9.max/4*3
    elseif (lvl==3) then vws.AKM_SLD_9.value=vws.AKM_SLD_9.max/2 
    elseif (lvl==4) then vws.AKM_SLD_9.value=vws.AKM_SLD_9.max/4
    elseif (lvl==5) then vws.AKM_SLD_9.value=vws.AKM_SLD_9.min
    end
  end
end



function akm_button_dial()
  local mfp=renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR
  local mfm=renoise.ApplicationWindow.MIDDLE_FRAME_MIXER
  local mfi=renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR
  if not (rna.window.instrument_editor_is_detached) then
    if (rna.window.active_middle_frame~=mfp and rna.window.active_middle_frame~=mfi) then
      rna.window.active_middle_frame=mfp
    else
      if (rna.window.active_middle_frame==mfp) then
        rna.window.active_middle_frame=mfi
        vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[44]
      elseif (rna.window.active_middle_frame==mfi) then
        rna.window.active_middle_frame=mfp
        vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[37]
      end
    end
  else
    if (rna.window.active_middle_frame~=mfp) then
      rna.window.active_middle_frame=mfp
    else
      rna.window.active_middle_frame=mfm
    end    
  end
end


function akm_collapse_col_trk(bol)
  local sti=song.selected_track_index
  local trk=song.selected_track
  local sub=string.sub
  local reverse=string.reverse
  local match=string.match
  local find=string.find
  local max=math.max
  local floor=math.floor
  local has_nc=trk.type==renoise.Track.TRACK_TYPE_SEQUENCER
  local max_nc=1
  local max_ec
  if (has_nc) then
    max_ec=1
  else
    max_ec=1
  end  
  for _,pattern in ipairs(song.patterns) do
    local patterntrack=pattern:track(sti)
    if not (patterntrack.is_empty) then
      local lns=patterntrack:lines_in_range(1,pattern.number_of_lines)
      for _,lne in ipairs(lns) do
        if not (lne.is_empty) then
          local lne_str=tostring(lne)
          --note columns
          if (has_nc) then
            local ncol_lne_str=sub(lne_str,0,214)
            ncol_lne_str=reverse(ncol_lne_str)
            local first_match=match(ncol_lne_str,"%d.[1-G]")
            max_nc=(first_match and max(max_nc, 12-floor(find(ncol_lne_str,first_match) / 18))) or max_nc         
          end
          --effect columns
          local ecol_lne_str=reverse(lne_str)
          local ecol_first_match=match(ecol_lne_str,"[1-Z]")
          max_ec=(ecol_first_match and math.max(max_ec, 8-floor(find(ecol_lne_str,ecol_first_match)/7))) or max_ec
        end
      end
    end
  end
  if (bol) then
    if (has_nc) then
      if (song.selected_note_column) then
        trk.visible_note_columns=max_nc
      else
        trk.visible_effect_columns=max_ec
      end
    else
      trk.visible_effect_columns=max_ec
    end
  else
    trk.visible_effect_columns=max_ec
  end
end
