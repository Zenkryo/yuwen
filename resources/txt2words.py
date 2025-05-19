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

def process_special_chars(text):
    """
    将文本中的全角字符（字母、数字）转换为半角字符。
    同时将拉丁文小写草书字母和其他特殊拉丁字母转换为对应的ASCII字母。
    """
    # 第一步：转换全角字符
    trans_dict1 = str.maketrans(
        'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ０１２３４５６７８９',
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    )
    
    # 第二步：转换拉丁文小写草书字母
    trans_dict2 = str.maketrans(
        '𝓪𝓫𝓬𝓭𝓮𝓯𝓰𝓱𝓲𝓳𝓴𝓵𝓶𝓷𝓸𝓹𝓺𝓻𝓼𝓽𝓾𝓿𝔀𝔁𝔂𝔃',
        'abcdefghijklmnopqrstuvwxyz'
    )
    
    # 第三步：转换其他特殊拉丁字母
    special_chars = 'ɡɢʛɕʗɖɗɘəɚɛɜɝɞɟɠɡɢɣɤɥɦɧɨɩɪɫɬɭɮɯɰɱɲɳɴɵɶɷɸɹɺɻɼɽɾɿʀʁʂʃʄʅʆʇʈʉʊʋʌʍʎʏʐʑʒʓʔʕʖʗʘʙʚʛʜʝʞʟʠʡʢʣʤʥʦʧʨʩʪʫ'
    normal_chars = 'gggccdddeeeeeeefggghhiiilllllmmmmnnnooopprrrrrrsssttuuvvwwyyzzzqhhkkllqqqzzzzzzzzzzzzzzzzzz'
    
    trans_dict3 = str.maketrans(special_chars, normal_chars)
    
    # 第四步：转换上标数字
    trans_dict4 = str.maketrans(
        '⁰¹²³⁴⁵⁶⁷⁸⁹',
        '0123456789'
    )
    
    # 执行转换
    text = text.translate(trans_dict1)
    text = text.translate(trans_dict2)
    text = text.translate(trans_dict3)
    text = text.translate(trans_dict4)
    
    # 全角空格 (U+3000) 转换为半角空格 (U+0020)
    text = text.replace('　', ' ')
    
    return text

# 解析现代汉语词典, 得到每个词，以及对应的拼音和释义
def parse_cidian():
    # 读取词典文件
    with open('XDHYCD7th.txt', 'r', encoding='utf-8') as f:
        content = f.read()
    content = process_special_chars(content)
    # 使用正则表达式匹配词条
    # 词条格式为：【词】拼音 释义
    pattern = r'【(.*?)】\s*\d*\s*([a-zA-Zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ•’]+)\s*(.*)'
    entries = re.findall(pattern, content)
    
    # 存储词条信息
    dictionary = {}
    for word, pinyin,defs in entries:
        if len(word) > 1:
            if word == "龙腾虎跃":
                print(pinyin)
            pinyin_list = split_pinyin(pinyin)
            if len(word) != len(pinyin_list):
                print(word, pinyin, pinyin_list, defs)
            dictionary[word] = {'pinyin': pinyin_list, 'explanation': defs}
    
    return dictionary

# 解析成语词典, 得到每个成语，以及对应的拼音，解释，出处，例句
def parse_chengyu():
    with open('idiom.json', 'r', encoding='utf-8') as f:
        idiom_dict = json.load(f)
    idioms = {}
    for idiom in idiom_dict:
        idioms[idiom['word']] = idiom
        pinyin_list = split_pinyin(idiom['pinyin'])
        idioms[idiom['word']]['pinyin'] = pinyin_list
    return idioms

# 解析课本，得到课本中所有的词语
def parse_keben():
    # 获取当前目录下所有的txt文件
    txt_files = glob.glob('语文*.txt')

    # 用于存储所有不重复的词语
    all_words = set()

    # 遍历每个txt文件
    for txt_file in txt_files:
        print(f'Processing {txt_file}...')
        
        # 读取文件内容
        with open(txt_file, 'r', encoding='utf-8') as f:
            text = f.read()
        
        # 只保留汉字和标点符号
        text = re.sub(r'[^\u4e00-\u9fff\s]', '', text)
        
        # 使用jieba进行分词
        words = jieba.cut(text)
        
        # 将词语添加到集合中
        all_words.update(words)
    return all_words

def parse_chengyu300():
    with open('成语300.txt', 'r', encoding='utf-8') as f:
        content = f.read()
    words = set()
    for line in content.split('\n'):
        for word in line.split(' '):
            if word not in words:
                words.add(word)
    return words



if __name__ == '__main__':
    # 解析现代汉语词典
    cidian = parse_cidian()

    # 解析成语词典
    chengyu = parse_chengyu()

    # 解析课本
    words = parse_keben()

    # 解析成语3000
    chengyu300 = parse_chengyu300()

    all_words = words | chengyu300

    # for word in sorted(all_words):
    #     if word in cidian:
    #         print(word," ", cidian[word]['pinyin'], " ", cidian[word]['explanation'])
    #     elif word in chengyu:
    #         print(word," ", chengyu[word]['pinyin'], " ", chengyu[word]['explanation'])
