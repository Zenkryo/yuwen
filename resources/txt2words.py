#! /usr/bin/env python3
import os
import glob
import re
import jieba
import json
import re
import unicodedata

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
        'b|p|m|f|d|t|n|l|g|k|h|j|q|x|zh|ch|sh|r|z|c|s|y|w'
    ).split('|')

    # 合法拼音韵母（涵盖常见韵母，支持带声调和无声调）
    finals = (
        'a|o|e|i|u|ü|ai|ei|ui|ao|ou|iu|ie|üe|ue|er|an|en|in|ang|eng|ing|ong|un|ün|'
        'ia|ian|iang|iong|iao|'
        'ua|uai|uan|uang|uo|r'
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
        sub_parts = part.split(' ')
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

# 解析现代汉语词典, 得到每个词，以及对应的拼音和释义
def parse_cidian():
    # 读取词典文件
    with open('XDHYCD7th.txt', 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('\u0251', 'a')
    content = content.replace('\u0261', 'g')
    content = content.replace('－', ' ')
    content = content.replace('’', ' ')
    content = content.replace('•', ' ')
    content = unicodedata.normalize('NFC', content)
    # 使用正则表达式匹配词条
    # 词条格式为：【词】拼音 释义
    pattern = r'【(.*?)】\s*\d*\s*([a-zA-Zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ̀ ]+)\s*(.*)'
    entries = re.findall(pattern, content)
    user_words = set()

    # 存储词条信息
    dictionary = {}
    for word, pinyin,defs in entries:
        if word.endswith('（儿）'):
            word = word[:-3]
        if len(word) > 1:
            pinyin_list = split_pinyin(pinyin)
            if pinyin_list[-1] == "r" and  not word.endswith("儿"):
                pinyin_list = pinyin_list[:-1]
            dictionary[word] = {'pinyin': pinyin_list, 'explanation': defs}
            user_words.add(word+ " 10000")
    # 生成分词词典
    if not os.path.exists('user_words.txt'):
        with open('user_words.txt', 'w', encoding='utf-8') as f:
            for word in user_words:
                f.write(word + "\n")
    
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
    all_chars = set()
    # load user words to jieba
    if os.path.exists('user_words.txt'):
        with open('user_words.txt', 'r', encoding='utf-8') as f:
            user_words = set(f.read().splitlines())
        jieba.load_userdict(user_words)
    jieba.del_word("匍匐前进")
    # 遍历每个txt文件
    for txt_file in txt_files:
        print(f'Processing {txt_file}...')
        
        # 读取文件内容
        with open(txt_file, 'r', encoding='utf-8') as f:
            text = f.read()
        # 只保留汉字和标点符号
        text = re.sub(r'[^\u4e00-\u9fff]', '', text)
        text = text.replace('\n', '')
        chars = set(text)
        all_chars.update(chars)
        # 使用jieba进行分词
        words = jieba.cut(text)
        words = list(words)
        # write to a file name .jieba
        with open(txt_file + '.jieba', 'w', encoding='utf-8') as f:
            f.write(' '.join(words))
        
        # 将词语添加到集合中
        all_words.update(words)
    return all_words,all_chars

# 读取常用成语
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

    # 解析课本, 得到课本中所有的词语和字符
    words,chars = parse_keben()
    
    # 解析成语3000
    chengyu300 = parse_chengyu300()

    all_words = words | chengyu300

    out_words = {}
    for word in sorted(all_words):
        if word in chengyu:
            out_words[word] = {'pinyin': chengyu[word]['pinyin'], 'explanation': chengyu[word]['explanation'], "chengyu": True}
            print(word," ", chengyu[word]['pinyin'], " ", chengyu[word]['explanation'])
        elif word in cidian:
            out_words[word] = {'pinyin': cidian[word]['pinyin'], 'explanation': cidian[word]['explanation'], "chengyu": False}
            print(word," ", cidian[word]['pinyin'], " ", cidian[word]['explanation'])
        elif len(word)>2:
            words1 = jieba.lcut(word)
            for word1 in words1:
                if word1 in cidian:
                    out_words[word] = {'pinyin': cidian[word1]['pinyin'], 'explanation': cidian[word1]['explanation'], "chengyu": False}
                    print(word," ", cidian[word1]['pinyin'], " ", cidian[word1]['explanation'])
                    break
    for char in sorted(chars):
        has_word = False
        for word in out_words:
            if char in word:
                has_word = True
                break
                # print(char," ------ ", word)
        if not has_word:
            for word in cidian:
                if word.startswith(char):
                    out_words[word] = {'pinyin': cidian[word]['pinyin'], 'explanation': cidian[word]['explanation'], "chengyu": False}
                    print(word," ", cidian[word]['pinyin'], " ", cidian[word]['explanation'])
                    has_word = True
                    break
        if not has_word:
            for word in cidian:
                if char in word:
                    out_words[word] = {'pinyin': cidian[word]['pinyin'], 'explanation': cidian[word]['explanation'], "chengyu": False}
                    print(word," ", cidian[word]['pinyin'], " ", cidian[word]['explanation'])
                    has_word = True
                    break
    # 将out_words写入all_words.json
    with open('all_words.json', 'w', encoding='utf-8') as f:
        json.dump(out_words, f, ensure_ascii=False)
