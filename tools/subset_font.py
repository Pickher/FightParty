# 中文导读：可选的字体维护工具，不是运行游戏必需的环境。
# 仅当界面增加了字体里没有的汉字时使用；需要 Python + fonttools（原步骤也安装 brotli）。
# 参数是原始 NotoSansSC 可变字体路径，不要把项目中已经裁剪过的字体当作原字体输入。
# 当前扫描会同时收集脚本注释里的汉字，所以大量中文注释可能增大重新生成的字体子集。
"""Optional asset maintenance: pip install fonttools brotli; pass original NotoSansSC variable TTF.
The shipped subset covers the game's UI and data. Re-run after adding Chinese text.
"""
import pathlib, sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
# 根据当前脚本位置定位项目根目录。
root=pathlib.Path(__file__).resolve().parents[1]
# 先保留 ASCII 字符，再扫描代码与配置，收集需要显示的文字。
text=''.join(chr(i) for i in range(32,127))
for folder in ['scripts','data','tests']:
    for path in (root/folder).rglob('*'):
        if path.suffix in ['.gd','.json']:
            text+=path.read_text(encoding='utf-8')
font=TTFont(sys.argv[1])
# 固定字重为 500，让文字清晰可读；随后只保留收集到的字符以缩小体积。
font=instantiateVariableFont(font,{'wght':500},inplace=True)
options=subset.Options()
options.name_IDs=['*']
subsetter=subset.Subsetter(options=options)
subsetter.populate(text=text)
subsetter.subset(font)
# 覆盖项目字体资源；Godot 下次打开工程时会重新导入。
font.save(root/'assets'/'NotoSansSC.ttf')
print('UI font bytes:',(root/'assets'/'NotoSansSC.ttf').stat().st_size)
