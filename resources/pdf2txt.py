#! /usr/bin/env python3
import os
import glob
import pdfplumber

# 获取当前目录下所有的pdf文件
pdf_files = glob.glob('*.pdf')

# 遍历每个pdf文件
for pdf_file in pdf_files:
    print(f'Processing {pdf_file}...')
    # 生成对应的txt文件名
    txt_file = os.path.splitext(pdf_file)[0] + '.txt'
    # 如果txt文件存在，则跳过
    if os.path.exists(txt_file):
        print(f'{txt_file} already exists, skipping...')
        continue
    # 打开pdf文件并提取文本
    with pdfplumber.open(pdf_file) as pdf:
        text = ''
        # 遍历每一页
        for page in pdf.pages:
            print(f'Processing page {page.page_number}...')
            text += page.extract_text() + '\n'
    
    # 将提取的文本写入txt文件
    with open(txt_file, 'w', encoding='utf-8') as f:
        f.write(text)





