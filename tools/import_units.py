#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将兵种 Excel 导入 JSON。只使用 Python 3.8+ 标准库，无需安装 Excel 或 pip 包。

XLSX 本质是 ZIP 中的一组 XML。兼容旧版“兵种”页及新版分表格式，
不执行宏、不依赖公式缓存。先完整校验，再备份，最后原子替换 JSON。
"""
import argparse
import copy
import json
import math
import os
from pathlib import Path
import posixpath
import re
import sys
import tempfile
from datetime import datetime
import xml.etree.ElementTree as ET
from zipfile import ZipFile, BadZipFile

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ['id', 'name', 'symbol', 'cost', 'hp', 'armor_type', 'damage', 'interval',
          'range', 'speed', 'splash', 'armor', 'shield', 'color', 'role', 'counter',
          'race', 'status', 'layer', 'target_layers', 'structure', 'bonus', 'skills',
          'pending', 'requires', 'sc2', 'attacks_base']
NUMBERS = {'cost', 'hp', 'damage', 'interval', 'range', 'speed', 'splash',
           'armor', 'shield'}
DEFAULTS = {'armor': 0, 'shield': 0, 'race': 'neutral', 'status': 'ready',
            'layer': 'ground', 'target_layers': ['ground'], 'structure': False,
            'bonus': {}, 'skills': {}, 'pending': [], 'requires': [], 'sc2': '',
            'attacks_base': True}
JSON_FIELDS = {'target_layers': list, 'bonus': dict, 'skills': dict, 'pending': list, 'requires': list}
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def read_rows(path, sheet_name="兵种"):
    """按工作表关系定位文件，兼容 Excel/WPS 的共享字符串和内联字符串。"""
    with ZipFile(path) as archive:
        # 防止误选超大文件；正常的配置表通常只有几十 KB。
        if sum(info.file_size for info in archive.infolist()) > 20_000_000:
            raise ValueError('工作簿解压后超过 20 MB，请使用单独的兵种配置表。')
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            strings = [''.join(item.itertext()) for item in
                       ET.fromstring(archive.read('xl/sharedStrings.xml'))]
        book = ET.fromstring(archive.read('xl/workbook.xml'))
        sheet = next((s for s in book.findall('s:sheets/s:sheet', NS)
                      if s.get('name') == sheet_name), None)
        if sheet is None:
            raise ValueError('找不到“%s”工作表，请勿更改页签名称。' % sheet_name)
        relation_id = sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
        relations = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        target = next(r.get('Target') for r in relations if r.get('Id') == relation_id)
        member = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
        rows = {}
        for row in ET.fromstring(archive.read(member)).findall('s:sheetData/s:row', NS):
            row_number = int(row.get('r'))
            cells = {}
            for cell in row.findall('s:c', NS):
                address = cell.get('r')
                column = re.match(r'[A-Z]+', address).group()
                value_node = cell.find('s:v', NS)
                value = value_node.text if value_node is not None else ''
                kind = cell.get('t', 'n')
                if cell.find('s:f', NS) is not None:
                    # 不用缓存值：Excel 未重算时，缓存可能仍是上一次的结果。
                    value = ('formula', address)
                elif kind == 's':
                    value = strings[int(value)]
                elif kind == 'inlineStr':
                    value = ''.join(t.text or '' for t in cell.findall('.//s:t', NS))
                elif kind in ('e', 'b', 'd'):
                    value = ('unsupported', address)
                cells[column] = value or ''
            rows[row_number] = cells
        return rows


def parse_units(path, current):
    """通过第 5 行的英文键匹配列，因此可以整列移动，但不能删字段。"""
    with ZipFile(path) as archive:
        book = ET.fromstring(archive.read('xl/workbook.xml'))
        if any(s.get('name') == '源数据' for s in book.findall('s:sheets/s:sheet', NS)):
            from unit_workbook import parse_workbook
            return parse_workbook(path, current, read_rows)
    if any('attack_modes' in unit for unit in current['units'].values()):
        raise ValueError('当前源码已使用独立攻击模式；旧版“兵种”单页格式无法表达这些数据，请使用data/units/兵种配置.xlsx。')
    rows = read_rows(path)
    headers = rows.get(5, {})
    if len(headers.values()) != len(set(str(v) for v in headers.values())):
        raise ValueError('第 5 行存在重复字段。')
    if set(headers.values()) != set(FIELDS):
        raise ValueError('第 5 行必须保留全部英文列名：' + ', '.join(FIELDS))
    units = {}
    for row_number, cells in sorted(rows.items()):
        if row_number <= 5 or not any(v != '' for v in cells.values()):
            continue
        if any(v != '' for col, v in cells.items() if col not in headers):
            raise ValueError('第 %d 行在字段范围外有内容，请移到“填写说明”页。' % row_number)
        unit = {}
        for col, field in headers.items():
            raw = cells.get(col, '')
            where = '第 %d 行，%s (%s)' % (row_number, field, col)
            if isinstance(raw, tuple):
                raise ValueError(where + '：不支持公式、错误值、日期或布尔值，请填普通文字/数字。')
            raw = str(raw).strip()
            if field in JSON_FIELDS:
                try:
                    value = json.loads(raw, parse_constant=lambda s: (_ for _ in ()).throw(ValueError(s)))
                except ValueError:
                    raise ValueError(where + '：必须是合法 JSON，字符串用英文双引号。')
                if not isinstance(value, JSON_FIELDS[field]):
                    raise ValueError(where + '：JSON 类型错误。')
                unit[field] = value
                continue
            if field in ('structure', 'attacks_base'):
                if raw.lower() not in ('true', 'false'):
                    raise ValueError(where + '：只能填写 true 或 false。')
                unit[field] = raw.lower() == 'true'
                continue
            if not raw and field != 'sc2':
                raise ValueError(where + '：不能为空（无范围伤害请填 0）。')
            if field in NUMBERS:
                try:
                    value = float(raw)
                except ValueError:
                    raise ValueError(where + '：必须填写数字。')
                if not math.isfinite(value) or value < 0:
                    raise ValueError(where + '：必须是有限的非负数。')
                if field in ('hp', 'interval') and value <= 0:
                    raise ValueError(where + '：必须大于 0。')
                if field == 'cost' and not value.is_integer():
                    raise ValueError(where + '：价格必须是正整数。')
                unit[field] = int(value) if value.is_integer() else value
            else:
                unit[field] = raw
        key = unit.pop('id')
        if not re.fullmatch(r'[a-z][a-z0-9_]*', key) or key in ('erase', 'move'):
            raise ValueError('第 %d 行：ID 使用小写英文字母、数字、下划线，以字母开头；不能用 erase/move。' % row_number)
        if key in units:
            raise ValueError('第 %d 行：重复 ID %s。' % (row_number, key))
        if unit['armor_type'] not in ('none', 'light', 'heavy', 'special'):
            raise ValueError('第 %d 行：armor_type 只能是 none / light / heavy / special。' % row_number)
        if unit['race'] not in ('terran', 'zerg', 'protoss', 'blight', 'neutral') or unit['status'] not in ('ready', 'stub'):
            raise ValueError('第 %d 行：种族或实装状态无效。' % row_number)
        if unit['layer'] not in ('ground', 'air') or not unit['target_layers'] or any(x not in ('ground', 'air') for x in unit['target_layers']):
            raise ValueError('第 %d 行：层级只能使用 ground / air。' % row_number)
        if unit['cost'] == 0 and not unit['structure']:
            raise ValueError('第 %d 行：只有建筑价格可以为 0。' % row_number)
        if any(not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v) or v < 0 for v in unit['bonus'].values()):
            raise ValueError('第 %d 行：bonus 加成必须为非负有限数。' % row_number)
        if not re.fullmatch(r'[0-9a-fA-F]{6}', unit['color']):
            raise ValueError('第 %d 行：color 必须是 6 位十六进制文本，例如 7ed8ed，不含 #。' % row_number)
        if len(unit['symbol']) != 1:
            raise ValueError('第 %d 行：symbol 必须是单个字符。' % row_number)
        # 未来代码增加的其他字段不会被旧版表格悄悄删除。
        preserved = copy.deepcopy(current['units'].get(key, {}))
        # 可选字段在表格里展示默认值，但不强行写回原来未配置的字段。
        for field, default in DEFAULTS.items():
            if field not in preserved and unit.get(field) == default:
                unit.pop(field, None)
        preserved.update(unit)
        units[key] = preserved
    if not units:
        raise ValueError('表中没有兵种数据。')
    missing = set(current['units']) - set(units)
    if missing:
        raise ValueError('不能删除或改名已有 ID（存档/AI 可能引用）：' + ', '.join(sorted(missing)))
    return units


def import_units(excel, destination, check_only=False):
    """失败不修改原文件；同样的数据重复导入不产生无意义的备份。"""
    original = destination.read_bytes()
    current = json.loads(original.decode('utf-8-sig'))
    units = parse_units(excel, current)
    result = copy.deepcopy(current)
    result['units'] = units
    changed = [key for key in units if units[key] != current['units'].get(key)]
    print('校验通过：%d 个兵种；变更：%s' % (len(units), ', '.join(changed) or '无'))
    if check_only or result == current:
        print('仅校验，未写入。' if check_only else '数据相同，未写入。')
        return None
    payload = (json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode('utf-8')
    backup_dir = destination.parent / 'backups'
    backup_dir.mkdir(exist_ok=True)
    backup = backup_dir / ('units-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
    backup.write_bytes(original)
    temporary = None
    try:
        # 同目录临时文件 + os.replace，避免写到一半留下残缺 JSON。
        with tempfile.NamedTemporaryFile(dir=destination.parent, suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(str(temporary), str(destination))
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    print('已写入：%s\n原文件备份：%s\n请关闭游戏并重新打开，已有安装包需要重新打包。' % (destination, backup))
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('excel', nargs='?', type=Path, default=ROOT / 'data' / 'units' / '兵种配置.xlsx')
    parser.add_argument('--output', type=Path, default=ROOT / 'data' / 'units.json')
    parser.add_argument('--check', action='store_true', help='只校验，不写 JSON')
    args = parser.parse_args()
    try:
        import_units(args.excel.resolve(), args.output.resolve(), args.check)
    except (ValueError, OSError, BadZipFile, ET.ParseError, KeyError, StopIteration, IndexError, TypeError) as error:
        print('导入失败：%s\n原 units.json 未被替换。' % error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    sys.exit(main())
