-----------------------------------------------------------------------------------------------
-- Arturia KeyLab Essential mk3 (AKM) - action functions
-- Everything that happens when a pad/knob/fader/transport button is pressed or turned.
-- Loaded by main.lua alongside akm.lua. All functions here are plain globals (not local)
-- so akm.lua's midi_callback can call them directly across the file boundary.
-----------------------------------------------------------------------------------------------

function akm_tap_led_dim_callback()
  akm_essential_set_led(0x17,0x18,0x18,0x18)
  if (renoise.tool():has_timer(akm_tap_led_dim_callback)) then
    renoise.tool():remove_timer(akm_tap_led_dim_callback)
  end
end


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
    return
  else
    rna:save_song_as(filename)
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[16]
  end
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


function akm_song_undo()
  if (song.can_undo) then song:undo() end
end


function akm_song_redo()
  if (song.can_redo) then song:redo() end
end


function akm_stop()
  song.transport:stop()
  vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[27]
  if not (song.transport.playing) then
    song.transport:panic()
    vws.AKM_TXT_DIGITAL_1.text=akm_tbl_dm1[28]
    --print("panic")
  end
end


function akm_quantize()
  song.transport.record_quantize_enabled=not song.transport.record_quantize_enabled
  if (song.transport.record_quantize_enabled) then
    vws.AKM_TXT_DIGITAL_1.text=("Quantize: ON (%d lines)"):format(song.transport.record_quantize_lines)
    akm_essential_set_led(0x0D,0x7F,0x7F,0x7F)
  else
    vws.AKM_TXT_DIGITAL_1.text="Quantize: OFF"
    akm_essential_set_led(0x0D,0x10,0x10,0x10)
  end
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


function akm_previous_nc_ec()
  if (AKM_VAL_LOCK[8]) then
    if (song.selected_track.type==renoise.Track.TRACK_TYPE_SEQUENCER) then
      if (song.selected_note_column) then
        if (song.selected_note_column_index>1) then
          song.selected_note_column_index=song.selected_note_column_index-1
          vws.AKM_ROT_8.value=math.floor((song.selected_note_column_index-1)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))
          vws.AKM_TXT_DIGITAL_2.text=("Note Column %s"):format(song.selected_note_column_index)
        end
      else
        if (song.selected_effect_column_index>1) then
          song.selected_effect_column_index=song.selected_effect_column_index-1
          vws.AKM_ROT_8.value=math.floor((song.selected_effect_column_index-1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))
          vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
        end
      end
    else
      if (song.selected_effect_column_index>1) then
        song.selected_effect_column_index=song.selected_effect_column_index-1
        vws.AKM_ROT_8.value=math.floor((song.selected_effect_column_index-1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))
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
          vws.AKM_ROT_8.value=math.floor((song.selected_note_column_index+1)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))
          vws.AKM_TXT_DIGITAL_2.text=("Note Column %s"):format(song.selected_note_column_index)
        end
      else
        if (song.selected_track.visible_effect_columns<8 and song.selected_track.visible_effect_columns==song.selected_effect_column_index) then
          song.selected_track.visible_effect_columns=song.selected_effect_column_index+1
        end
        if (song.selected_effect_column_index<song.selected_track.visible_effect_columns) then
          song.selected_effect_column_index=song.selected_effect_column_index+1
          vws.AKM_ROT_8.value=math.floor((song.selected_effect_column_index+1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))
          vws.AKM_TXT_DIGITAL_2.text=("Effect Column %s"):format(song.selected_effect_column_index)
        end
      end
    else
      if (song.selected_track.visible_effect_columns<8 and song.selected_track.visible_effect_columns==song.selected_effect_column_index) then
        song.selected_track.visible_effect_columns=song.selected_effect_column_index+1
      end
      if (song.selected_effect_column_index<song.selected_track.visible_effect_columns) then
        song.selected_effect_column_index=song.selected_effect_column_index+1
        vws.AKM_ROT_8.value=math.floor((song.selected_effect_column_index+1+song.selected_track.visible_note_columns)*127/(song.selected_track.visible_note_columns+song.selected_track.visible_effect_columns))
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
