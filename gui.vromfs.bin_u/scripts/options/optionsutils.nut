//-file:plus-string
from "%scripts/dagui_natives.nut" import get_thermovision_index, set_thermovision_index
from "%scripts/dagui_library.nut" import *
from "%scripts/controls/controlsConsts.nut" import optionControlType

let u = require("%sqStdLibs/helpers/u.nut")
let { get_option_bool } = require("gameOptions")
let { blkFromPath } = require("%sqstd/datablock.nut")
let { showedUnit } = require("%scripts/slotbar/playerCurUnit.nut")
let { GUI } = require("%scripts/utils/configs.nut")
let { get_gui_option } = require("guiOptions")
let { get_game_mode } = require("mission")
let { startsWith } = require("%sqstd/string.nut")
let { script_net_assert_once } = require("%sqStdLibs/helpers/net_errors.nut")
let { OPTIONS_MODE_GAMEPLAY, USEROPT_HUD_SHOW_TANK_GUNS_AMMO
} = require("%scripts/options/optionsExtNames.nut")
let { getDynamicLayouts } = require("%scripts/missions/missionsUtils.nut")

let changedOptionReqRestart = mkWatched(persist, "changedOptionReqRestart", {})

let checkArgument = function(id, arg, varType) {
  if (type(arg) == varType)
    return true

  local msg = "[ERROR] Wrong argument type supplied for option item '" + id + ".\n"
  msg += "Value = " + toString(arg) + ".\n"
  msg += "Expected '" + varType + "' found '" + type(arg) + "'."

  script_net_assert_once(id, msg)
  return false
}

let createDefaultOption = function() {
  return {
    type = -1
    id = ""
    title = null //"options/" + descr.id
    hint = null  //"guiHints/" + descr.id
    value = null
    controlType = optionControlType.LIST
    hasWarningIcon = false
    context = null
    optionCb = null
    items = null
    values = null
    needShowValueText = false
    needRestartClient = false
    diffCode = null

    getTrId = @() this.id + "_tr"

    getTitle = @() this.title || loc("options/" + this.id)

    getCurrentValueLocText = @() this.getValueLocText(this.value)

    getValueLocText = function(val) {
      let ctype = this.controlType
      if (ctype == optionControlType.CHECKBOX) {
        if (val == true)
          return loc("options/yes")
        else if (val == false)
          return loc("options/no")
      }

      else if ( ctype == optionControlType.LIST) {
        let result = getTblValue(this.values.indexof(val), this.items)
        local locKey = (u.isString(result)) ? result : getTblValue("text", result, "")
        if (startsWith(locKey, "#"))
          locKey = locKey.slice(1)
        return loc(locKey)
      }
      else {
        if (val != null)
          return val.tostring()
      }
      return ""
    }

    onChangeCb = null
  }
}

let fillBoolOption = function(descr, id, optionIdx) {
  descr.id = id
  descr.controlType = optionControlType.CHECKBOX
  descr.controlName <- "switchbox"
  descr.value = get_option_bool(optionIdx)
  descr.boolOptionIdx <- optionIdx
}

let setHSVOption_ThermovisionColor = function(_desrc, value) {
  set_thermovision_index(value)
}

let fillHSVOption_ThermovisionColor = function(descr) {
  descr.id = "color_picker_hue_tank_tv"
  descr.items = []
  descr.values = []

  local idx = 0
  foreach (it in ::thermovision_colors) {
    descr.items.append({ rgb = it.menu_rgb })
    descr.values.append(idx)
    idx++
  }

  descr.value = get_thermovision_index()
}

let function addHueParamsToOptionDescr(descr, hue, text = null, sat = null, val = null) {
  let defV = hue > 360 ? 1.0 : 0.7
  descr.items.append({ hue, sat = sat ?? defV, val = val ?? defV, text })
  descr.values.append(hue)
}

//Allow White and Black color
let function fillHueSaturationBrightnessOption(descr, id, defHue = null, defSat = null, defBri = null,
  curHue = null) {
  let hueStep = 22.5
  if (curHue == null)
    curHue = get_gui_option(descr.type)
  if (!is_numeric(curHue))
    curHue = -1

  descr.id = id
  descr.items = []
  descr.values = []
  if (defHue != null)
    addHueParamsToOptionDescr(descr, defHue, loc("options/hudDefault"), defSat, defBri)

  //default palette
  local even = false
  for (local hue = 0.0001; hue < 360.0 - 0.5 * hueStep; hue += hueStep) {
    addHueParamsToOptionDescr(descr, hue + (even ? 360.0 : 0))
    addHueParamsToOptionDescr(descr, hue + (even ? 0 : 360.0))
    even = !even
  }

  if ((defSat ?? 0) >= 0.000001) //create white (in case it's not default)
    addHueParamsToOptionDescr(descr, 10.0, null, 0.0, 0.9)

  //now black
  addHueParamsToOptionDescr(descr, 0.0, null, 0.0, 0.0)

  local valueIdx = ::find_nearest(curHue, descr.values)
  if (curHue == -1)
    valueIdx = 0 // defValue
  if (valueIdx >= 0)
    descr.value = valueIdx
}

