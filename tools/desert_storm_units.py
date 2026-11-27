"""Port explicit Desert Storm catalog overrides for FightParty's existing roster.
Reads XML as data only; never executes supplied Galaxy/Python. Missing native/mod
fields are preserved and recorded, never inferred from UI Level/MinScanRange.
Run: python tools/desert_storm_units.py --apply
"""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT/'reference/desert-storm/Base.SC2Data/GameData'
# These packs have editable FightParty group prices. Map resources are per unit.
PROJECT_PACKS = {'rifle', 'hellbat', 'hellbat_mech', 'zergling', 'roach', 'hydralisk'}
PACK_COUNT_SOURCE = 'FightParty 试玩平衡：每组数量由兵种配置指定'
PACK_BALANCE_SOURCE = 'FightParty 试玩平衡：保留兵种配置中的数值；原图参考 '
UNIT_IDS = {
 'rifle':'Marine', 'hellbat':'Hellion', 'hellbat_mech':'Hellbat', 'marauder':'Marauder', 'medic':'Medic',
 'agent':'Ghost', 'widow_mine':'WidowMine', 'mortar':'SiegeTank', 'viking':'VikingFighter', 'viking_assault':'VikingAssault',
 'liberator':'Liberator', 'thor':'Thor', 'battlecruiser':'Battlecruiser',
 'zergling':'Zergling','baneling':'Baneling','roach':'Roach','hydralisk':'Hydralisk',
 'ravager':'Ravager','piercer':'LurkerMP','tunneler':'SwarmHostMP','mutalisk':'Mutalisk',
 'infestor':'Infestor','ultralisk':'Ultralisk','brood_lord':'BroodLord',
 'vanguard':'Zealot','adept':'Adept','stalker':'Stalker','sentry':'Sentry','immortal':'Immortal',
 'high_templar':'HighTemplar','archon':'Archon','colossus':'Colossus','disruptor':'Disruptor',
 'void_ray':'VoidRay','carrier':'Carrier','broodling':'Broodling','locust':'LocustMP','interceptor':'Interceptor',
}
# Explicit correspondence to standard weapon/effect IDs. Native default links are
# not reconstructed: the audit states when the local UnitData omits that link.
MODES = {
 'rifle': [('gauss_rifle','GuassRifle','GuassRifle')],
 'hellbat':[('flame_jet','InfernalFlameThrower','InfernalFlameThrower')],
 'hellbat_mech':[('napalm_spray','HellionTank','HellionTankDamage')],
 'marauder':[('concussive_grenade','PunisherGrenades','PunisherGrenadesU')],
 'agent':[('armor_piercing','C10CanisterRifleFake','C10CanisterRifle')],
 'mortar':[('mobile_cannon','90mmCannons','90mmCannons'),('siege_cannon','CrucioShockCannon','CrucioShockCannonDirected')],
 'viking':[('anti_air_missile','LanzerTorpedoes','LanzerTorpedoesU')],
 'viking_assault':[('gatling_cannon','TwinGatlingCannon','TwinGatlingCannons')],
 'liberator':[('anti_air_burst','LiberatorMissileLaunchers','LiberatorMissileDamage'),('defender_cannon','LiberatorAGWeapon','LiberatorAGDamage')],
 'thor':[('hammer','ThorsHammer','ThorsHammerDamage'),('javelin','JavelinMissileLaunchers','JavelinMissileLaunchersDamage')],
 'battlecruiser':[('ats_laser','ATSLaserBattery','ATSLaserBatteryU'),('ata_laser','ATALaserBattery','ATALaserBatteryU')],
 'zergling':[('claw_strike','PrimalZergling','PrimalZergling')],
 'baneling':[('volatile_burst',None,'VolatileBurstU')],
 'roach':[('acid_spit','AcidSaliva','AcidSalivaU')],
 'hydralisk':[('needle_spines','NeedleSpines','NeedleSpinesDamage')],
 'ravager':[('plasma_spit','RavagerWeapon','RavagerWeaponDamage')],
 'piercer':[('lurker_spines','Lurker','LurkerMPDamage')],
 'mutalisk':[('glaive_wurm','MutaliskGlaiveWurm','MutaliskGlaiveWurmDamage')],
 'ultralisk':[('kaiser_blades','KaiserBlades2','KaiserBladesDamage')],
 'brood_lord':[('broodling_strike','BroodLord','BroodlingEscortDamage')],
 'vanguard':[('psi_blades','Weapon_LNLR','Effect_SH_LNLR')],
 'adept':[('resonating_glaive','Adept','AdeptDamage')],
 'stalker':[('particle_disruptor','ParticleDisruptors','ParticleDisruptorsU')],
 'sentry':[('disruption_beam','DisruptionBeam','DisruptionBeamDamage')],
 'immortal':[('phase_disruptor','PhaseDisruptors','PhaseDisruptors')],
 'archon':[('psionic_shockwave','PsionicShockwave','PsionicShockwaveDamage')],
 'colossus':[('thermal_lances','ThermalLances','ThermalLancesMU')],
 'void_ray':[('prismatic_beam','VoidRaySwarm','VoidRaySwarmDamage')],
 'locust':[('locust_spit','LocustMP','LocustMPDamage')],
 'interceptor':[('pulse_cannons','InterceptorBeam','InterceptorBeamDamage')],
}
ATTRS = {'Light':'light','Armored':'heavy','Biological':'biological','Mechanical':'mechanical',
         'Massive':'massive','Psionic':'psionic','Structure':'structure','Detector':'detector','Summoned':'summoned'}
