"""Optional asset maintenance: pip install fonttools brotli; pass original NotoSansSC variable TTF.
The shipped subset covers the game's UI and data. Re-run after adding Chinese text.
"""
import pathlib, sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
root=pathlib.Path(__file__).resolve().parents[1]
text=''.join(chr(i) for i in range(32,127))
for folder in ['scripts','data','tests']:
    for path in (root/folder).rglob('*'):
        if path.suffix in ['.gd','.json']:
            text+=path.read_text(encoding='utf-8')
font=TTFont(sys.argv[1])
font=instantiateVariableFont(font,{'wght':500},inplace=True)
options=subset.Options()
options.name_IDs=['*']
subsetter=subset.Subsetter(options=options)
subsetter.populate(text=text)
subsetter.subset(font)
font.save(root/'assets'/'NotoSansSC.ttf')
print('UI font bytes:',(root/'assets'/'NotoSansSC.ttf').stat().st_size)
