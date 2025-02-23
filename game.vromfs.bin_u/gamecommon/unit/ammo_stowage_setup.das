require ecs
require dm
require app
require net
require Unit
require Weapon
require AmmoStowage
require DagorSystem
require WTDamageModel
require %game.utils.component_bundle_macro
require %game.utils.utils_common
require %game.unit.ammo_stowage_events
require %game.unit.ammo_stowage_common


// subtract stage:
// - receives total number of ammo in gun as num_ammos parameter
// - subtracts all ammo, already contained in this cluster from num_ammos parameter
// - if ammo count in slots is larger than num_ammos, subtracts excess ammo from last slots in cluster
// after iterating all clusters, num_ammos will contain excess ammo, that needs to be inserted,
// so it needs to be passed to the next stage
[with_bundle(v)]
def setup_cluster_subtract(var unit : Unit?; cluster_id : int; var num_ammos : int&;
                           v : tuple<
                             ammo_clusters__state : UInt32List- const;
                             ammo_clusters__slotsRange : IPoint2List;
                             ammo_slots__state : UInt32List- const;
                             ammo_slots__partId : PartIdList;
                             ammo_slots__numAmmo : IPoint2List- const
                           >) : bool
  var is_changed = false
  set_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState EMPTY, num_ammos <= 0)
  let cluster_state = v.ammo_clusters__state[cluster_id]
  let reverse_fill = get_flag(cluster_state, AmmoClusterState REVERSE_FILL)
  let slots_range = v.ammo_clusters__slotsRange[cluster_id]
  var i = reverse_fill ? slots_range.y - 1 : slots_range.x
  for _ in slots_range.x..slots_range.y
    let slot_id = reverse_fill ? i-- : i++
    let slot_part_id = v.ammo_slots__partId[slot_id]

    // if slot is not enabled, no ammo is stored in it, enforce this
    if !get_flag(v.ammo_slots__state[slot_id], AmmoSlotState ENABLED)
      v.ammo_slots__numAmmo[slot_id].x = 0

    // subtract ammo from slot, if it is not enough and subtract ammo in slot, from num_ammos
    v.ammo_slots__numAmmo[slot_id].x = min(v.ammo_slots__numAmmo[slot_id].x, num_ammos)
    num_ammos -= v.ammo_slots__numAmmo[slot_id].x

    // disable dm part if slot is empty
    let is_enabled = v.ammo_slots__numAmmo[slot_id].x > 0
    if *unit.visual |> dm_is_part_enabled(slot_part_id) != is_enabled
      *unit.visual |> dm_set_part_enabled(slot_part_id, is_enabled)
      *unit.visual |> dm_set_decor_by_part_id(int(slot_part_id.globalId), is_enabled)
      is_changed = true
  return is_changed

// insert stage:
// - receives excess ammo left from subtract stage
// - inserts it in free slots and subtracts from num_ammos
[with_bundle(v)]
def setup_cluster_insert(var unit : Unit?; cluster_id : int; var num_ammos : int&;
                         v : tuple<
                           ammo_clusters__state : UInt32List- const;
                           ammo_clusters__slotsRange : IPoint2List;
                           ammo_slots__state : UInt32List- const;
                           ammo_slots__partId : PartIdList;
                           ammo_slots__numAmmo : IPoint2List- const
                         >) : bool
  var is_changed = false
  let cluster_state = v.ammo_clusters__state[cluster_id]
  let reverse_fill = get_flag(cluster_state, AmmoClusterState REVERSE_FILL)
  let slots_range = v.ammo_clusters__slotsRange[cluster_id]
  var i = reverse_fill ? slots_range.y - 1 : slots_range.x

  for _ in slots_range.x..slots_range.y
    let slot_id = reverse_fill ? i-- : i++
    let slot_available = get_flag(v.ammo_slots__state[slot_id], AmmoSlotState ENABLED) || get_flag(cluster_state, AmmoClusterState RESTORE_AFTER_DEAD)
    let slot_part_id = v.ammo_slots__partId[slot_id]

    // try filling available slots
    if slot_available && num_ammos > 0
      // restore slot
      set_flag(v.ammo_slots__state[slot_id], AmmoSlotState ENABLED, true)
      if v.ammo_slots__numAmmo[slot_id].x == 0
        *unit.visual |> dm_set_rel_hp(int(slot_part_id.globalId), 1.0f, false)
      // increase ammo in slot
      let count_before = v.ammo_slots__numAmmo[slot_id].x
      v.ammo_slots__numAmmo[slot_id].x = min(num_ammos, v.ammo_slots__numAmmo[slot_id].y)
      num_ammos -= v.ammo_slots__numAmmo[slot_id].x - count_before

    // enable dm parts, if they are disabled
    let is_enabled = v.ammo_slots__numAmmo[slot_id].x > 0
    if *unit.visual |> dm_is_part_enabled(slot_part_id) != is_enabled
      *unit.visual |> dm_set_part_enabled(slot_part_id, is_enabled)
      *unit.visual |> dm_set_decor_by_part_id(int(slot_part_id.globalId), is_enabled)
      is_changed = true

    if num_ammos == 0
      // other slots were already disabled
      break

  return is_changed


