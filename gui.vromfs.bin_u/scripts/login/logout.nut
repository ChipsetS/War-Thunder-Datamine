from "%scripts/dagui_natives.nut" import disable_network, sign_out, exit_game
from "%scripts/dagui_library.nut" import *

let { set_disable_autorelogin_once } = require("loginState.nut")
let { broadcastEvent } = require("%sqStdLibs/helpers/subscriptions.nut")
let { handlersManager } = require("%sqDagui/framework/baseGuiHandlerManager.nut")
let { isInFlight } = require("gameplayBinding")
let { isXbox } = require("%sqstd/platform.nut")

let needLogoutAfterSession = mkWatched(persist, "needLogoutAfterSession", false)


local platformLogout = null
if (isXbox) {
  platformLogout = require("%scripts/xbox/loginState.nut").logout
}


let function canLogout() {
  return !disable_network()
}


let function doLogout() {
  if (!canLogout())
    return exit_game()

  if (::is_multiplayer()) { //we cant logout from session instantly, so need to return "to debriefing"
    if (isInFlight()) {
      needLogoutAfterSession(true)
      ::quit_mission()
      return
    }
    else
      ::destroy_session_scripted("on start logout")
  }

  if (::should_disable_menu() || ::g_login.isProfileReceived())
    broadcastEvent("BeforeProfileInvalidation") // Here save any data into profile.

  log("Start Logout")
  set_disable_autorelogin_once(true)
  needLogoutAfterSession(false)
  ::g_login.reset()
  ::on_sign_out()
  sign_out()
  handlersManager.startSceneFullReload({ globalFunctionName = "gui_start_startscreen" })
}


let function startLogout() {
  if (platformLogout != null)
    platformLogout(function() {
      doLogout()
    })
  else
    doLogout()
}


return {
  canLogout = canLogout
  startLogout = startLogout
  needLogoutAfterSession = needLogoutAfterSession
}