"""中文导读：由 data/units.json 生成 docs/UNIT_TABLE.md 兵种数值总表，只读数据，不改游戏配置。
用法：python tools/unit_table.py            覆盖写入 docs/UNIT_TABLE.md
      python tools/unit_table.py --check    只比较，表格过期时返回 1（改数值后提醒重新生成）
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'docs/UNIT_TABLE.md'
RACES = [('terran', '人族'), ('zerg', '虫族'), ('protoss', '神族'), ('blight', '腐族'), ('neutral', '中立结构')]
ARMOR = {'none': '无', 'light': '轻', 'heavy': '重', 'special': '特殊'}
LAYER = {'ground': '地', 'air': '空'}
STATUS = {'ready': '可用', 'stub': '预留', 'summoned': '召唤物'}


def number(value):
    return '%g' % value if isinstance(value, (int, float)) else str(value)


def weapon(mode):
    text = number(mode['damage'])
    bonuses = ['+%s%s' % (number(v), {'light': '轻', 'heavy': '重'}.get(k, k)) for k, v in (mode.get('bonus') or {}).items()]
    bonuses += ['+%s %s' % (number(v), k) for k, v in (mode.get('bonus_tags') or {}).items()]
    if bonuses: text += '（' + '、'.join(bonuses) + '）'
    if mode.get('hit_count', 1) > 1: text += '×%d' % mode['hit_count']
    text += ' / %s / %s' % (number(mode['interval']), number(mode['range']))
    if mode.get('splash'): text += '，溅射 %s' % number(mode['splash'])
    if 'healing' in mode: text += '，治疗 %s' % number(mode['healing'])
    layers = '、'.join(LAYER[x] for x in mode['target_layers'])
    return '%s %s（%s，%s）' % (mode['label'], text, layers, mode.get('delivery', {}).get('type', ''))


def render(data):
    units = data['units']
    lines = ['# 兵种数值总表', '',
             '> 由 `python tools/unit_table.py` 从 `data/units.json`（规则 %s）生成，请勿手改；改数值后重新生成。' % data.get('version', ''),
             '> 价格按组（每组 `spawn_count` 名），生命、护盾、伤害按个体。间隔单位秒，射程与速度单位格、格/秒。',
             '> 攻击模式列：伤害（类型/标签加成）×每轮段数 / 轮后间隔 / 射程（可打的层，投送类型）。', '']
    for race, label in RACES:
        lines += ['## %s `%s`' % (label, race), '',
                  '| ID | 名称 | 状态 | 价格 矿/气/核 | 每组 | 生命/护盾 | 护甲 | 层 | 速度 | 攻击模式 | 技能组件 |',
                  '|---|---|---|---|---:|---|---|---|---:|---|---|']
        for uid, unit in units.items():
            if unit.get('race') != race: continue
            status = STATUS.get(unit.get('status'), '结构体' if unit.get('structure') else '—')
            if not unit.get('available', True): status = '暂时停用'
            cost = '%d/%d/%d' % (unit['cost'], unit.get('gas_cost', 0), unit.get('core_cost', 0))
            health = number(unit['hp']) + ('/' + number(unit['shield']) if unit.get('shield') else '')
            armor = '%s %s' % (ARMOR[unit['armor_type']], number(unit['armor']))
            modes = '<br>'.join(weapon(m) for m in unit.get('attack_modes', [])) or '—'
            skills = '、'.join('`%s`' % k for k in unit.get('skills', {})) or '—'
            lines.append('| `%s` | %s | %s | %s | %d | %s | %s | %s | %s | %s | %s |' % (
                uid, unit['name'], status, cost, unit.get('spawn_count', 1), health, armor,
                LAYER[unit.get('layer', 'ground')], number(unit['speed']), modes, skills))
        lines.append('')
    return '\n'.join(lines)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    text = render(json.loads((ROOT / 'data/units.json').read_text(encoding='utf-8-sig')))
    if args.check:
        current = DESTINATION.read_text(encoding='utf-8') if DESTINATION.exists() else ''
        if current != text:
            print('docs/UNIT_TABLE.md 已过期：请运行 python tools/unit_table.py')
            raise SystemExit(1)
        print('docs/UNIT_TABLE.md 与 data/units.json 一致')
    else:
        DESTINATION.write_text(text, encoding='utf-8')
        print('已生成', DESTINATION)