enum SetupClusterStage
  SUBTRACT
  INSERT

[with_bundle(v)]
def setup_cluster_stage(stage : SetupClusterStage; var unit : Unit?; cluster_id : int; var num_ammos : int&;
                        v : tuple<
                          ammo_clusters__state : UInt32List- const;
                          ammo_clusters__slotsRange : IPoint2List;
                          ammo_slots__state : UInt32List- const;
                          ammo_slots__partId : PartIdList;
                          ammo_slots__numAmmo : IPoint2List- const
                        >) : bool
  if stage == SetupClusterStage INSERT
    if num_ammos == 0
      return false
    return setup_cluster_insert(unit, cluster_id, num_ammos, v);
  elif stage == SetupClusterStage SUBTRACT
    return setup_cluster_subtract(unit, cluster_id, num_ammos, v);
  return false


[with_bundle(v)]
def iter_clusters_in_order(stowage_id : int;
                           v : tuple<
                             ammo_stowages__clustersRange : IPoint2List;
                             ammo_clusters__state : UInt32List
                           >; b : block<(cluster_id : int) : void>) : void
  let clusters_range = v.ammo_stowages__clustersRange[stowage_id]
  var i = clusters_range.y - 1
  // ammo loaded in gun clusters
  for _ in clusters_range.x..clusters_range.y
    let cluster_id = i--
    if get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AMMO_LOADED_IN_GUN)
      b |> invoke(cluster_id)
  i = clusters_range.y - 1
  // first stage and auto load clusters
  for _ in clusters_range.x..clusters_range.y
    let cluster_id = i--
    if get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AMMO_LOADED_IN_GUN)
      continue
    if get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState FIRST_STAGE) || get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AUTO_LOAD)
      b |> invoke(cluster_id)
  i = clusters_range.y - 1
  // other clusters
  for _ in clusters_range.x..clusters_range.y
    let cluster_id = i--
    if get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AMMO_LOADED_IN_GUN)
      continue
    if !get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState FIRST_STAGE) && !get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AUTO_LOAD)
      b |> invoke(cluster_id)


