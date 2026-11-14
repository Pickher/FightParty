"""当前兵种工作簿导入器回归用例。只操作临时副本，不写游戏数据或存档。
运行：python -m unittest discover -s tests -p test_import_units.py
"""
import json
from pathlib import Path
import posixpath
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
WORKBOOK = ROOT / 'data/units/兵种配置.xlsx'
sys.path.insert(0, str(ROOT / 'tools'))
import import_units as importer
import unit_workbook

TAG = '{' + importer.NS['s'] + '}'


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.destination = self.folder / 'units.json'
        self.original = (ROOT / 'data/units.json').read_bytes()
        self.destination.write_bytes(self.original)
        self.current = json.loads(self.original.decode('utf-8-sig'))

    def workbook(self, changes=None, delete=False):
        """按工作表关系、字段键和兵种ID定位单元格，不依赖固定列号/页序。
        字段名含 / 时视为武器模式或技能参数页的参数路径，修改该行 F 列“数值”。"""
        edits = {}
        rows = importer.read_rows(WORKBOOK, '兵种属性')
        columns = {field: col for col, field in rows[2].items()}
        row_ids = {cells[columns['id']]: n for n, cells in rows.items() if n > 2}
        for (uid, field), value in (changes or {}).items():
            if '/' in field:
                sheet = '武器模式' if unit_workbook.is_weapon(field.split('/')) else '技能参数'
                params = importer.read_rows(WORKBOOK, sheet)
                row = next(n for n, cells in params.items() if n > 2 and cells.get('A') == uid and cells.get('D') == field)
                edits.setdefault(sheet, {})['F' + str(row)] = value
            else:
                edits.setdefault('兵种属性', {})[columns[field] + str(row_ids[uid])] = value
        path = self.folder / 'test.xlsx'
        with ZipFile(WORKBOOK) as source, ZipFile(path, 'w') as output:
            book = ET.fromstring(source.read('xl/workbook.xml'))
            relations = ET.fromstring(source.read('xl/_rels/workbook.xml.rels'))
            members = {}
            for sheet in book.findall('s:sheets/s:sheet', importer.NS):
                relation = sheet.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
                target = next(r.get('Target') for r in relations if r.get('Id') == relation)
                members[target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)] = sheet.get('name')
            for info in source.infolist():
                data = source.read(info.filename)
                name = members.get(info.filename)
                if name in edits or (delete and name == '兵种属性'):
                    tree = ET.fromstring(data)
                    row_nodes = tree.find(TAG + 'sheetData')
                    if delete and name == '兵种属性':
                        row_nodes.remove(next(r for r in row_nodes if r.get('r') == str(row_ids['rifle'])))
                    for address, value in edits.get(name, {}).items():
                        cell = next(c for c in tree.iter(TAG + 'c') if c.get('r') == address)
                        for child in list(cell): cell.remove(child)
                        if isinstance(value, str) and value.startswith('='):
                            cell.set('t', 'n')
                            ET.SubElement(cell, TAG + 'f').text = value[1:]
                            ET.SubElement(cell, TAG + 'v').text = '100'
                        elif isinstance(value, str):
                            cell.set('t', 'inlineStr')
                            ET.SubElement(ET.SubElement(cell, TAG + 'is'), TAG + 't').text = value
                        else:
                            cell.set('t', 'n')
                            ET.SubElement(cell, TAG + 'v').text = str(value)
                    data = ET.tostring(tree)
                output.writestr(info, data)
        return path

    def test_round_trip_and_noop(self):
        self.assertEqual(importer.parse_units(WORKBOOK, self.current), self.current['units'])
        self.assertIsNone(importer.import_units(WORKBOOK, self.destination))
        self.assertEqual(self.destination.read_bytes(), self.original)
        self.assertFalse((self.folder / 'backups').exists())

    def test_change_backup_and_unknown_fields(self):
        self.current['units']['rifle']['future_field'] = 17
        self.current['extra_metadata'] = 'preserve'
        before = json.dumps(self.current).encode()
        self.destination.write_bytes(before)
        backup = importer.import_units(self.workbook({('rifle', 'hp'): 555, ('rifle', 'color'): '001122'}), self.destination)
        result = json.loads(self.destination.read_text(encoding='utf-8'))
        self.assertEqual(result['units']['rifle']['hp'], 555)
        self.assertEqual(result['units']['rifle']['color'], '001122')
        self.assertEqual(result['units']['rifle']['future_field'], 17)
        self.assertEqual(result['units']['marauder']['skills'], self.current['units']['marauder']['skills'])
        self.assertEqual(result['extra_metadata'], 'preserve')
        self.assertEqual(backup.read_bytes(), before)

    def test_unknown_id_rejected(self):
        with self.assertRaises(ValueError):
            importer.parse_units(self.workbook({('rifle', 'id'): 'assassin'}), self.current)

    def test_dry_run(self):
        importer.import_units(self.workbook({('rifle', 'hp'): 600}), self.destination, True)
        self.assertEqual(self.destination.read_bytes(), self.original)
        self.assertFalse((self.folder / 'backups').exists())

    def test_invalid_input_never_writes(self):
        # 武器数值只保存在 attack_modes 内；特战队员第 0 个模式是 projectile，间隔必须大于 0。
        weapon = 'attack_modes/0/'
        for field, value in [(weapon + 'interval', 0), ('cost', 1.5), ('hp', -1), (weapon + 'interval', 'NaN'),
                             (weapon + 'damage', 'inf'), ('armor_type', 'medium'), ('color', 'zzz'),
                             ('id', 'move'), (weapon + 'damage', '=2*8'), ('hp', ''), (weapon + 'hit_count', 0),
                             (weapon + 'damage', -1), (weapon + 'range', -2)]:
            with self.subTest(field=field, value=value):
                with self.assertRaises(ValueError):
                    importer.import_units(self.workbook({('rifle', field): value}), self.destination)
                self.assertEqual(self.destination.read_bytes(), self.original)
                self.assertFalse((self.folder / 'backups').exists())

    def test_signed_speed_bonus(self):
        """交战机动的 speed_bonus 是加减量，允许为负；其他数值仍须非负。"""
        path = 'skills/combat_mobility/modifiers/0/speed_bonus'
        importer.import_units(self.workbook({('zergling', path): -0.75}), self.destination)
        result = json.loads(self.destination.read_text(encoding='utf-8'))
        self.assertEqual(result['units']['zergling']['skills']['combat_mobility']['modifiers'][0]['speed_bonus'], -0.75)
        self.destination.write_bytes(self.original)
        with self.assertRaises(ValueError):
            importer.import_units(self.workbook({('vanguard', 'skills/combat_mobility/modifiers/0/speed_multiplier'): -1}), self.destination)
        self.assertEqual(self.destination.read_bytes(), self.original)

    def test_delete_rejected(self):
        with self.assertRaises(ValueError):
            importer.import_units(self.workbook(delete=True), self.destination)


if __name__ == '__main__':
    unittest.main()