SCALARS = {'LifeMax':'hp','LifeArmor':'armor','ShieldsMax':'shield','ShieldArmor':'shield_armor',
           'EnergyMax':'energy','EnergyStart':'initial_energy','Speed':'speed',
           'LifeRegenRate':'health_regen','LifeRegenDelay':'health_regen_delay',
           'ShieldRegenRate':'shield_regen','ShieldRegenDelay':'shield_regen_delay',
           'EnergyRegenRate':'energy_regen','EnergyRegenDelay':'energy_regen_delay','Radius':'collision_radius'}

class Catalog:
 def __init__(self):
  self.tables = {name:{n.attrib['id']:n for n in ET.parse(REFERENCE/(name+'.xml')).getroot() if 'id' in n.attrib}
                 for name in ('UnitData','WeaponData','EffectData','AbilData','BehaviorData','ValidatorData')}
 def node(self, table, uid): return self.tables[table].get(uid)
 def children(self, table, uid, field, seen=()):
  if not uid or uid in seen:return []
  node=self.node(table,uid)
  if node is None:return []
  found=node.findall(field)
  return found if found else self.children(table,node.get('parent'),field,seen+(uid,))
 def scalar(self, table, uid, field, index=None):
  entries=self.children(table,uid,field)
  if index is not None:entries=[e for e in entries if e.get('index')==index]
  for node in reversed(entries):
   if node.get('removed')=='1':return None
   if 'value' in node.attrib:
    try:return float(node.get('value'))
    except ValueError:return node.get('value')
  return None

def set_path(node, path, value):
 parts=path.split('/')
 for part in parts[:-1]:node=node[int(part)] if isinstance(node,list) else node[part]
 if isinstance(node,list):node[int(parts[-1])]=value
 else:node[parts[-1]]=value

def apply_infantry_stimulants(cat, units, write):
 # The two ordinary infantry augments both apply Stimpack. Commander variants use other effects.
 for uid, ability in [('rifle','DSStimpack'), ('marauder','DSStimpackMarauder')]:
  units[uid].setdefault('skills', {}).setdefault('stimulant', {})
  prefix = 'skills/stimulant/'
  cost_source = 'AbilData/' + ability + '/Cost'
  behavior_source = 'AbilData/' + ability + '/Effect=Stimpack → Liberty BehaviorData/Stimpack/'
  write(uid, prefix+'health_cost', cat.scalar('AbilData', ability, 'Cost/Vital', 'Life'), cost_source+'/Vital[Life]')
  write(uid, prefix+'health_cost_ratio', 0, cost_source+'/Vital[Life] 为固定生命消耗')
  cooldown = cat.children('AbilData', ability, 'Cost/Cooldown')[0]
  write(uid, prefix+'cooldown', float(cooldown.get('TimeUse')), cost_source+'/Cooldown@TimeUse')
  write(uid, prefix+'duration', 15, behavior_source+'Duration')
  write(uid, prefix+'attack_multiplier', 1.5, behavior_source+'Modification@AttackSpeedMultiplier')
  write(uid, prefix+'speed_multiplier', 1.5, behavior_source+'Modification@MoveSpeedMultiplier')
  write(uid, prefix+'min_health_cost_multiplier', 2, 'FightParty 施放条件：当前生命须严格高于本次生命消耗的两倍')
  write(uid, prefix+'display_name', '兴奋剂', 'FightParty 技能显示名称')

