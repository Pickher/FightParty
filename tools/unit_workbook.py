#!/usr/bin/env python3
"""当前兵种工作簿：生成需 openpyxl，读取和导入只用标准库。"""
import copy
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORKBOOK = ROOT / 'data' / 'units' / '兵种配置.xlsx'
LABELS = dict(zip(
    'id name race cost spawn_count hp shield shield_armor energy initial_energy armor_type armor damage interval range speed splash splash_multiplier size collision_radius separate_when_stopped bonus target_layers targetable_layers layer tags unit_type damage_type windup backswing health_regen health_regen_delay shield_regen shield_regen_delay energy_regen energy_regen_delay attacks_base attacks_structures structure status symbol color role counter requires sc2'.split(),
    '内部ID 显示名称 种族 每组价格 每组数量 生命上限 护盾上限 护盾护甲 能量上限 初始能量 护甲类型 护甲值 基础伤害 攻击间隔秒 射程格 移速格每秒 溅射半径 次目标伤害倍率 模型尺寸宽高 碰撞半径 停步分散 对甲额外伤害 攻击目标层 可被攻击层 自身层级 单位标签 单位类型 伤害类型 前摇秒 后摇秒 每秒回血 回血延迟秒 每秒回盾 回盾延迟秒 每秒回能 回能延迟秒 可攻击基地 可攻击建筑 是否建筑 实装状态 符号 颜色 定位 特点 前置兵种 星际原型'.split()))
# 伤害类型仍供内部减甲规则使用，编辑表改展示每轮命中次数。
LABELS.pop('damage_type', None)
LABELS['hit_count']='每轮命中次数'
LABELS['damage']='每段基础伤害'
LABELS['collision_radius']='碰撞半径（最终值）'
LABELS.update(bonus_tags='按单位标签额外伤害',shield_bonus='仅对护盾额外伤害',range_from_edge='按模型边缘量射程',pending='未研究或待实现项目')
PARAM_LABELS = {
    'shield_bonus':'仅对护盾额外伤害','structure_damage':'对建筑伤害','range_from_edge':'按模型边缘量射程',
    'hit_count':'每轮命中次数', 'preferred_distance':'期望距离（格）', 'single_target_limit':'移动追击敌人数上限',
    'damage':'基础伤害', 'heavy':'重甲额外伤害', 'light':'轻甲额外伤害',
    'range':'射程（格）', 'interval':'攻击间隔（秒）', 'splash':'溅射半径（格）',
    'splash_multiplier':'次目标伤害倍率', 'length':'传播长度（格）', 'speed':'传播速度（格/秒）',
    'half_width':'攻击半宽（格）', 'duration':'持续时间（秒）', 'duration_seconds':'持续时间（秒）',
    'health_cost_ratio':'最大生命消耗比例', 'attack_multiplier':'攻速倍率', 'speed_multiplier':'移速倍率',
    'deploy_seconds':'架设/埋地耗时（秒）', 'pack_seconds':'收起耗时（秒）',
    'deploy_enemy_threshold':'立即部署人数阈值（需大于）', 'scan_seconds':'扫描间隔（秒）',
    'hold_range_multiplier':'部署保持外围倍率', 'mobile_can_attack':'未部署可攻击',
    'cooldown':'冷却（秒）', 'cooldown_seconds':'冷却（秒）', 'channel_seconds':'引导时间（秒）',
    'min_target_hp':'目标最低当前生命+护盾', 'angle_degrees':'扇形角度', 'heal':'每次治疗量',
    'switch_seconds':'切换耗时（秒）', 'count':'数量（炮位/技能）', 'light_air_threshold':'轻甲空军数量阈值',
}


def kind(value):
    if isinstance(value, bool): return 'bool'
    if isinstance(value, (int, float)): return 'number'
    if isinstance(value, str): return 'text'
    return 'json'


def encode(value):
    return json.dumps(value, ensure_ascii=False) if kind(value) in ('bool', 'json') else value


def decode(raw, expected, where):
    if isinstance(raw, tuple): raise ValueError(where + '：不支持公式、日期或错误值，请粘贴为值。')
    text = str(raw).strip()
    if expected == 'text': return str(raw)
    if not text: raise ValueError(where + '：数值/布尔/JSON 不能为空。')
    if expected == 'number':
        try: value = float(text)
        except ValueError: raise ValueError(where + '：请填数字。')
        if not math.isfinite(value) or value < 0: raise ValueError(where + '：须为非负有限数。')
        return int(value) if value.is_integer() else value
    if expected == 'bool':
        if text.lower() not in ('true', 'false'): raise ValueError(where + '：填 true 或 false。')
        return text.lower() == 'true'
    try: return json.loads(text, parse_constant=lambda s: (_ for _ in ()).throw(ValueError(s)))
    except ValueError: raise ValueError(where + '：请填合法 JSON。')


