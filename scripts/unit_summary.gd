extends RefCounted
## 选中卡片下的紧凑资料；只展示现有配置，不在简介中解释技能效果。
const ARMOR_NAMES := {"light":"轻甲","heavy":"重甲","none":"无分类","special":"特殊甲"}
const SKILL_NAMES := {
	"deployment":"架设", "defender_zone":"防卫模式", "healing":"治疗",
	"stimulant":"强化剂", "on_hit_slow":"命中减速", "multi_attack":"多重攻击",
	"line_attack":"直线攻击", "weapon_switch":"武器切换", "yamato":"大和炮",
	"regen":"再生", "suicide":"自爆", "delayed_area":"范围攻击",
	"charge":"冲锋", "blink":"闪烁", "dive":"钻地突进", "aura":"光环",
	"barrier":"屏障", "dot":"毒素", "ramp_damage":"蓄能",
	"chain_attack":"弹射", "summon":"召唤", "on_death":"死亡触发",
	"corpse_raise":"尸体复生", "mobile_attack":"移动攻击", "weapon_buff":"棱镜校准",
	"independent_weapons":"驻军火力"
}
const EFFECT_NAMES := {"flame":"火焰喷射","spike":"地刺","beam":"双束扫射","bile":"腐蚀胆汁","fungal":"真菌增生","storm":"灵能风暴","nova":"净化新星"}
const MODE_NAMES := {"high_impact":"高射","javelin":"导弹","hammer":"重炮","armor_piercing":"穿甲","precision":"狙击","ats_laser":"对地","ata_laser":"对空","siege_cannon":"架设","mobile_cannon":"机动","defender_cannon":"防卫","garrison_rifle":"驻军枪兵","garrison_marauder":"驻军劫掠者"}
const TAG_NAMES := {"biological":"生物","mechanical":"机械","massive":"巨型","psionic":"灵能","structure":"建筑","light":"轻甲","heavy":"重甲"}

static func number(value) -> String:
	return ("%.2f" % float(value)).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func weapons(stats: Dictionary) -> Array:
	var skills: Dictionary = stats.get("skills",{})
	var result: Array = []
	if stats.has("attack_modes"):
		for mode in stats.attack_modes:
			result.append({"label":"" if stats.attack_modes.size()==1 else MODE_NAMES.get(str(mode.id),mode.label),"data":mode})
		return result
	if skills.has("weapon_switch"):
		for mode in skills.weapon_switch.weapons:
			result.append({"label":MODE_NAMES.get(str(mode.id),mode.get("label","")),"data":mode})
	else:result.append({"label":"移动" if skills.has("deployment") and skills.deployment.has("weapon") else "","data":stats})
	for skill_id in ["deployment","defender_zone"]:
		if skills.has(skill_id) and skills[skill_id].has("weapon"):
			result.append({"label":"架设" if skill_id=="deployment" else "防卫","data":skills[skill_id].weapon})
	return result

static func skill_names(stats: Dictionary, modes: Array) -> Array:
	var names: Array = []
	for key in stats.get("skills",{}):
		var config: Dictionary = stats.skills[key]
		var name: String = str(config.get("display_name",SKILL_NAMES.get(key,"特殊技能")))
		if key=="deployment" and config.get("mode","")=="burrow":name="埋地"
		elif key in ["line_attack","delayed_area"]:name=str(EFFECT_NAMES.get(str(config.get("effect","")),name))
		elif key=="aura" and float(config.get("ranged_damage_reduction",0))>0:name="守护者之盾"
		elif key=="summon":name=str({"locust":"孵化蝗虫","broodling":"孵化巢虫","interceptor":"拦截机"}.get(str(config.get("kind","")),name))
		elif key=="on_death":name="死亡分裂" if config.has("summon") else "死亡爆发"
		if not names.has(name):names.append(name)
	var count: int = 1 if stats.get("delivery",{}).get("type","")=="beam" else int(stats.get("hit_count",1))
	for mode in modes:
		if mode.data.get("delivery",{}).get("type","")=="beam":
			var beam_name := "持续治疗" if float(mode.data.get("healing",0))>0 else "持续光束"
			if float(mode.data.get("healing",0))>0:names.erase("治疗")
			if not names.has(beam_name):names.append(beam_name)
		else:count=maxi(count,int(mode.data.get("hit_count",1)))
	if count>1:
		var name := "双重攻击" if count==2 else "多重攻击"
		if not names.has(name):names.append(name)
	return names

static func text(stats: Dictionary) -> String:
	var modes := weapons(stats)
	var ranges: Array = []
	var bonuses: Array = []
	for mode in modes:
		var weapon: Dictionary = mode.data
		var reach := number(weapon.get("range",stats.range))
		if not ranges.has(reach):ranges.append(reach)
		var extra: Array = []
		for armor in weapon.get("bonus",{}):
			if float(weapon.bonus[armor])>0:extra.append("%s+%s" % [ARMOR_NAMES.get(armor,armor),number(weapon.bonus[armor])])
		for tag in weapon.get("bonus_tags",{}):
			if float(weapon.bonus_tags[tag])>0:extra.append("%s+%s" % [TAG_NAMES.get(tag,tag),number(weapon.bonus_tags[tag])])
		if float(weapon.get("shield_bonus",0))>0:extra.append("护盾+"+number(weapon.shield_bonus))
		if not extra.is_empty():
			bonuses.append((str(mode.label)+" " if str(mode.label)!="" else "")+"、".join(extra))
	var names := skill_names(stats,modes)
	return "射程 %s  移速 %s  护甲 %s\n加成：%s\n技能：%s" % ["/".join(ranges),number(stats.speed),ARMOR_NAMES.get(str(stats.get("armor_type","none")),"无分类"),"；".join(bonuses) if not bonuses.is_empty() else "无","、".join(names) if not names.is_empty() else "无"]