def apply_viking_assault(cat, write):
 """Ordinary ground Viking from the patrol port; apply the built-in Phobos range upgrade."""
 uid = 'viking_assault'
 prefix = 'attack_modes/0/'
 write(uid,'spawn_count',cat.scalar('UnitData','InfestedDominionHousing1','EnergyMax'),
       '普通巡逻空港 UnitData/InfestedDominionHousing1/EnergyMax；GameStrings/DSVikingAssault：每组3台')
 write(uid,'armor_type','heavy','Liberty UnitData/VikingAssault/Attributes[Armored]')
 write(uid,'tags',['mechanical'],'Liberty UnitData/VikingAssault/Attributes[Mechanical]；GameStrings/DSVikingAssault')
 write(uid,'speed',2.25,'Liberty UnitData/VikingAssault/Speed')
 write(uid,'size',[1.5,1.5],'Liberty UnitData/VikingAssault/Radius=0.75；项目按直径表示模型大小')
 write(uid,'collision_radius',0.75,'Liberty UnitData/VikingAssault/SeparationRadius')
 write(uid,'energy',0,'VikingAssault 无能量池；巡逻空港的 EnergyMax 用来记录编组人数')
 write(uid,prefix+'range',7,'Liberty WeaponData/TwinGatlingCannon/Range=6；MapScript:21136 启用 AresClassWeaponsSystemViking，Liberty Campaign UpgradeData 使对地射程+1')
 write(uid,prefix+'target_layers',['ground'],'Liberty WeaponData/TwinGatlingCannon/TargetFilters[Ground]')
 write(uid,prefix+'hit_count',1,'Liberty WeaponData/TwinGatlingCannon 直接引用单一 Damage 效果 TwinGatlingCannons')
 write(uid,prefix+'attack_duration',0.167,'Core WeaponData/CWeapon/DamagePoint=0.167，单发出手后结算')
 write(uid,prefix+'backswing',0.5,'Core WeaponData/CWeapon/Backswing')
 write(uid,prefix+'delivery',{'type':'projectile','flight':'fixed','seconds':0,'tracking':True},
       'Liberty WeaponData/TwinGatlingCannon/Effect 直接引用 EffectData/TwinGatlingCannons，无飞行弹体')

def apply_medivac(cat, write):
 """The deployed Medivac inherits Liberty campaign effects. Convert its game seconds to Faster real seconds."""
 uid = 'medivac'
 ability = 'MedivacDoubleBeamHeal'
 prefix = 'skills/medivac_healing/'
 weapon = 'attack_modes/0/'
 faster = 1.4
 pulse = round(0.111 / faster, 10)
 clock = '（Faster：游戏秒÷1.4）'
 period_source = 'Liberty Campaign/EffectData/MedivacHealTargetPersistent/PeriodicPeriodArray=0.111' + clock
 write(uid, 'energy_regen', round(cat.scalar('UnitData','Medivac','EnergyRegenRate') * faster, 6),
       'UnitData/Medivac/EnergyRegenRate=1.125，Faster 实时每秒×1.4')
 write(uid, weapon+'range', 4, 'Liberty Campaign/AbilData/MedivacDoubleBeamHeal/Range；ValidatorData/HealTargetInRange')
 write(uid, weapon+'healing', 1, 'Liberty Campaign/EffectData/MedivacHealModifyTargetLife/VitalArray[Life]')
 write(uid, weapon+'attack_duration', pulse, period_source)
 write(uid, weapon+'delivery/tick_interval', pulse, period_source)
 write(uid, weapon+'delivery/switch_delay', 0, 'Liberty Campaign/EffectData/MedivacHealInitialSet：直接开始目标持续效果')
 write(uid, prefix+'max_targets', 2, 'Liberty Campaign/ValidatorData/HealBeamAvailable：MedivacHealBeamBusy < 2')
 write(uid, prefix+'acquire_range', cat.scalar('AbilData',ability,'AutoCastRange'), 'AbilData/MedivacDoubleBeamHeal/AutoCastRange')
 write(uid, prefix+'secondary_range', 4.5, 'Liberty Campaign/EffectData/MedivacHealSearch/AreaArray@Radius')
 write(uid, prefix+'scan_interval', round(0.0625 / faster, 10),
       'Liberty Campaign/EffectData/HealScanPersistent/PeriodicPeriodArray=0.0625' + clock)
 write(uid, prefix+'start_energy', cat.scalar('ValidatorData','healCasterMinEnergy','Value'), 'ValidatorData/healCasterMinEnergy/Value')
 write(uid, prefix+'sustain_energy', 1, 'Liberty Campaign/ValidatorData/HealPeriodicCombine → Liberty/ValidatorData/CasterHasEnergy')
 write(uid, prefix+'energy_cost', 0.33, 'Liberty Campaign/EffectData/MedivacHealModifyCasterEnergy/VitalArray[Energy]')

