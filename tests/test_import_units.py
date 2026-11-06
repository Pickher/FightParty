"""运行：python -m unittest discover -s tests -p test_import_units.py

所有写入发生在临时目录，不修改真正的 units.json 或玩家存档。
测试直接调整 XLSX 内的测试 XML，以覆盖 Excel 保存时的单元格表示。
"""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_units as importer

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
        self.extra_row = str(6 + len(self.current['units']))

    def workbook(self, changes=None, extra=False, delete=False):
        """从真实交付模板复制出测试输入，不依赖安装 Excel。"""
        path = self.folder / 'test.xlsx'
        with ZipFile(ROOT / 'data/兵种配置.xlsx') as source, ZipFile(path, 'w') as output:
            for name in source.namelist():
                data = source.read(name)
                if name == 'xl/worksheets/sheet1.xml':
                    tree = ET.fromstring(data)
                    rows = tree.find(TAG + 'sheetData')
                    if extra:
                        for existing in list(rows):
                            if existing.get('r') == self.extra_row:
                                rows.remove(existing)
                        row = copy.deepcopy(next(r for r in rows if r.get('r') == '6'))
                        row.set('r', self.extra_row)
                        for c in row:
                            c.set('r', c.get('r')[:-1] + self.extra_row)
                        rows.append(row)
                    if delete:
                        rows.remove(next(r for r in rows if r.get('r') == '6'))
                    for address, value in (changes or {}).items():
                        cell = next(c for c in tree.iter(TAG + 'c') if c.get('r') == address)
                        for child in list(cell):
                            cell.remove(child)
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
                output.writestr(name, data)
        return path

    def test_round_trip_and_noop(self):
        sheet = ROOT / 'data/兵种配置.xlsx'
        self.assertEqual(importer.parse_units(sheet, self.current), self.current['units'])
        self.assertIsNone(importer.import_units(sheet, self.destination))
        self.assertEqual(self.destination.read_bytes(), self.original)
        self.assertFalse((self.folder / 'backups').exists())

    def test_change_backup_and_unknown_fields(self):
        self.current['units']['rifle']['future_field'] = 17
        self.current['extra_metadata'] = 'preserve'
        before = json.dumps(self.current).encode()
        self.destination.write_bytes(before)
        backup = importer.import_units(self.workbook({'E6': 555, 'N6': '001122'}), self.destination)
        result = json.loads(self.destination.read_text(encoding='utf-8'))
        self.assertEqual(result['units']['rifle']['hp'], 555)
        self.assertEqual(result['units']['rifle']['color'], '001122')
        self.assertEqual(result['units']['rifle']['future_field'], 17)
        self.assertEqual(result['units']['marauder']['skills'], self.current['units']['marauder']['skills'])
        self.assertEqual(result['extra_metadata'], 'preserve')
        self.assertEqual(backup.read_bytes(), before)

    def test_new_unit(self):
        path = self.workbook({'A'+self.extra_row: 'assassin', 'B'+self.extra_row: '刺客'}, extra=True)
        units = importer.parse_units(path, self.current)
        self.assertEqual(len(units), len(self.current['units'])+1)
        self.assertEqual(units['assassin']['name'], '刺客')

    def test_dry_run(self):
        importer.import_units(self.workbook({'E6': 600}), self.destination, True)
        self.assertEqual(self.destination.read_bytes(), self.original)
        self.assertFalse((self.folder / 'backups').exists())

    def test_invalid_input_never_writes(self):
        for changes in [{'H6': 0}, {'D6': 1.5}, {'E6': -1}, {'H6': 'NaN'},
                        {'G6': 'inf'}, {'F6': 'medium'}, {'N6': 'zzz'},
                        {'A7': 'rifle'}, {'A6': 'changed_id'}, {'A6': 'move'},
                        {'G6': '=2*8'}, {'E6': ''}, {'D5': 'hp'}]:
            with self.subTest(changes=changes):
                with self.assertRaises(ValueError):
                    importer.import_units(self.workbook(changes), self.destination)
                self.assertEqual(self.destination.read_bytes(), self.original)
                self.assertFalse((self.folder / 'backups').exists())

    def test_delete_rejected(self):
        with self.assertRaises(ValueError):
            importer.import_units(self.workbook(delete=True), self.destination)


if __name__ == '__main__':
    unittest.main()