def leaves(value, path=()):
    if isinstance(value, dict) and value:
        for key, item in value.items(): yield from leaves(item, path + (str(key),))
    elif isinstance(value, list) and value:
        for i, item in enumerate(value): yield from leaves(item, path + (str(i),))
    else: yield path, value


def set_path(unit, path, value):
    node = unit
    for part in path[:-1]: node = node[int(part)] if isinstance(node, list) else node[part]
    if isinstance(node, list): node[int(path[-1])] = value
    else: node[path[-1]] = value


def is_weapon(path):
    return 'weapon' in path or 'weapons' in path


def validate(units):
    for uid, unit in units.items():
        where = uid + '：'
        for key in ('hp', 'interval'):
            if not isinstance(unit.get(key), (int, float)) or unit[key] <= 0: raise ValueError(where + key + ' 必须大于 0。')
        for key in ('cost', 'spawn_count'):
            val = unit.get(key, 1)
            if not isinstance(val, (int, float)) or isinstance(val, bool) or int(val) != val or val < (0 if key == 'cost' and (unit.get('structure') or unit.get('status')=='summoned') else 1):
                raise ValueError(where + key + ' 必须为整数，兵种价格/数量须为正。')
        for key, choices in [('race', ('terran','zerg','protoss','blight','neutral')), ('armor_type', ('none','light','heavy','special')), ('layer', ('ground','air')), ('status', ('ready','stub','summoned')), ('damage_type', ('physical','spell','true'))]:
            if key in unit and unit[key] not in choices: raise ValueError(where + key + ' 枚举值无效。')
        if not unit.get('name') or not re.fullmatch('[0-9a-fA-F]{6}', str(unit.get('color',''))): raise ValueError(where + '名称或颜色无效。')
        if len(str(unit.get('symbol',''))) != 1: raise ValueError(where + 'symbol 必须为单字符。')
        if not isinstance(unit.get('skills',{}), dict): raise ValueError(where + 'skills 须为对象。')
        for path, value in leaves(unit):
            key = path[-1]
            if isinstance(value, (int,float)) and not isinstance(value,bool) and (not math.isfinite(value) or value < 0): raise ValueError(where + '/'.join(path) + ' 须为非负有限数。')
            if key in ('interval','speed','scan_seconds','length') and isinstance(value,(int,float)) and value <= 0 and path[0]=='skills': raise ValueError(where + '/'.join(path) + ' 必须大于 0。')
            if len(path)>1 and path[-2] in ('target_layers','targetable_layers') and value not in ('ground','air'): raise ValueError(where + '/'.join(path) + ' 只能填 ground/air。')
            if key in ('hit_count','single_target_limit','count','max_count','bounces','max_stacks','deploy_enemy_threshold','light_air_threshold','default_index') and (not isinstance(value,(int,float)) or isinstance(value,bool) or int(value)!=value): raise ValueError(where + '/'.join(path) + ' 必须为整数。')
            if key=='hit_count' and value<1: raise ValueError(where + '/'.join(path) + ' 必须至少为1。')
            if key in ('splash_multiplier','health_cost_ratio') and not 0 <= value <= 1: raise ValueError(where + '/'.join(path) + ' 应在 0～1 之间。')
        for key in ('size',):
            val = unit.get(key,[1,1])
            if not isinstance(val,list) or len(val)!=2 or any(not isinstance(x,(int,float)) or isinstance(x,bool) or x<=0 for x in val): raise ValueError(where + 'size 须为两个正数的 JSON 数组。')
        for key in ('target_layers','targetable_layers'):
            if key in unit and (not isinstance(unit[key],list) or not unit[key] or any(x not in ('ground','air') for x in unit[key])): raise ValueError(where + key + ' 须为 ground/air 的非空 JSON 数组。')
        if not isinstance(unit.get('bonus',{}),dict) or any(not isinstance(v,(int,float)) or isinstance(v,bool) for v in unit.get('bonus',{}).values()): raise ValueError(where + 'bonus 须为数值对象。')
        for key in ('tags','requires'):
            if key in unit and (not isinstance(unit[key],list) or any(not isinstance(x,str) for x in unit[key])): raise ValueError(where + key + ' 须为文字数组。')


