from "%rGui/globals/ui_library.nut" import *

let { send } = require("eventbus")
let { mkRadar } = require("radarComponent.nut")
let aamAim = require("rocketAamAim.nut")
let agmAim = require("agmAim.nut")
let actionBarTopPanel = require("hud/actionBarTopPanel.nut")
let tws = require("tws.nut")
let { IsMlwsLwsHudVisible, CollapsedIcon } = require("twsState.nut")
let sightIndicators = require("hud/tankSightIndicators.nut")
let activeProtectionSystem = require("%rGui/hud/activeProtectionSystem.nut")
let { isVisibleDmgIndicator, dmgIndicatorStates } = require("%rGui/hudState.nut")
let { IndicatorsVisible } = require("%rGui/hud/tankState.nut")
let { lockSight, targetSize } = require("%rGui/hud/targetTracker.nut")
let { bw, bh } = require("style/screenState.nut")
let { AzimuthRange, IsRadarVisible, IsRadar2Visible, IsRadarHudVisible, IsCScopeVisible, IsBScopeVisible } = require("radarState.nut")
let { PI } = require("%sqstd/math.nut")
let radarHud = require("%rGui/radar.nut")
//




let greenColor = Color(10, 202, 10, 250)
let redColor = Color(255, 35, 30, 255)

let styleAamAim = {
  color = greenColor
  fillColor = Color(0, 0, 0, 0)
  lineWidth = hdpx(2.0)
}

let radarPosComputed = Computed(@() [bw.value, bh.value])

let tankXrayIndicator = @() {
  rendObj = ROBJ_XRAYDOLL
  rotateWithCamera = true
  size = [pw(62), ph(62)]
}

let xraydoll = {
  rendObj = ROBJ_XRAYDOLL     ///Need add ROBJ_XRAYDOLL in scene for correct update isVisibleDmgIndicator state
  size = [1, 1]
}

let function tankDmgIndicator() {
  if (!isVisibleDmgIndicator.value)
    return {
      watch = isVisibleDmgIndicator
      children = xraydoll
    }

  let colorWacthed = Watched(greenColor)
  let children = [
    tankXrayIndicator,
    activeProtectionSystem,
    //


  ]
  if (IsMlwsLwsHudVisible.value)
    children.append(tws({
      colorWatched = colorWacthed,
      posWatched = Watched([0, 0]),
      sizeWatched = Computed(@() dmgIndicatorStates.value.size.map(@(v) 0.8*v)),
      relativCircleSize = 49,
      needDrawCentralIcon = false,
      needDrawBackground =  true,
      needAdditionalLights = false
    }))
  return {
    rendObj = ROBJ_IMAGE
    watch = [ IsMlwsLwsHudVisible, isVisibleDmgIndicator, dmgIndicatorStates ]
    pos = dmgIndicatorStates.value?.pos ?? [0, 0]
    size = dmgIndicatorStates.value.size
    halign = ALIGN_CENTER
    valign = ALIGN_CENTER
    image = Picture($"ui/gameuiskin/bg_dmg_board.svg:{dmgIndicatorStates.value.size[0]}:{dmgIndicatorStates.value.size[1]}")
    children
    behavior = Behaviors.RecalcHandler
    function onRecalcLayout(_initial, elem) {
      if (elem.getWidth() > 1 && elem.getHeight() > 1) {
        send("update_damage_panel_state", {
          pos = [elem.getScreenPosX(), elem.getScreenPosY()]
          size = [elem.getWidth(), elem.getHeight()]
          visible = isVisibleDmgIndicator.value
        })
      }
      else
        send("update_damage_panel_state", {})
    }
  }
}

let radarPic = Picture("!ui/gameuiskin#radar_stby_icon")
let isBScope = Computed(@() AzimuthRange.value > PI)
let needRadarCollapsedIcon = Computed(@() IsRadarHudVisible.value && !IsRadarVisible.value && !IsRadar2Visible.value &&
 CollapsedIcon.value && (IsCScopeVisible.value || IsBScopeVisible.value))
let function Root() {
  let colorWacthed = Watched(greenColor)
  let colorAlertWatched = Watched(redColor)
  let radarColor = Watched(Color(0, 255, 0, 255))
  return {
    halign = ALIGN_LEFT
    valign = ALIGN_TOP
    watch = [IndicatorsVisible, isBScope]
    size = [sw(100), sh(100)]
    children = [
      mkRadar(radarPosComputed)
      @(){
        watch = needRadarCollapsedIcon
        children = needRadarCollapsedIcon.value ? {
            pos = radarPosComputed.value
            size = [sh(5), sh(5)]
            rendObj = ROBJ_IMAGE
            image = radarPic
            color = radarColor.value
          } : null
      }
      aamAim(colorWacthed, colorAlertWatched)
      agmAim(colorWacthed)
      tankDmgIndicator
      actionBarTopPanel
      //


      radarHud(isBScope.value ? sh(40) : sh(32), isBScope.value ? sh(40) : sh(32), radarPosComputed.value[0], radarPosComputed.value[1], radarColor)
      IndicatorsVisible.value
        ? @() {
            children = [
              sightIndicators(styleAamAim, colorWacthed)
              lockSight(colorWacthed, hdpx(150), hdpx(100), sw(50), sh(50))
              targetSize(colorWacthed, sw(100), sh(100), false)
            ]
          }
        : null
    ]
  }
}

return Root