def apply():
 cat=Catalog();path=ROOT/'data/units.json';data=json.loads(path.read_text(encoding='utf-8'));units=data['units']
 extension_path=ROOT/'data/units/defense_reference.json'
 extension=json.loads(extension_path.read_text(encoding='utf-8')) if extension_path.exists() else {}
 profile_version=data['version']
 previous_path=ROOT/'data/units/desert_storm_reference.json'
 previous=json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {}
 audit={'version':profile_version,'source':'reference/desert-storm','policy':'仅导入本地图明确覆盖项；普通组价按地图单价×每组数量。标注 FightParty 主动平衡的组价、组数和生命值沿用兵种配置。已核对的战役或合作模组继承值逐项注明，其余缺失字段保留回退。',
        'units':{},'changes':[],'unresolved':[]}
 def write(uid,path,value,source):
  unit=units[uid];old=unit
  try:
   for part in path.split('/'):old=old[int(part)] if isinstance(old,list) else old[part]
  except (KeyError,IndexError):old=None
  if (uid in PROJECT_PACKS and path=='cost') or (uid=='zergling' and path=='hp'):
   value=old
   source=PACK_BALANCE_SOURCE+source
  if isinstance(value,float) and value.is_integer():value=int(value)
  if old!=value:audit['changes'].append({'id':uid,'path':path,'before':copy.deepcopy(old),'after':copy.deepcopy(value),'source':source})
  if old!=value:set_path(unit,path,value)
  audit['units'].setdefault(uid,{'source_unit':UNIT_IDS.get(uid,''),'fields':{}})['fields'][path]=source
 def pending(uid,path,reason):
  audit['unresolved'].append({'id':uid,'path':path,'reason':reason})
 def skill(uid,key,config,source):
  units[uid].setdefault('skills',{})
  write(uid,'skills/'+key,config,source)
 # Seed inherited values before importing the local damage, round duration and pack price.
 apply_viking_assault(cat, write)
 for uid,sid in UNIT_IDS.items():
  unit=units[uid];node=cat.node('UnitData',sid)
  if node is None:pending(uid,'unit','未找到对应UnitData条目');continue
  for native,local in SCALARS.items():
   val=cat.scalar('UnitData',sid,native)
   if isinstance(val,(int,float)):write(uid,local,val,f'UnitData/{sid}/{native}')
  if unit.get('initial_energy',0)>unit.get('energy',0):
   pending(uid,'energy','地图明确写出初始能量，但能量上限继承原版；保留现有上限')
  if unit.get('status')!='summoned':
   for resource,key in [('Minerals','cost'),('Vespene','gas_cost')]:
    val=cat.scalar('UnitData',sid,'CostResource',resource)
    if isinstance(val,(int,float)):write(uid,key,int(val*unit.get('spawn_count',1)),f'UnitData/{sid}/CostResource[{resource}] × spawn_count')
  for attr in cat.children('UnitData',sid,'Attributes'):
   tag=ATTRS.get(attr.get('index'))
   if not tag:continue
   enabled=attr.get('value')=='1'
   if tag in ['light','heavy']:
    if enabled:write(uid,'armor_type',tag,f'UnitData/{sid}/Attributes[{attr.get("index")}]')
    elif unit.get('armor_type')==tag:write(uid,'armor_type','none',f'UnitData/{sid}/Attributes[{attr.get("index")}]')
   else:
    tags=list(unit.get('tags',[]))
    if enabled and tag not in tags:tags.append(tag)
    if not enabled and tag in tags:tags.remove(tag)
    write(uid,'tags',tags,f'UnitData/{sid}/Attributes[{attr.get("index")}]')
  for native,local in [('LifeMax','hp'),('Speed','speed'),('EnergyMax','energy')]:
   if cat.scalar('UnitData',sid,native) is None:pending(uid,local,f'{sid}/{native}未在地图显式覆盖，保留现值；须合并对应原版/模组才可确认')
  entry=audit['units'].setdefault(uid,{'source_unit':sid,'fields':{}})
  if uid in PROJECT_PACKS:
   entry['fields']['spawn_count']=PACK_COUNT_SOURCE
  entry['abilities']=[n.get('Link') for n in node.findall('AbilArray') if n.get('Link') and n.get('removed')!='1']
  entry['behaviors']=[n.get('Link') for n in node.findall('BehaviorArray') if n.get('Link') and n.get('removed')!='1']
  for bid in entry['behaviors']:
   if bid not in ['slowprotoss275','speed225','speed295land','StalkerAutoBlink']:
    pending(uid,'behavior:'+bid,'行为挂载已识别；继承的修改器、触发效果尚未完整还原，不以名字推断功能')
  combat=[]
  for bid in entry['behaviors']:
   b=cat.node('BehaviorData',bid)
   if b is None:continue
   mod=b.find('Modification')
   if mod is None:continue
   known={key:float(mod.get(native)) for native,key in [('MoveSpeedMaximum','speed_maximum'),('MoveSpeedMultiplier','speed_multiplier'),('MoveSpeedBonus','speed_bonus')] if mod.get(native) is not None}
   if known and any(v.get('value')=='Speedfixcancel' for v in b.findall('RemoveValidatorArray')):
    combat.append(known)
  if combat:skill(uid,'combat_mobility',{'modifiers':combat,'display_name':'交战机动'},'BehaviorData/'+','.join(entry['behaviors'])+'; ValidatorData/Speedfixcancel')
 # Each weapon retains a canonical mode; local metadata cannot masquerade as damage.
 for uid,mappings in MODES.items():
  unit=units[uid];modes={m['id']:(i,m) for i,m in enumerate(unit['attack_modes'])}
  for mid,wid,eid in mappings:
   if mid not in modes:pending(uid,'attack_modes/'+mid,'当前模式ID不匹配');continue
   i,mode=modes[mid];prefix=f'attack_modes/{i}/'
   for native,key in [('Range','range'),('DamagePoint','windup'),('Backswing','backswing'),('DisplayAttackCount','hit_count')]:
    # Preserve project-approved melee/contact ranges when refreshing the source map.
    if uid in ('zergling','baneling','ultralisk') and key=='range':continue
    val=cat.scalar('WeaponData',wid,native)
    if isinstance(val,(int,float)):write(uid,prefix+key,int(val) if key=='hit_count' else val,f'WeaponData/{wid}/{native}')
   effect=cat.node('EffectData',eid)
   if effect is not None and effect.tag=='CEffectDamage':
    amount=cat.scalar('EffectData',eid,'Amount')
    if isinstance(amount,(int,float)):write(uid,prefix+'damage',amount,f'EffectData/{eid}/Amount')
    for att in cat.children('EffectData',eid,'AttributeBonus'):
     tag=ATTRS.get(att.get('index'))
     if not tag or att.get('value') is None:continue
     key='bonus' if tag in ['light','heavy'] else 'bonus_tags'
     write(uid,prefix+key+'/'+tag,float(att.get('value')),f'EffectData/{eid}/AttributeBonus[{att.get("index")}]')
    for native,key in [('ShieldBonus','shield_bonus'),('ArmorReduction','armor_multiplier')]:
     val=cat.scalar('EffectData',eid,native)
     if isinstance(val,(int,float)):write(uid,prefix+key,val,f'EffectData/{eid}/{native}')
    # Only whole explicit areas with Fraction are safe: indexed radius-only edits inherit unknown fractions.
    areas=cat.children('EffectData',eid,'AreaArray')
    rings=[{'radius':float(a.get('Radius')),'multiplier':float(a.get('Fraction'))} for a in areas if a.get('Radius') and a.get('Fraction')]
    if uid in ('baneling','ultralisk'):pass  # Project uses collision-based blast / sector, not source radius rings.
    elif rings and len(rings)==len(areas):
     rings.sort(key=lambda r:r['radius']);write(uid,prefix+'splash_rings',rings,f'EffectData/{eid}/AreaArray')
     write(uid,prefix+'splash',rings[-1]['radius'],f'EffectData/{eid}/AreaArray')
    elif areas:pending(uid,prefix+'splash','溅射区域只覆盖半径或部分索引，倍率继承未齐，不根据其他武器猜测')
   elif eid:pending(uid,prefix+'damage',f'EffectData/{eid}未定义可直接读取的Damage，保留现值')
   period=cat.scalar('WeaponData',wid,'Period')
   if isinstance(period,(int,float)):
    if mode['delivery']['type']=='beam':
     write(uid,prefix+'delivery/tick_interval',period,f'WeaponData/{wid}/Period')
     write(uid,prefix+'attack_duration',period,f'WeaponData/{wid}/Period')
    else:
     wait=max(.001,round(period-mode.get('attack_duration',.1)-mode.get('windup',0)-mode.get('backswing',0),6))
     write(uid,prefix+'interval',wait,f'WeaponData/{wid}/Period（完整周期减出手与前后摇）')
   if uid not in ('zergling','baneling','ultralisk') and cat.scalar('WeaponData',wid,'Range') is None:pending(uid,prefix+'range',f'WeaponData/{wid}/Range继承原版，不把MinScanRange当成射程')
   if cat.scalar('WeaponData',wid,'Period') is None:pending(uid,prefix+'interval',f'WeaponData/{wid}/Period继承原版，保留当前轮后间隔')
   if cat.scalar('WeaponData',wid,'DisplayAttackCount') is None:pending(uid,prefix+'hit_count','每轮段数未显式覆盖，仍用现有参数；不使用显示Level反推段数')
   if not cat.children('EffectData',eid,'AttributeBonus'):
    pending(uid,prefix+'bonus','加成未显式覆盖，可能继承原版；保留现有加成，不把缺失当作0')
 # Filter inheritance warnings now resolved from the ground Viking's underlying catalogs.
 viking_fields=audit['units']['viking_assault']['fields']
 audit['unresolved']=[item for item in audit['unresolved'] if item['id']!='viking_assault' or item['path'] not in viking_fields]
 # Confirmed skill overrides. Other native abilities remain in unresolved inventory.
 apply_infantry_stimulants(cat, units, write)
 # Additional Adept fields come from its inherited weapon and the map's two mutually exclusive orders.
 adept_fields=audit['units']['adept']['fields']
 adept_fields.update({
  'spawn_count':'ShakurasGateway/EnergyMax；GameStrings/Button/Tooltip/ShakurasGateway 部署两名；每名140矿',
  'speed':'Void/UnitData/Adept/Speed（原始游戏秒）', 'collision_radius':'Core/UnitData/Radius=0.5',
  'armor_type':'Unit/Adept 属性及 ShakurasGateway 中文说明：轻甲', 'tags':'Unit/Adept 属性及 ShakurasGateway 中文说明：生物',
  'shield_regen':'Void/UnitData/Adept/ShieldRegenRate', 'shield_regen_delay':'Void/UnitData/Adept/ShieldRegenDelay',
  'attack_modes/0/target_layers':'WeaponData/Adept/TargetFilters：Ground',
  'attack_modes/0/hit_count':'Void/WeaponData/Adept 单发共鸣之刃',
  'attack_modes/0/interval':'Void/WeaponData/Adept/Period=2.25；MapScript 全局 AdeptPiercingAttack 攻速+45%；完整周期 2.25/1.45 减出手',
  'attack_modes/0/attack_duration':'Core/WeaponData/DamagePoint=0.167，以单段出手持续时间表达',
  'attack_modes/0/delivery/speed':'Void/MoverData/AdeptWeapon 继承 Core/MoverData/MissileDefault，速度18.75',
  'skills/psionic_transfer/launch_delay':'MapScript 发出 AdeptPhaseShift 指令前 Wait(0.25)',
  'skills/psionic_transfer/contact_range':'ValidatorData/EnemiesGroundNearbyRange622222，地面敌人',
  'skills/psionic_transfer/retreat_shield_threshold':'ValidatorData/CasterShieldLT30',
  'skills/psionic_transfer/retreat_cooldown':'AbilData/AdeptPhaseShift_FSB/Cost/Cooldown',
  'skills/psionic_transfer/attacker_range':'AbilData/AdeptPhaseShift_FSB/AutoCastRange',
  'skills/psionic_transfer/retreat_distance':'EffectData/AdeptPhaseShift_LaunchBack/ImpactOffset',
  'skills/psionic_transfer/retreat_speed':'MoverData/AdeptPhaseShift/MotionPhases/MaxSpeed',
 })
 audit['unresolved']=[item for item in audit['unresolved'] if item['id']!='adept' or item['path'] not in adept_fields]
 pending('adept','skills/psionic_transfer/shade_speed','主包投影基础速度2.9531，按 Void 行为加成1.75 暂取4.7031格/秒。间接依赖是否改写该加成待确认。')
 # The ordinary Hellbat equips weapon HellionTank. The unit with that second ID is a different variant.
 hellbat_fields=audit['units']['hellbat_mech']['fields']
 hellbat_fields.update({
  'spawn_count':PACK_COUNT_SOURCE+'；原图参考 MapScript/Upgrade_BZZDB=8 → Hellbat；GameStrings/Button/Tooltip/DSSupplyDepot1 部署1台',
  'speed':'Swarm/UnitData/HellionTank/Speed=2.25（游戏秒）',
  'energy':'Hellbat、HellionTank 及 Core/CUnit 均未设置能量池，使用 SC2 单位缺省值 0',
  'size':'Swarm/UnitData/HellionTank/Radius=0.625，模型宽高按直径填写',
  'collision_radius':'Swarm/UnitData/HellionTank/SeparationRadius=0.75',
  'armor_type':'GameStrings/Button/Tooltip/DSSupplyDepot1 轻甲',
  'tags':'Swarm/UnitData/HellionTank 的 Mechanical 及 Void/UnitData/HellionTank 的 Biological；GameStrings/DSSupplyDepot1 及 TechAliasArray[4]=1 表示冲击性',
  'attack_modes/0/target_layers':'Hellbat/WeaponArray → HellionTank；HellionTankSearch 的地面目标过滤',
  'attack_modes/0/range':'FightParty 近距开火调校，按双方碰撞边缘计；原图 Swarm/WeaponData/HellionTank/Range=2',
  'attack_modes/0/hit_count':'Swarm/EffectData/HellionTank → HellionTankDamage 主目标一次，HellionTankSearch 排除主目标',
  'attack_modes/0/attack_duration':'Core/WeaponData/DamagePoint=0.167，映射为一次出手',
  'attack_modes/0/backswing':'Core/WeaponData/Backswing=0.5',
  'attack_modes/0/interval':'Void/WeaponData/HellionTank/Period=2游戏秒，扣除0.167出手和0.5后摇',
  'attack_modes/0/delivery/angle_degrees':'Void/EffectData/HellionTankSearch/AreaArray@Arc=45',
  'attack_modes/0/delivery/length':'FightParty 短扇形调校，自机体前缘起算；原图 Void/EffectData/HellionTankSearch/AreaArray@Radius=2',
 })
 audit['units']['hellbat']['fields'].update({
  'collision_radius':'UnitData/HellionBlackOps、HHHellionTank/SeparationRadius=0.75（Hellion本体未覆盖，取图内恶火变体的分离半径）',
  'separate_when_stopped':'试玩反馈：同特战队员在攻击冷却中散开，降低溅射叠伤',
  'tags':'机械车型继承 UnitData/Hellion；具有原图变形恶火 HellionMorph/TechAliasArray[4]=1 的冲击性',
 })
 audit['unresolved']=[item for item in audit['unresolved'] if item['id']!='hellbat_mech' or item['path'] not in hellbat_fields]
 # Post-morph armor must be applied at damage settlement, not only recorded in a sheet.
 armor=cat.scalar('UnitData','SiegeTankSieged','LifeArmor')
 write('mortar','skills/deployment/armor_override',armor,'UnitData/SiegeTankSieged/LifeArmor')
 b=cat.node('BehaviorData','ImmortalBarrierBase3');mod=b.find('Modification')
 skill('immortal','shield_armor_buff',{'display_name':'刚毅护盾','amount':float(mod.get('ShieldArmorBonus')),'duration':float(b.find('Duration').get('value')),'cooldown':45,'requires_damaged_shields':True},'AbilData/ImmortalBarrierArmor → EffectData/ImmortalBarrierBaseABArmor → BehaviorData/ImmortalBarrierBase3')
 if 'barrier' in units['immortal'].get('skills',{}):
  audit['changes'].append({'id':'immortal','path':'skills/barrier','before':units['immortal']['skills'].pop('barrier'),'after':None,'source':'替换为原图护盾护甲机制'})
 b=cat.node('BehaviorData','HydraliskFrenzynormal')
 skill('hydralisk','mobility_burst',{'display_name':'狂暴机动','duration':1,'cooldown':14,'initial_cooldown':1,'enemy_radius':7,'speed_multiplier':2,'only_out_of_combat':True},'AbilData/HydraliskFrenzynormal → BehaviorData/HydraliskFrenzynormal; ValidatorData/NoEnemiesNearbyWidowRange7')
 # The zealot's explicit persistent schedules two hits at 0 and 0.28 seconds.
 write('vanguard','attack_modes/0/strike_offsets',[0,0.28],'EffectData/Weapon_LNLR/PeriodicPeriodArray')
 write('vanguard','attack_modes/0/attack_duration',0.28,'EffectData/Weapon_LNLR/PeriodicPeriodArray')
 write('vanguard','attack_modes/0/interval',0.92,'WeaponData/Weapon_LNLR/Period=1.2 减0.28秒出手')
 write('stalker','skills/blink/distance',14,'EffectData/StalkerAutoBlinkCP/InitialOffset')
 write('stalker','skills/blink/cooldown',8,'EffectData/StalkerBlinkSetCooldown/Cost@CooldownTimeUse')
 write('stalker','skills/blink/shield_threshold',30,'ValidatorData/CasterShieldLT30（原图自动闪烁）')
 write('stalker','skills/blink/damage_trigger',True,'BehaviorData/StalkerAutoBlink/DamageResponse')
 write('stalker','skills/blink/invulnerable_seconds',0.07,'BehaviorData/StalkerBlink0625/Duration 与 StateFlags[Invulnerable]')
 write('void_ray','skills/weapon_buff/cooldown',60,'AbilData/DSVoidRaySwarmDamageBoost/Cost/Cooldown@TimeUse')
 write('tunneler','skills/summon/interval',30,'AbilData/SpawnLocustsTargeted/Cost/Cooldown@TimeUse')
 write('medic','attack_modes/0/range',4,'AbilData/heal/Range')
 write('medic','skills/healing/follow_distance',units['medic']['skills']['healing'].get('follow_distance',3),'项目后排治疗AI保留')
 write('high_templar','skills/delayed_area/cooldown',5,'AbilData/PsiStorm/Cost/Cooldown@TimeUse')
 write('high_templar','skills/delayed_area/range',9,'AbilData/PsiStorm/AutoCastRange（只用于自动施法触发）')
 write('ravager','skills/delayed_area/range',10,'AbilData/RavagerCorrosiveBile/AutoCastRange（自动施法范围）')
 # Use the explicit burrow stat section delay, without guessing engine-only unburrow timing.
 duration=cat.scalar('AbilData','BurrowLurkerMPDown','InfoArray/SectionArray/DurationArray','Delay')
 if duration is not None:write('piercer','skills/deployment/deploy_seconds',duration,'AbilData/BurrowLurkerMPDown/InfoArray/SectionArray/DurationArray[Delay]')
 # Lurker's local persistent contains an explicit 0.125s period, but its other offsets/effects inherit.
 write('piercer','attack_modes/0/delivery/length',12,'WeaponData/Lurker/Range（固定地刺总长）')
 for uid,entry in audit['units'].items():
  covered={mid for mid,_,_ in MODES.get(uid,[])}
  for i,mode in enumerate(units[uid]['attack_modes']):
   if mode['id'] not in covered and mode['damage']>0:
    pending(uid,f'attack_modes/{i}','该模式未找到完整原图对应，保留项目回退；不宣称已按原图还原')
  for aid in entry.get('abilities',[]):
   if aid.startswith('wanttoattack') or aid in ['move','attack','DSStimpack','DSStimpackMarauder','HydraliskFrenzynormal','ImmortalBarrierArmor','heal','SiegeMode','BurrowLurkerMPDown','SpawnLocustsTargeted']:continue
   pending(uid,'ability:'+aid,'已识别挂载，但效果链/原版继承/施法条件未全部还原；不将参数登记冒充完整实装')
 for uid in ['agent','infestor','carrier','disruptor','colossus','void_ray','stalker']:
  pending(uid,'skill_semantics','保留现有原型技能；原图的额外技能和未齐效果链须合并原版/依赖后继续移植')
 # Descriptions reflect confirmed replacements; no effect text is mistaken for a mechanic.
 write('hellbat','sc2','恶火 Hellion','UnitData/Hellion 对应关系（内部ID保留hellbat）')
 write('immortal','role','刚毅护盾 · 前排抗压','BehaviorData/ImmortalBarrierBase3')
 write('immortal','counter','护盾受损时短时增加40护盾护甲；不生成吸收盾','BehaviorData/ImmortalBarrierBase3')
 # Source removes unit-side movement upgrades? Absence is not a removal; keep existing skills unless a confirmed replacement exists.
 for uid,entry in audit['units'].items():
  units[uid]['source_profile']={'map_unit':entry['source_unit'],'source':'desert-storm','status':'explicit_overrides'}
 # The purchase is a pair of ordinary Medivacs; commander variants use different effect chains.
 audit['units']['medivac']={
  'source_unit':'Medivac', 'fields':{},
  'abilities':['MedivacDoubleBeamHeal','MedivacSpeedBoost'], 'behaviors':[],
 }
 apply_medivac(cat, write)
 pending('medivac','ability:MedivacSpeedBoost','原图存在推进加速，本次还原双束治疗，推进加速尚未接入。')
 for unit in units.values():
  unit.setdefault('gas_cost',0);unit.setdefault('core_cost',0)
 audit['units'].update(extension.get('units',{}))
 audit['unresolved'].extend(extension.get('unresolved',[]))
 path.write_text(json.dumps(data,ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
 # Preserve original before-values when a developer reapplies the same profile.
 if previous.get('version')==audit['version']:
  earlier={(c['id'],c['path']):c for c in previous.get('changes',[])}
  for change in audit['changes']:
   key=(change['id'],change['path'])
   if key in earlier:change['before']=earlier[key]['before']
   earlier[key]=change
  audit['changes']=list(earlier.values())
 (ROOT/'data/units/desert_storm_reference.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 # Retain older unresolved fields only when this port did not resolve that path.
 rp=ROOT/'data/units/sc2_reference.json';old=json.loads(rp.read_text(encoding='utf-8'))
 old['policy']='0.11.0起以沙漠风暴明确覆盖项为准；此文件保留原版继承回退与尚未确认的旧标记。详见desert_storm_reference.json。'
 def still_exists(item):
  node=units.get(item['id'],{})
  try:
   for part in item['path'].split('/'):node=node[int(part)] if isinstance(node,list) else node[part]
   return True
  except (KeyError,IndexError,TypeError,ValueError):return False
 old['review']=[r for r in old.get('review',[]) if still_exists(r) and r['path'] not in audit['units'].get(r['id'],{}).get('fields',{})]
 rp.write_text(json.dumps(old,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(f'Wrote explicit overrides: {len(audit["units"])} units, {len(audit["changes"])} changes; unresolved dependencies recorded separately.')

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--apply',action='store_true');args=parser.parse_args()
 if not args.apply:parser.error('Use --apply to update units.json and the source ledger; this does not run Godot or simulations.')
 apply()