def merge_edits(base, edited, current, path=''):
    """仅应用用户相对导出快照的编辑；保留随后代码变更，同字段并发修改报冲突。"""
    if edited == base: return copy.deepcopy(current)
    if current == base or current == edited: return copy.deepcopy(edited)
    if all(isinstance(x,dict) for x in (base,edited,current)):
        result = copy.deepcopy(current)
        for key in edited:
            if key not in base:
                if key in current and current[key] != edited[key]: raise ValueError('并发修改冲突：'+path+'/'+key)
                result[key]=copy.deepcopy(edited[key])
            elif key in current: result[key]=merge_edits(base[key],edited[key],current[key],path+'/'+key)
            elif edited[key]!=base[key]: raise ValueError('字段已被代码删除：'+path+'/'+key)
        return result
    raise ValueError('表格和代码修改了同一字段：'+path+'；请刷新表格后重新填写。')


def parse_workbook(path, current, read_rows):
    source = read_rows(path, '源数据')
    base = {}
    for n,cells in source.items():
        if n > 1 and cells.get('A'): base[str(cells['A'])]=json.loads(cells['B'])
    if not base: raise ValueError('源数据快照为空，请使用完整工作簿。')
    edited=copy.deepcopy(base)
    try:
        review_rows=read_rows(path,'待确认字段')
    except ValueError as error:
        if '找不到“待确认字段”' not in str(error):raise
        review_rows={}
    review_keys={(str(c.get('A','')),str(c.get('B',''))) for n,c in review_rows.items() if n>1 and c.get('A')}
    touched={}
    rows=read_rows(path,'兵种属性')
    headers=rows[2]
    if len(set(headers.values()))!=len(headers) or 'id' not in headers.values(): raise ValueError('兵种属性字段缺失或重复。')
    samples={k:v for u in base.values() for k,v in u.items() if k!='skills'}
    if not set(headers.values()).issubset(set(samples)|{'id'}): raise ValueError('存在未知属性列。')
    seen=set()
    for n,cells in rows.items():
        if n <= 2 or not any(v!='' for v in cells.values()): continue
        if any(v!='' for c,v in cells.items() if c not in headers): raise ValueError('兵种属性：字段范围外有内容。')
        uid=str(next((cells.get(c,'') for c,k in headers.items() if k=='id'),''))
        if uid not in base or uid in seen: raise ValueError('未知或重复兵种 ID：'+uid+'；新增兵种请先由开发者接入。')
        seen.add(uid)
        expected=set(base[uid])-{'skills','damage_type'}
        if not expected.issubset(set(headers.values())): raise ValueError(uid+'：属性列被删除。')
        for col,key in headers.items():
            if key=='id': continue
            raw=cells.get(col,'')
            if key not in base[uid]:
                if raw!='':
                    value=decode(raw,kind(samples[key]),'兵种属性第%d行 %s'%(n,key))
                    if type(value)!=type(samples[key]) and not (kind(value)==kind(samples[key])=='number'): raise ValueError(uid+'：'+key+' 类型错误。')
                    edited[uid][key]=value
                continue
            if raw=='' and (uid,key) in review_keys:continue
            value=decode(raw,kind(base[uid][key]),'兵种属性第%d行 %s'%(n,key))
            if type(value)!=type(base[uid][key]) and not (kind(value)==kind(base[uid][key])=='number'): raise ValueError(uid+'：'+key+' 类型错误。')
            edited[uid][key]=value
            touched[(uid,key)]=value
    if seen!=set(base): raise ValueError('不能删除兵种数据行或更改 ID。')
    expected={(uid,'/'.join(p)):v for uid,u in base.items() for p,v in leaves(u.get('skills',{}),('skills',)) if 'skills' in u}
    seen=set()
    for sheet in ('武器模式','技能参数'):
        for n,cells in read_rows(path,sheet).items():
            if n<=2 or not any(v!='' for v in cells.values()): continue
            uid,p=str(cells.get('A','')),str(cells.get('D',''))
            key=(uid,p)
            if key not in expected or key in seen: raise ValueError(sheet+'：未知或重复参数 '+uid+'/'+p)
            seen.add(key)
            if cells.get('F','')=='' and key in review_keys:continue
            value=decode(cells.get('F',''),kind(expected[key]),sheet+'第%d行 %s/%s'%(n,uid,p))
            if type(value)!=type(expected[key]) and not (kind(value)==kind(expected[key])=='number'): raise ValueError(uid+'/'+p+' 类型错误。')
            set_path(edited[uid],p.split('/'),value)
            touched[key]=value
    if seen!=set(expected): raise ValueError('不能删除技能或武器参数行，请修改值；机制增删由开发者处理。')
    if review_keys:
        for n,cells in read_rows(path,'待确认清单').items():
            if n<=2 or cells.get('D','')=='':continue
            uid,p=str(cells.get('A','')),str(cells.get('C',''))
            if (uid,p) not in review_keys:raise ValueError('待确认清单：未知字段 '+uid+'/'+p)
            original=base[uid]
            for part in p.split('/'):original=original[int(part)] if isinstance(original,list) else original[part]
            value=decode(cells['D'],kind(original),'待确认清单第%d行 %s/%s'%(n,uid,p))
            if type(value)!=type(original) and not (kind(value)==kind(original)=='number'):raise ValueError('待确认清单：类型错误 '+uid+'/'+p)
            if (uid,p) in touched and touched[(uid,p)]!=value:raise ValueError('同一字段在属性/技能页和待确认清单填了不同值：'+uid+'/'+p)
            set_path(edited[uid],p.split('/'),value)
    result=merge_edits(base,edited,current['units'])
    validate(result)
    return result