[with_bundle(v)]
def public setup_ammo_stowage(var unit : Unit?; init_num : bool; is_refill : bool;
                              v : tuple<
                                ammo_stowage__ammoLost : int-const;

                                ammo_stowages__state : UInt32List- const;
                                ammo_stowages__numAmmo : IPoint3List- const;
                                ammo_stowages__numAmmoFirstStage : IPoint3List- const;
                                ammo_stowages__clustersRange : IPoint2List;
                                ammo_stowages__weaponTriggersRange : IPoint2List;
                                ammo_stowage__weaponTriggers : IntList;

                                ammo_clusters__type : IntList;
                                ammo_clusters__state : UInt32List- const;
                                ammo_clusters__slotsRange : IPoint2List;
                                ammo_slots__state : UInt32List- const;
                                ammo_slots__partId : PartIdList;
                                ammo_slots__numAmmo : IPoint2List- const
                              >) : bool
  // this can be an ammo stowage flag instead
  let can_load_to_breech = !get_app().isInHangar

  let eid = unit.eid
  let weapon_controller = unit.weap
  var is_dm_changed = false
  var is_sync_required = false
  for stowage_id, state, stowage_num_ammo, stowage_num_ammo_first_stage, triggers_range in iter_range(v.ammo_stowages__state), v.ammo_stowages__state, v.ammo_stowages__numAmmo, v.ammo_stowages__numAmmoFirstStage, v.ammo_stowages__weaponTriggersRange
    var num_ammo = 0
    var num_ammo_loaded = 0
    var max_ammo_loaded = 0
    for i in triggers_range.x..triggers_range.y
      for weapon in weapon_controller.Weapons |> get_weapons_by_trigger(v.ammo_stowage__weaponTriggers[i])
        if weapon == null
          continue
        let gun = weapon |> as_gun()
        if gun != null
          var count = 0
          for bullet_set in gun.properties.bulletSets
            if bullet_set.bulletsCount > 0
              count += bullet_set.bulletsCount
          let bullets_cartidge = gun.currentBulletSet.bulletsCartridge
          if count > 0
            num_ammo_loaded += gun.currentLoadedAmmoCount
            max_ammo_loaded += bullets_cartidge
            num_ammo += count;
        else
          let count = weapon.countBullets
          if count > 0
            num_ammo += count
            // TODO: handle base gun
            num_ammo_loaded += 1
            max_ammo_loaded += 1

    if get_flag(state, AmmoStowageState REMOVE_LOADED_AMMO) && can_load_to_breech
      num_ammo -= num_ammo_loaded

    if is_refill || num_ammo > stowage_num_ammo.x
      iter_clusters_in_order(stowage_id, v) <| $(cluster_id : int)
        let slots_range = v.ammo_clusters__slotsRange[cluster_id]
        for slot_id in slots_range.x..slots_range.y
          if !get_flag(v.ammo_slots__state[slot_id], AmmoSlotState ENABLED)
            v.ammo_stowage__ammoLost = 0
            set_flag(v.ammo_slots__state[slot_id], AmmoSlotState ENABLED, true)
            *unit.visual |> dm_set_rel_hp(int(v.ammo_slots__partId[slot_id].globalId), 1.0f, false)

      if stowage_num_ammo_first_stage.z > 0
        if is_refill
          stowage_num_ammo_first_stage.x = max(0, min(num_ammo, stowage_num_ammo_first_stage.z))
        else
          stowage_num_ammo_first_stage.x = max(0, min(stowage_num_ammo_first_stage.x + num_ammo - stowage_num_ammo.x,  stowage_num_ammo_first_stage.z))
        is_sync_required = true

    if stowage_num_ammo_first_stage.z > 0 && num_ammo < stowage_num_ammo.x
      stowage_num_ammo_first_stage.x = max(0, stowage_num_ammo_first_stage.x + num_ammo - stowage_num_ammo.x)
      is_sync_required = true

    stowage_num_ammo.x = num_ammo
    if init_num
      stowage_num_ammo.y = num_ammo
      stowage_num_ammo_first_stage.y = stowage_num_ammo_first_stage.x
    elif is_refill
      stowage_num_ammo.y = max(stowage_num_ammo.x, stowage_num_ammo.y)
      stowage_num_ammo_first_stage.y = max(stowage_num_ammo_first_stage.x, stowage_num_ammo_first_stage.y)

    // das does not allow use this as array size directly, because this is not technically a constant, so we hardcode it and guard with assert
    assert(int(AmmoClusterType NUM_TYPES) == 2)
    var num_ammos : int[2]
    var num_ammos_first_stage : int[2]
    var num_ammos_loaded : int[2]
    for i in 0..int(AmmoClusterType NUM_TYPES)
      num_ammos_first_stage[i] = stowage_num_ammo_first_stage.x
      num_ammos[i] = num_ammo - stowage_num_ammo_first_stage.x
      num_ammos_loaded[i] = num_ammo_loaded

    for stage in each_enum(SetupClusterStage SUBTRACT)
      iter_clusters_in_order(stowage_id, v) <| $(cluster_id : int)
        let is_first_stage = (get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState FIRST_STAGE) ||
                              get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AUTO_LOAD))
        let is_loaded_ammo = get_flag(v.ammo_clusters__state[cluster_id], AmmoClusterState AMMO_LOADED_IN_GUN)
        let cluster_type = v.ammo_clusters__type[cluster_id]
        is_dm_changed = setup_cluster_stage(stage, unit, cluster_id,
                                      is_loaded_ammo ?
                                        num_ammos_loaded[cluster_type] :
                                      is_first_stage ?
                                        num_ammos_first_stage[cluster_type] :
                                        num_ammos[cluster_type], v) || is_dm_changed

  if is_dm_changed
    sendEvent(eid, [[EventAmmoStowageInvalidateRenderer]])
  return is_sync_required


