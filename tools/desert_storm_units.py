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
UNIT_IDS = {
 'rifle':'Marine', 'hellbat':'Hellion', 'marauder':'Marauder', 'medic':'Medic',
 'agent':'Ghost', 'widow_mine':'WidowMine', 'mortar':'SiegeTank', 'viking':'VikingFighter',
 'liberator':'Liberator', 'thor':'Thor', 'battlecruiser':'Battlecruiser',
 'zergling':'Zergling','baneling':'Baneling','roach':'Roach','hydralisk':'Hydralisk',
 'ravager':'Ravager','piercer':'LurkerMP','tunneler':'SwarmHostMP','mutalisk':'Mutalisk',
 'infestor':'Infestor','ultralisk':'Ultralisk','brood_lord':'BroodLord',
 'vanguard':'Zealot','stalker':'Stalker','sentry':'Sentry','immortal':'Immortal',
 'high_templar':'HighTemplar','archon':'Archon','colossus':'Colossus','disruptor':'Disruptor',
 'void_ray':'VoidRay','carrier':'Carrier','broodling':'Broodling','locust':'LocustMP','interceptor':'Interceptor',
}
# Explicit correspondence to standard weapon/effect IDs. Native default links are
# not reconstructed: the audit states when the local UnitData omits that link.
MODES = {
 'rifle': [('gauss_rifle','GuassRifle','GuassRifle')],
 'hellbat':[('flame_jet','InfernalFlameThrower','InfernalFlameThrower')],
 'marauder':[('concussive_grenade','PunisherGrenades','PunisherGrenadesU')],
 'agent':[('armor_piercing','C10CanisterRifleFake','C10CanisterRifle')],
 'mortar':[('mobile_cannon','90mmCannons','90mmCannons'),('siege_cannon','CrucioShockCannon','CrucioShockCannonDirected')],
 'viking':[('anti_air_missile','LanzerTorpedoes','LanzerTorpedoesU')],
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

def apply():
 cat=Catalog();path=ROOT/'data/units.json';data=json.loads(path.read_text(encoding='utf-8'));units=data['units']
 previous_path=ROOT/'data/units/desert_storm_reference.json'
 previous=json.loads(previous_path.read_text(encoding='utf-8')) if previous_path.exists() else {}
 audit={'version':'0.11.0','source':'reference/desert-storm','policy':'仅导入本地图明确覆盖项；价格按单体×现有组数；未还原原版/依赖继承。用户确认以参考配置覆盖旧数值。',
        'units':{},'changes':[],'unresolved':[]}
 def write(uid,path,value,source):
  unit=units[uid];old=unit
  try:
   for part in path.split('/'):old=old[int(part)] if isinstance(old,list) else old[part]
  except (KeyError,IndexError):old=None
  if isinstance(value,float) and value.is_integer():value=int(value)
  if old!=value:audit['changes'].append({'id':uid,'path':path,'before':copy.deepcopy(old),'after':copy.deepcopy(value),'source':source})
  if old!=value:set_path(unit,path,value)
  audit['units'].setdefault(uid,{'source_unit':UNIT_IDS.get(uid,''),'fields':{}})['fields'][path]=source
 def pending(uid,path,reason):
  audit['unresolved'].append({'id':uid,'path':path,'reason':reason})
 def skill(uid,key,config,source):
  units[uid].setdefault('skills',{})
  write(uid,'skills/'+key,config,source)
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
    if rings and len(rings)==len(areas):
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
   if cat.scalar('WeaponData',wid,'Range') is None:pending(uid,prefix+'range',f'WeaponData/{wid}/Range继承原版，不把MinScanRange当成射程')
   if cat.scalar('WeaponData',wid,'Period') is None:pending(uid,prefix+'interval',f'WeaponData/{wid}/Period继承原版，保留当前轮后间隔')
   if cat.scalar('WeaponData',wid,'DisplayAttackCount') is None:pending(uid,prefix+'hit_count','每轮段数未显式覆盖，仍用现有参数；不使用显示Level反推段数')
   if not cat.children('EffectData',eid,'AttributeBonus'):
    pending(uid,prefix+'bonus','加成未显式覆盖，可能继承原版；保留现有加成，不把缺失当作0')
 # Confirmed skill overrides. Other native abilities remain in unresolved inventory.
 for uid,aid in [('rifle','DSStimpack'),('marauder','DSStimpackMarauder')]:
  life=cat.scalar('AbilData',aid,'Cost/Vital','Life')
  cooldown_node=cat.children('AbilData',aid,'Cost/Cooldown')
  config=copy.deepcopy(units[uid].get('skills',{}).get('stimulant',{'health_cost_ratio':0,'duration':15,'attack_multiplier':1.5,'speed_multiplier':1.5}))
  config['health_cost']=life;config['health_cost_ratio']=0;config['cooldown']=float(cooldown_node[0].get('TimeUse'))
  skill(uid,'stimulant',config,'AbilData/'+aid+'/Cost')
  for field in ['duration','attack_multiplier','speed_multiplier']:
   pending(uid,'skills/stimulant/'+field,'Stimpack持续时间及倍率继承原版；保留现有参数（新挂载使用SC2原型15秒/1.5倍）')
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
 for unit in units.values():
  unit.setdefault('gas_cost',0);unit.setdefault('core_cost',0)
 data['version']='0.11.0'
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