let function fillHueOption(descr, id, curHue = null, defHue = null, defSat = null, defBri = null) {
  let hueStep = 22.5
  if (curHue == null)
    curHue = get_gui_option(descr.type)
  if (!is_numeric(curHue))
    curHue = -1

  descr.id = id
  descr.items = []
  descr.values = []
  if (defHue != null)
    addHueParamsToOptionDescr(descr, defHue, loc("options/hudDefault"), defSat, defBri)

  //default palette
  local even = false
  for (local hue = 0.0001; hue < 360.0 - 0.5 * hueStep; hue += hueStep) {
    addHueParamsToOptionDescr(descr, hue + (even ? 360.0 : 0))
    addHueParamsToOptionDescr(descr, hue + (even ? 0 : 360.0))
    even = !even
  }

  local valueIdx = ::find_nearest(curHue, descr.values)
  if (curHue == -1)
    valueIdx = 0 // defValue
  if (valueIdx >= 0)
    descr.value = valueIdx
}

let function fillMultipleHueOption(descr, id, currentHueIndex) {
  descr.id = id
  descr.items = []
  descr.values = []
  let alertHueBlock = GUI.get()?.alertHue
  if (!u.isDataBlock(alertHueBlock))
    return
  for (local i = 0; i < alertHueBlock.blockCount(); ++i) {
    let hueValues = []
    let hueBlock = alertHueBlock.getBlock(i)
    for (local j = 0; j < hueBlock.paramCount(); ++j) {
      hueValues.append(hueBlock.getParamValue(j))
    }
    if (i == 0)
      descr.items.append({ hues = hueValues, text = loc("options/hudDefault") })
    else
      descr.items.append({ hues = hueValues })
    descr.values.append(hueValues)
  }
  descr.value = currentHueIndex
}

let fillDynMapOption = function(descr) {
  let curMap = getTblValue("layout", ::mission_settings)
  let dynLayouts = getDynamicLayouts()
  foreach (layout in dynLayouts) {
    if (get_game_mode() == GM_BUILDER) {
      let db = blkFromPath(layout.mis_file)
      let tags = db.mission_settings.mission.tags % "tag"
      let airTags = showedUnit.value?.tags ?? []
      local skip = false
      foreach (tag in tags) {
        local found = false
        foreach (atag in airTags)
          if (atag == tag) {
            found = true
            break
          }
        if (!found) {
          skip = true
          log("SKIP " + layout.name + " because of tag " + tag)
          break
        }
      }
      if (skip)
        continue
    }
    descr.items.append("#dynamic/" + layout.name)
    let map = layout.mis_file
    descr.values.append(map)
    if (map == curMap)
      descr.value <- descr.values.len() - 1
  }

  if (descr.items.len() == 0 && dynLayouts.len() > 0) {
    log("[WARNING] All dynamic layouts are skipped due to tags of current aircraft. Adding '" +
      dynLayouts[0].name + "' to avoid empty list.")

    // must be at least one dynamic layout in USEROPT_DYN_MAP
    descr.items.append("#dynamic/" + dynLayouts[0].name)
    descr.values.append(dynLayouts[0].mis_file)
  }
}

let function setOptionReqRestartValue(option) {
  if (option.type in changedOptionReqRestart.value)
    return

  changedOptionReqRestart.value[option.type] <- option.value
}

let function isOptionReqRestartChanged(option, newValue) {
  let baseValue = changedOptionReqRestart.value?[option.type]
  return baseValue != null && baseValue != newValue
}

let function isVisibleTankGunsAmmoIndicator() {
  return hasFeature("MachineGunsAmmoIndicator")
    && ::get_gui_option_in_mode(USEROPT_HUD_SHOW_TANK_GUNS_AMMO, OPTIONS_MODE_GAMEPLAY, false)
}

::cross_call_api.isVisibleTankGunsAmmoIndicator <- @() isVisibleTankGunsAmmoIndicator()

return {
  checkArgument
  createDefaultOption
  fillBoolOption
  fillHueSaturationBrightnessOption
  fillHueOption
  fillMultipleHueOption
  fillDynMapOption
  setHSVOption_ThermovisionColor
  fillHSVOption_ThermovisionColor
  isOptionReqRestartChanged
  setOptionReqRestartValue
  isVisibleTankGunsAmmoIndicator
}