[es, with_bundle(v)]
def ammo_stowage_setup_stowage_es(evt : EventAmmoStowageSetup; active : bool; eid : EntityId; uid : int;
                                  v : tuple<
                                    ammo_stowage__ammoLost : int-const;
                                    ammo_stowages__state : UInt32List- const;
                                    ammo_stowages__replenishmentStartEnd : Point2List;
                                    ammo_stowages__numAmmo : IPoint3List- const;
                                    ammo_stowages__numAmmoFirstStage : IPoint3List- const;
                                    ammo_stowages__clustersRange : IPoint2List;
                                    ammo_stowages__weaponTriggersRange : IPoint2List;
                                    ammo_stowage__weaponTriggers : IntList;
                                    ammo_clusters__type : IntList;
                                    ammo_clusters__state : UInt32List- const;
                                    ammo_clusters__slotsRange : IPoint2List;
                                    ammo_slots__state : UInt32List- const;
                                    ammo_slots__partId : PartIdList;
                                    ammo_slots__numAmmo : IPoint2List- const
                                  >)
  if !active
    return
  var unit = get_unit(uid)
  if unit != null && !unit.isDelayed
    let sync_required = setup_ammo_stowage(unit,
      evt.initNum,
      evt.isRefill) <| v
    if evt.netSyncIfRequired && sync_required
      ammo_stowage_send_net_sync(eid) <| v


[es, with_bundle(v)]
def ammo_stowage_bullets_amount_changed_es(evt : EventBulletsAmountChanged; active : bool; eid : EntityId; uid : int;
                                           v : tuple<
                                             ammo_stowage__ammoLost : int-const;
                                             ammo_stowages__state : UInt32List- const;
                                             ammo_stowages__replenishmentStartEnd : Point2List;
                                             ammo_stowages__numAmmo : IPoint3List- const;
                                             ammo_stowages__numAmmoFirstStage : IPoint3List- const;
                                             ammo_stowages__clustersRange : IPoint2List;
                                             ammo_stowages__weaponTriggersRange : IPoint2List;
                                             ammo_stowage__weaponTriggers : IntList;
                                             ammo_clusters__type : IntList;
                                             ammo_clusters__state : UInt32List- const;
                                             ammo_clusters__slotsRange : IPoint2List;
                                             ammo_slots__state : UInt32List- const;
                                             ammo_slots__partId : PartIdList;
                                             ammo_slots__numAmmo : IPoint2List- const
                                           >)
  if !active
    return
  var unit = get_unit(uid)
  if unit != null && !unit.isDelayed
    let sync_required = setup_ammo_stowage(unit, false, evt.isRefill) <| v
    if sync_required
      ammo_stowage_send_net_sync(eid) <| v


[es, with_bundle(v)]
def ammo_stowage_apply_slot_effect_es(evt : EventAmmoStowageApplySlotEffect;
                                      uid : int;
                                      v : tuple<
                                        ammo_stowage__partIdRemap : IPoint4List;
                                        ammo_stowage__weaponTriggers : IntList;
                                        ammo_stowage__ammoLost : int-const;
                                        ammo_stowages__state : UInt32List- const;
                                        ammo_stowages__numAmmo : IPoint3List- const;
                                        ammo_stowages__numAmmoFirstStage : IPoint3List- const;
                                        ammo_stowages__clustersRange : IPoint2List;
                                        ammo_stowages__weaponTriggersRange : IPoint2List;
                                        ammo_clusters__type : IntList;
                                        ammo_clusters__state : UInt32List- const;
                                        ammo_clusters__slotsRange : IPoint2List;
                                        ammo_slots__state : UInt32List- const;
                                        ammo_slots__numAmmo : IPoint2List- const;
                                        ammo_slots__partId : PartIdList
                                      >)
  var unit = get_unit(uid)
  if unit != null && !unit.isDelayed
    apply_slot_effect_by_part_id(unit, evt.partId, evt.effect) <| v
    setup_ammo_stowage(unit, false, false) <| v

