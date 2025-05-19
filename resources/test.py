#! /usr/bin/env python3
import os
import glob
import re
import jieba
import json
import re

def split_pinyin(pinyin):
    """
    将拼音字符串分隔为单个音节。
    每个音节由声母（可选）+韵母构成，韵母中最多有一个带声调的字母。
    支持带声调的拼音（如 lóngténghǔyuè → ['lóng', 'téng', 'hǔ', 'yuè']）、
    空格分隔（如 nǐ hǎo）、撇号分隔（如 xi'an）。
    """
    # 检查输入是否为空或非字符串
    if not pinyin or not isinstance(pinyin, str):
        return []

    # 规范化输入：替换单引号和分隔符
    pinyin = pinyin.replace("’", " ").replace("•", " ").strip()

    # 第一步：按空格分隔
    parts = re.split(r'[\s]+', pinyin)
    pinyin_list = []

    # 合法拼音声母（包括空声母）
    initials = (
        'b|p|m|f|d|t|n|l|g|k|h|j|q|x|zh|ch|sh|r|z|c|s|y|w|'
    ).split('|')

    # 合法拼音韵母（涵盖常见韵母，支持带声调和无声调）
    finals = (
        'a|o|e|i|u|ü|ai|ei|ui|ao|ou|iu|ie|ue|er|an|en|in|ang|eng|ing|ong|un|ün|'
        'ia|ian|iang|iong|iao|'
        'ua|uai|uan|uang|uo|'
    ).split('|')

    # 按长到短排序
    finals.sort(key=len, reverse=True)

    # 带声调的元音
    tones = r'[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]'

    # 构建正则表达式：
    # (声母)? (无声调韵母 | 带一个声调的韵母)
    # 无声调韵母：直接匹配 finals
    # 带声调韵母：替换韵母中的元音为带声调元音
    tone_finals = []
    for final in finals:
        if 'iu' == final:
            tone_finals.append('i[uūúǔù]')
        elif 'ui' == final:
            tone_finals.append('u[iīíǐì]')
        elif "a" in final:
            tone_finals.append(final.replace('a', '[aāáǎà]'))
        elif "o" in final:
            tone_finals.append(final.replace('o', '[oōóǒò]'))
        elif "e" in final:
            tone_finals.append(final.replace('e', '[eēéěè]'))
        elif final.startswith('i'):
            tone_finals.append(f'[iīíǐì]{final[1:]}')
        elif final.startswith('u'):
            tone_finals.append(f'[uūúǔù]{final[1:]}')
        elif final.startswith('ü'):
            tone_finals.append(f'[üǖǘǚǜ]{final[1:]}')
        elif final.startswith('v'):
            tone_finals.append(f'[vǖǘǚǜ]{final[1:]}')
        else:
            tone_finals.append(final)  # 无元音的韵母保持不变

    # 可选的声母部分+韵母部分
    syllable_pattern = rf"({'|'.join(initials)})?({'|'.join(tone_finals)})"
    print(syllable_pattern)
    for part in parts:
        # 处理撇号分隔的部分（例如 xi'an → xi + an）
        sub_parts = part.split('\'')
        for sub_part in sub_parts:
            if not sub_part:
                continue
            # 查找子部分中的所有音节
            matches = re.finditer(syllable_pattern, sub_part, re.IGNORECASE)
            syllables = [match.group(0) for match in matches if match.group(0)]  # 只保留非空匹配
            # 验证是否完全匹配整个子部分
            if syllables and ''.join(syllables) == sub_part:
                pinyin_list.extend(syllables)
            else:
                pinyin_list.append(sub_part)
    return pinyin_list


a = split_pinyin('zǔ’ài')
print(a)