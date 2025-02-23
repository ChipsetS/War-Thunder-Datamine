from "%scripts/dagui_natives.nut" import get_usefull_total_time
from "%scripts/dagui_library.nut" import *

let { getWeaponDescTextByTriggerGroup, getDefaultBulletName } = require("%scripts/weaponry/weaponryDescription.nut")
let { getBulletSetNameByBulletName } = require("%scripts/weaponry/bulletsInfo.nut")
let { EII_BULLET, EII_ROCKET, EII_SMOKE_GRENADE, EII_FORCED_GUN, EII_SELECT_SPECIAL_WEAPON } = require("hudActionBarConst")
let { get_mission_difficulty_int } = require("guiMission")

local cachedUnitId = ""
let cache = {}

let LONG_ACTIONBAR_TEXT_LEN = 6;

let cacheActionDescs = function(unitId) {
  let unit = getAircraftByName(unitId)
  let ediff = get_mission_difficulty_int()
  cachedUnitId = unitId
  cache.clear()
  if (unit == null ||
      (unit.esUnitType != ES_UNIT_TYPE_SHIP && unit.esUnitType != ES_UNIT_TYPE_BOAT))
    return

  foreach (triggerGroup in [ "torpedoes", "bombs", "rockets", "mines" ])
    cache[triggerGroup] <- getWeaponDescTextByTriggerGroup(triggerGroup, unit, ediff)
}

let getActionDesc = function(unitId, triggerGroup) {
  if (unitId != cachedUnitId)
    cacheActionDescs(unitId)
  return cache?[triggerGroup] ?? ""
}

let function getActionItemAmountText(modData, isFull = false) {
  let count = modData?.count ?? 0
  if (count < 0)
    return ""

  local text = ""
  if (modData.type == EII_SMOKE_GRENADE && "salvo" in modData)
    text = $"{modData.salvo}/{modData.count}"
  else {
    let countEx = modData?.countEx ?? 0
    let countStr = count.tostring()
    local countExText = modData?.isStreakEx ? loc("icon/nuclear_bomb") : (countEx < 0 ? "" : countEx.tostring())
    if (countExText.len() > 0 && countExText.len() > (LONG_ACTIONBAR_TEXT_LEN - countStr.len()))
      countExText = loc("weapon/bigAmountNumberIcon")
    text = countExText.len() > 0 ? $"{countStr}/{countExText}" : countStr
  }

  return isFull ? $"{loc("options/count")}{loc("ui/colon")}{text}" : text
}

let function getActionItemModificationName(item, unit) {
  if (!unit)
    return null
  let itemType = item.type
  if (itemType == EII_ROCKET )
    return getBulletSetNameByBulletName(unit, item?.bulletName)
  if (itemType == EII_SELECT_SPECIAL_WEAPON)
    return getBulletSetNameByBulletName(unit, item?.bulletName)
  if (itemType == EII_BULLET || itemType == EII_FORCED_GUN)
    return (item?.modificationName ?? "") != ""
      ? item.modificationName
      : getDefaultBulletName(unit)
  return null
}

let function getActionItemStatus(item) {
  let { count = 0, available = true, cooldownEndTime = 0 } = item
  let isAvailable = available && count != 0
  return {
    isAvailable
    isReady = isAvailable && cooldownEndTime <= get_usefull_total_time()
  }
}

return {
  cacheActionDescs
  getActionDesc
  LONG_ACTIONBAR_TEXT_LEN
  getActionItemAmountText
  getActionItemModificationName
  getActionItemStatus
}