[es]
def ammo_stowage_force_reload_gun_es(evt : EventAmmoStowageForceReloadGun; uid : int)
  var unit = get_unit(uid)
  if unit == null || unit.isDelayed
    return
  for weapon in unit.weap.Weapons |> get_weapons_by_trigger(evt.triggerId)
    var gun = weapon |> as_gun()
    if gun == null
      continue
    start_reloading_gun(*gun)


[with_bundle(v)]
def ammo_stowage_send_net_sync(eid : EntityId; v : tuple<
                                 ammo_stowages__replenishmentStartEnd : Point2List;
                                 ammo_stowages__numAmmo : IPoint3List;
                                 ammo_stowages__numAmmoFirstStage : IPoint3List
                               >) : void
  if !is_server()
    return
  let current_time = float(get_app().usefulTotalTime)

  using() <| $(var data : IntList)
    data |> reserve(4)
    for replenishment_start_end, num_ammo, num_ammo_first_stage in v.ammo_stowages__replenishmentStartEnd, v.ammo_stowages__numAmmo, v.ammo_stowages__numAmmoFirstStage
      let packed_remaining_time = replenishment_start_end.x > 0.0f ? int((replenishment_start_end.y - current_time) * 1000.0f) : -1
      data |> push(num_ammo.x)
      data |> push(num_ammo_first_stage.x)
      data |> push(packed_remaining_time)
    send_net_event(eid, [[EventAmmoStowageNetSync data=ecs_addr(data)]])


[es(tag=netClient), with_bundle(v)]
def ammo_stowage_net_sync_es(evt : EventAmmoStowageNetSync;
                             eid : EntityId;
                             var v : tuple<
                               ammo_stowages__replenishmentStartEnd : Point2List;
                               ammo_stowages__numAmmo : IPoint3List;
                               ammo_stowages__numAmmoFirstStage : IPoint3List
                             >) : void
  let current_time = float(get_app().usefulTotalTime)
  let updates_stowage_count = min(length(v.ammo_stowages__numAmmo), length(*evt.data) / 3)
  assume data = *evt.data;
  for stowage_id in 0..updates_stowage_count
    v.ammo_stowages__numAmmo[stowage_id].x = data[stowage_id * 3 + 0]
    v.ammo_stowages__numAmmoFirstStage[stowage_id].x = data[stowage_id * 3 + 1]
    let packed_remaining_time = data[stowage_id * 3 + 2]
    if packed_remaining_time > 0
      v.ammo_stowages__replenishmentStartEnd[stowage_id].y = current_time + float(packed_remaining_time) / 1000.0f
      if v.ammo_stowages__replenishmentStartEnd[stowage_id].x < 0.0f
        v.ammo_stowages__replenishmentStartEnd[stowage_id].x = current_time
    else
      v.ammo_stowages__replenishmentStartEnd[stowage_id] = float2(-1.0f)
  sendEvent(eid, [[EventBulletsAmountChanged isRefill=false]])


[es]
def ammo_stowage_gun_net_sync_es(act : UpdateStageInfoAct;
                                 uid : int;
                                 var ammo_stowages__state : UInt32List&;
                                 ammo_stowages__weaponTriggersRange : IPoint2List;
                                 ammo_stowage__weaponTriggers : IntList)
  for stowage_id, state in iter_range(ammo_stowages__state), ammo_stowages__state
    if get_flag(state, AmmoStowageState NEED_SYNC_BULLET_COUNT)
      set_flag(state, AmmoStowageState NEED_SYNC_BULLET_COUNT, false)

      let unit = get_unit(uid)
      if unit == null || unit.isDelayed
        return

      let triggers_range = ammo_stowages__weaponTriggersRange[stowage_id]
      for trigger_id_idx in triggers_range.x..triggers_range.y
        let trigger_id = ammo_stowage__weaponTriggers[trigger_id_idx]
        for weapon in unit.weap.Weapons |> get_weapons_by_trigger(trigger_id)
          let gun = weapon |> as_gun()
          if gun == null
            continue
          send_bullet_rearm_event(*gun, false)

