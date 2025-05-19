#! /usr/bin/env python3
import os
import glob
import re
import jieba
import json

def split_pinyin(pinyin):
    # 先按空格或分隔符（'•', ''', "'"）分割成多个部分
    parts = re.split(r'[\s•’]+', pinyin)
    
    # 对每个部分单独进行拼音分割
    pinyin_list = []
    for part in parts:
        # 匹配带声调的字母或普通音节，正确处理 qu, ju, xu, yu 等情况
        sub_matches = re.finditer(
            r'(?:[b-df-hj-np-tv-z]|qu|ju|xu|yu)[a-z]*[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]?[a-z]*',
            part,
            re.IGNORECASE
        )
        pinyin_list.extend([match.group(0) for match in sub_matches])
    
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
    pattern = r'【(.*?)】\s*\d*\s*([a-zA-Zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ•'']+)\s*(.*)'
    entries = re.findall(pattern, content)
    
    # 存储词条信息
    dictionary = {}
    for word, pinyin,defs in entries:
        if len(word) > 1:
            if word == "龙腾虎跃":
                print(pinyin)
            pinyin_list = split_pinyin(pinyin)
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

    for word in sorted(all_words):
        if word in cidian:
            print(word," ", cidian[word]['pinyin'], " ", cidian[word]['explanation'])
        elif word in chengyu:
            print(word," ", chengyu[word]['pinyin'], " ", chengyu[word]['explanation'])
