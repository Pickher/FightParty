import re

def parse_unit_priority(input_file, output_file):
    # 正则表达式说明：
    # 1. <CUnit id="([^"]+)">  -> 匹配单位开始标签，并提取 id
    # 2. ([\s\S]*?)           -> 非贪婪匹配中间的所有内容（包括换行）
    # 3. <GlossaryPriority value="([^"]+)"/> -> 匹配目标行，并提取 value
    # 4. [\s\S]*?</CUnit>     -> 匹配直到单位结束标签
    
    # 这一段正则只匹配那些拥有 GlossaryPriority 的单位块
    pattern = re.compile(
        r'<CUnit id="(?P<id>[^"]+)">[\s\S]*?<GlossaryPriority value="(?P<val>[^"]+)"/>[\s\S]*?</CUnit>',
        re.MULTILINE
    )

    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            content = f.read()

        # 查找所有匹配项
        matches = pattern.findall(content)

        # 写入结果文件
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(f"总共找到 {len(matches)} 个含有 GlossaryPriority 的单位：\n")
            f.write("="*50 + "\n")
            f.write(f"{'单位ID (Unit ID)':<40} | {'优先级 (Priority)':<10}\n")
            f.write("-"*50 + "\n")
            
            # 按优先级数值从大到小排序（可选，如果你希望按顺序看的话）
            # 如果想按原文件顺序，删掉下面 sorted 这一行即可
            # 注意：这里按数字大小排序，方便你找规律
            sorted_matches = sorted(matches, key=lambda x: int(x[1]), reverse=True)

            for unit_id, priority in sorted_matches:
                f.write(f"{unit_id:<40} : {priority}\n")

        print(f"处理完成！结果已保存至 {output_file}")
        print(f"共提取了 {len(matches)} 条数据。")

    except FileNotFoundError:
        print(f"错误：找不到文件 {input_file}，请确认文件名正确。")
    except Exception as e:
        print(f"发生错误：{e}")

# --- 使用说明 ---
# 1. 请将你的原始数据保存为 'unitdata.xml' (或者修改下面的文件名)
# 2. 运行脚本
if __name__ == '__main__':
    # 假设你的原始数据文件名为 unitdata.xml
    input_filename = 'UnitData.xml'
    # 输出文件名为 priority_list.txt
    output_filename = 'priority_list.txt'
    
    parse_unit_priority(input_filename, output_filename)