def export_workbook(source=ROOT/'data/units.json', destination=DEFAULT_WORKBOOK):
    # 仅生成工具需要 openpyxl；导入路径不会加载此依赖。
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.comments import Comment
    from openpyxl.worksheet.datavalidation import DataValidation
    data=json.loads(source.read_text(encoding='utf-8'))
    units=data['units']
    reference_path=source.parent/'units'/'sc2_reference.json'
    reference=json.loads(reference_path.read_text(encoding='utf-8')) if reference_path.exists() else {}
    reviews={(r['id'],r['path']):r for r in reference.get('review',[])}
    wb=Workbook()
    wb.remove(wb.active)
    guide=wb.create_sheet('填写说明')
    notes=[['FightParty 兵种数值表', '源码版本 '+data.get('version','')],
        ['编辑流程','修改下方三页并保存 → 在项目根目录执行 python tools/import_units.py；或把文件交给 AI 导入。'],
        ['审核标记','黄色空白=待确认，灰色空白=不适用。批注记录当前游戏兼容值，空白导入不会写0。可在原页或待确认清单D列填写，勿填两个不同值。'],
        ['原版口径','虫族/神族按5.0.17正式服三攻三防；神族含三盾。独立专属科技未全部点满，详情见技能核对。价格/每组数量保持项目原值。'],
        ['技能核对','该页仅列参考能力及支持状态，待实现能力不会因为填数字而自动生效。待确认清单D列可导入，确认后请同步sc2_reference.json审核状态。'],
        ['兵种属性','一行一个单位；价格按组，生命/伤害按单体；间隔单位秒，射程单位格。'],
        ['武器模式','坦克架设炮、雷神三模式、特工弹药、大和舰空地炮独立列出；这些值会覆盖基础武器。'],
        ['技能参数','一行一个参数；布尔填 true/false；倍率 1.3 表示增加30%，0.5 表示一半。'],
        ['编辑范围','只改属性数据格或参数页 F 列“数值”；保留英文列名、ID、路径、全部数据行及源数据页。支持筛选和整行排序。'],
        ['碰撞体积','collision_radius是最终圆半径，不叠加模型半径；直径=半径×2。全部单位已按模型最大边的一半显式配置；特战队员0.8×0.8对应半径0.4。当前为圆形软避让，不是矩形刚体。'],
        ['复杂字段','size 填 [宽,高]；bonus 填 {"heavy":14}；tags/target_layers 等为 JSON 数组，文字用英文双引号。'],
        ['空白与公式','属性空白表示未配置，可按相同列其他单位的格式补值；不支持公式，请粘贴为值。新增列/单位/技能请交给开发者。'],
        ['并发更新','记录了导出快照；导入只应用你的编辑，保留远程新增数据。同字段并发修改会报错；列表按整体判断冲突。'],
        ['生效范围','导入写入 data/units.json 并自动备份；重启源码游戏生效，已有APK/EXE需要重新打包。'],
        ['刷新表格','python tools/unit_workbook.py --output 新文件.xlsx；生成需安装 openpyxl，导入仅需 Python 标准库。请先保存并导入已有编辑。'],
        ['恶火','开火距离4.5格，火焰固定传播5格，总宽0.6格（half_width为0.3）。'],
        ['当前待确认：特工','基础攻击40，弹药模式仍是30；该差异保留，请在武器模式页分别填写。'],
        ['解放者 / 大和','解放者架设65+30重甲/1.14秒；大和720且目标门槛300。'],
        ['人族防御塔','1200生命/重甲/建筑/不自然回血；驻军8名特战队员、2名劫掠者。武器模式页count是独立炮位数，hit_count是每炮位每轮段数。'],
        ['基地防御模块','gate_tower不再生成独立单位；hp为基地额外生命5000，射程8，单发300真实伤害，间隔0.2秒；health_regen为防御层存在时整座基地的回血5/秒。'],
        ['基地核心规则','data/rules.json中base_hp=10000、base_regen_per_second=5（核心阶段回血）。初始15000，降至10000及以下永久失去额外上限与反击；两阶段均只回血5/秒，不能复活。'],
        ['多段攻击','每轮命中次数×每段伤害；每段单独扣甲/护盾并触发命中效果，可以叠加溅射；一轮只消耗一次攻击冷却。伤害类型由内部保留。'],
        ['雷神','对地2×(27+12重甲)，7格/1.28秒；对空2×(26+22重甲)，10格/3秒；溅射对空4×(9+9轻甲)，10格/3秒/半径1.2。'],
        ['技能能力','填参数仅能调整已实现机制；填写文字不会自动产生新的技能效果。']]
    for row in notes: guide.append(row)
    fields=['id']+[k for k in LABELS if k!='id' and any(k in u for u in units.values())]
    if 'hit_count' in fields:
        fields.remove('hit_count')
        fields.insert(fields.index('damage')+1,'hit_count')
    fields += sorted({k for u in units.values() for k in u}-set(fields)-{'skills','damage_type'})
    basic=wb.create_sheet('兵种属性')
    basic.append([LABELS.get(k,k) for k in fields]);basic.append(fields)
    for uid,u in units.items():
        basic.append([uid if k=='id' else encode(u[k]) if k in u else None for k in fields])
    tabs={}
    for name in ('武器模式','技能参数'):
        ws=wb.create_sheet(name);ws.append(['兵种ID','名称','参数说明','参数路径（勿改）','类型（勿改）','数值（编辑此列）']);ws.append(['id','name','label','path','type','value']);tabs[name]=ws
    for uid,u in units.items():
        if 'skills' not in u: continue
        for p,v in leaves(u['skills'],('skills',)):
            ws=tabs['武器模式' if is_weapon(p) else '技能参数']
            context=p[1] if len(p)>1 else 'skills'
            if 'weapons' in p:
                i=p.index('weapons')
                mode=u['skills'][p[1]]['weapons'][int(p[i+1])]
                context=mode.get('label',mode.get('id',context))
            elif 'weapon' in p:
                context='架设炮' if p[1]=='deployment' else '防卫对地炮'
            label=context+' · '+PARAM_LABELS.get(p[-1],LABELS.get(p[-1],p[-1]))
            ws.append([uid,u['name'],label,'/'.join(p),kind(v),encode(v)])
    if reviews:
        review_manifest=wb.create_sheet('待确认字段');review_manifest.append(['id','path'])
        todo=wb.create_sheet('待确认清单')
        todo.append(['兵种ID','名称','字段路径','确认值（填写）','原因','当前兼容值（仅参考）','来源'])
        todo.append(['id','name','path','value','reason','runtime_value','source'])
        for (uid,p),item in reviews.items():
            review_manifest.append([uid,p])
            todo.append([uid,units[uid]['name'],p,None,item['reason'],encode(item['runtime_value']),reference['units'][uid]['source']])
        review_manifest.sheet_state='hidden'
    if reference:
        inventory=wb.create_sheet('技能核对')
        inventory.append(['兵种ID','名称','原型技能','实现/研究状态','参考参数（不直接导入）','说明','来源'])
        inventory.append(['id','name','ability','status','parameters','note','source'])
        for uid,entry in reference.get('units',{}).items():
            for ability in entry.get('abilities',[]):
                inventory.append([uid,units[uid]['name'],ability['name'],ability['status'],json.dumps(ability['parameters'],ensure_ascii=False),ability.get('note',''),entry['source']])
    baseline=wb.create_sheet('源数据');baseline.append(['id','json'])
    for uid,u in units.items(): baseline.append([uid,json.dumps(u,ensure_ascii=False)])
    baseline.sheet_state='hidden'
    for ws in wb:
        if ws==baseline: continue
        ws.freeze_panes='D3' if ws==basic else 'F3' if ws in tabs.values() else 'B2'
        ws.sheet_view.zoomScale=85
        if ws!=guide: ws.auto_filter.ref='A2:'+ws.cell(ws.max_row,ws.max_column).coordinate
        for row in ws:
            for c in row:
                c.alignment=Alignment(vertical='top',wrap_text=True)
                if c.row<= (1 if ws==guide else 2):
                    c.fill=PatternFill('solid',fgColor='233D58');c.font=Font(color='FFFFFF',bold=True)
                elif c.row%2: c.fill=PatternFill('solid',fgColor='EEF4FA')
                # 强制文字，避免以 = 开头的说明/名称成为 Excel 公式。
                if isinstance(c.value,str): c.data_type='s'
        ws.row_dimensions[1].height=32
        for col in ws.columns:
            ws.column_dimensions[col[0].column_letter].width=20
    guide.column_dimensions['A'].width=30;guide.column_dimensions['B'].width=115
    for i in range(2,guide.max_row+1): guide.row_dimensions[i].height=35
    for ws in tabs.values():
        for col,width in [('B',20),('C',27),('D',66),('F',28)]: ws.column_dimensions[col].width=width
    for i,k in enumerate(fields,1):
        basic.cell(1,i).comment=Comment('源码字段：'+k+'。空白表示未配置，可按同列其他单位的格式补值。','FightParty')
        if k in ('bonus','tags','target_layers','requires','counter','role'): basic.column_dimensions[basic.cell(1,i).column_letter].width=36
        options={'race':'terran,zerg,protoss,blight,neutral','armor_type':'none,light,heavy,special','layer':'ground,air','status':'ready,stub,summoned','damage_type':'physical,spell,true'}.get(k)
        if options:
            dv=DataValidation(type='list',formula1='"'+options+'"');dv.errorTitle='无效枚举';dv.error='请选择下拉选项';dv.showErrorMessage=True;ws=basic;ws.add_data_validation(dv);dv.add('%s3:%s%d'%(basic.cell(1,i).column_letter,basic.cell(1,i).column_letter,basic.max_row))
    if reviews:
        def mark(cell,item):
            cell.value=None
            cell.fill=PatternFill('solid',fgColor='E7E6E6' if item.get('kind')=='不适用' else 'FFF2CC')
            cell.comment=Comment(item['reason']+'\n当前运行兼容值：'+str(encode(item['runtime_value']))+'\n留空则保留兼容值，不代表已确认。','FightParty')
        for row in basic.iter_rows(min_row=3):
            uid=str(row[0].value)
            for i,field in enumerate(fields):
                if (uid,field) in reviews:mark(row[i],reviews[(uid,field)])
        for ws in tabs.values():
            for row in ws.iter_rows(min_row=3):
                key=(str(row[0].value),str(row[3].value))
                if key in reviews:mark(row[5],reviews[key])
        for row in todo.iter_rows(min_row=3):mark(row[3],reviews[(str(row[0].value),str(row[2].value))])
        for row in todo.iter_rows(min_row=3):todo.row_dimensions[row[0].row].height=48
        for col,width in [('C',62),('D',24),('E',72),('F',32),('G',72)]:todo.column_dimensions[col].width=width
    if reference:
        for row in inventory.iter_rows(min_row=3):
            inventory.row_dimensions[row[0].row].height=48
            if row[4].value=='{}':
                row[4].value=None
                row[4].fill=PatternFill('solid',fgColor='FFF2CC')
                row[4].comment=Comment('该能力的完整参数尚未核对，待人工补充；此页不直接导入技能实现。','FightParty')
        for col,width in [('C',36),('D',20),('E',80),('F',70),('G',72)]:inventory.column_dimensions[col].width=width
    destination.parent.mkdir(parents=True,exist_ok=True)
    wb.save(destination)
    print('已生成 %s（%d 个单位，保留源码原值）'%(destination,len(units)))


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT/'data/units.json')
    parser.add_argument('--output',type=Path,default=DEFAULT_WORKBOOK)
    args=parser.parse_args()
    if args.output.exists(): parser.error('目标文件已存在；为避免覆盖未导入编辑，请指定新的 --output 路径。')
    export_workbook(args.source,args.output)
